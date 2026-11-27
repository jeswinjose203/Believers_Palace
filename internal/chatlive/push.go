package chatlive

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

type PushWorker struct {
	Postgres
	client   *http.Client
	endpoint string
}

func NewPushWorker(ctx context.Context, db Postgres, project string) (*PushWorker, error) {
	credentials, err := google.FindDefaultCredentials(ctx, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, fmt.Errorf("load FCM application default credentials: %w", err)
	}
	client := oauth2.NewClient(ctx, credentials.TokenSource)
	client.Timeout = 10 * time.Second
	return &PushWorker{Postgres: db, client: client,
		endpoint: "https://fcm.googleapis.com/v1/projects/" + project + "/messages:send"}, nil
}

type delivery struct {
	id                                     int64
	messageID, kind, roomID, userID, token string
	attempts                               int
}

// Run leases delivery work across replicas. An expired lease is retried after
// a process crash. Provider tags keep retries of the same message together.
func (p *PushWorker) Run(ctx context.Context) {
	for ctx.Err() == nil {
		expansion, err := p.expand(ctx)
		if err == nil {
			var deliveryCount int
			deliveryCount, err = p.deliverBatch(ctx)
			if err == nil && (expansion > 0 || deliveryCount > 0) {
				continue
			}
		}
		if err != nil && ctx.Err() == nil {
			slog.Warn("chat push queue stalled", "error", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}

func (p *PushWorker) expand(ctx context.Context) (int64, error) {
	tag, err := p.Pool.Exec(ctx, `
		WITH claimed AS (
			SELECT * FROM chat_push_jobs ORDER BY created_at,message_id LIMIT 16 FOR UPDATE SKIP LOCKED
		), audience AS (
			SELECT j.*, cm.user_id AS recipient
			FROM claimed j JOIN community_memberships cm ON cm.community_id=j.room_id AND cm.status='active'
			WHERE j.kind='community' AND j.created_at > now()-interval '1 hour'
			UNION ALL
			SELECT j.*, pref.user_id
			FROM claimed j JOIN chat_notification_preferences pref
			  ON pref.kind='event' AND pref.room_id=j.room_id AND NOT pref.muted
			WHERE j.kind='event' AND j.created_at > now()-interval '1 hour'
		), expanded AS (
			INSERT INTO chat_push_deliveries (message_id, kind, room_id, user_id, token)
			SELECT a.message_id, a.kind, a.room_id, a.recipient, d.token
			FROM audience a JOIN chat_push_devices d ON d.user_id=a.recipient
			WHERE d.updated_at > now()-interval '60 days'
			  AND a.sender_id IS DISTINCT FROM a.recipient
		)
		DELETE FROM chat_push_jobs USING claimed WHERE chat_push_jobs.message_id=claimed.message_id`)
	return tag.RowsAffected(), err
}

func (p *PushWorker) deliverBatch(ctx context.Context) (int, error) {
	rows, err := p.Pool.Query(ctx, `
		WITH claimed AS (
			SELECT id FROM chat_push_deliveries WHERE next_attempt <= now()
			ORDER BY next_attempt,id LIMIT 16 FOR UPDATE SKIP LOCKED
		)
		UPDATE chat_push_deliveries d SET attempts=attempts+1, next_attempt=now()+interval '2 minutes'
		FROM claimed WHERE d.id=claimed.id
		RETURNING d.id,d.message_id,d.kind,d.room_id,d.user_id,d.token,d.attempts`)
	if err != nil {
		return 0, err
	}
	batch := make([]delivery, 0, 16)
	for rows.Next() {
		var d delivery
		if err := rows.Scan(&d.id, &d.messageID, &d.kind, &d.roomID, &d.userID, &d.token, &d.attempts); err != nil {
			rows.Close()
			return 0, err
		}
		batch = append(batch, d)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	var group sync.WaitGroup
	for _, d := range batch {
		group.Add(1)
		go func() {
			defer group.Done()
			if err := p.deliver(ctx, d); err != nil && ctx.Err() == nil {
				slog.Warn("chat push delivery could not be finalized", "error", err)
			}
		}()
	}
	group.Wait()
	return len(batch), nil
}

// Check current ownership, mute and room access immediately before sending.
func (p *PushWorker) eligible(ctx context.Context, d delivery) (bool, error) {
	var allowed bool
	err := p.Pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM users u JOIN chat_push_devices d ON d.user_id=u.id
			WHERE u.id=$1 AND d.token=$2
			  AND NOT EXISTS (SELECT 1 FROM chat_notification_preferences p
				WHERE p.user_id=u.id AND p.kind=$3 AND p.room_id=$4 AND p.muted)
			  AND (
				($3='community' AND EXISTS (SELECT 1 FROM community_memberships m
					WHERE m.community_id=$4 AND m.user_id=u.id AND m.status='active')
					AND EXISTS (SELECT 1 FROM community_messages WHERE id=$5))
				OR
				($3='event' AND EXISTS (SELECT 1 FROM events e WHERE e.id=$4 AND (
					NOT e.registration_required OR u.role='super_admin'
					OR (u.church_id=e.church_id AND u.role IN ('church_admin','priest','associate_priest'))
					OR EXISTS (SELECT 1 FROM event_registrations r WHERE r.event_id=e.id AND r.user_id=u.id)))
					AND EXISTS (SELECT 1 FROM event_messages WHERE id=$5))
			  )
		)`, d.userID, d.token, d.kind, d.roomID, d.messageID).Scan(&allowed)
	return allowed, err
}

func (p *PushWorker) deliver(ctx context.Context, d delivery) error {
	allowed, err := p.eligible(ctx, d)
	if err != nil {
		return err
	}
	if allowed && d.attempts <= 8 {
		retry, unregister, delay := p.send(ctx, d)
		if unregister {
			_, err := p.Pool.Exec(ctx, "DELETE FROM chat_push_devices WHERE token=$1 AND user_id=$2", d.token, d.userID)
			return err
		}
		if retry && d.attempts < 8 {
			_, err := p.Pool.Exec(ctx, "UPDATE chat_push_deliveries SET next_attempt=$2 WHERE id=$1", d.id, time.Now().Add(delay))
			return err
		}
	}
	_, err = p.Pool.Exec(ctx, "DELETE FROM chat_push_deliveries WHERE id=$1", d.id)
	return err
}

func (p *PushWorker) send(ctx context.Context, d delivery) (retry, unregister bool, delay time.Duration) {
	delay = time.Minute * time.Duration(1<<min(d.attempts-1, 5))
	payload, _ := json.Marshal(map[string]any{"message": map[string]any{
		"fid":          d.token,
		"notification": map[string]string{"title": "Believers Palace", "body": "New chat message"},
		"data":         map[string]string{"kind": d.kind, "roomId": d.roomID, "messageId": d.messageID},
		"android":      map[string]any{"notification": map[string]string{"tag": d.messageID, "channel_id": "chat_messages"}},
		"apns":         map[string]any{"headers": map[string]string{"apns-collapse-id": d.messageID}},
	}})
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, p.endpoint, bytes.NewReader(payload))
	if err != nil {
		return false, false, 0
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := p.client.Do(request)
	if err != nil {
		return true, false, delay
	}
	defer response.Body.Close()
	if response.StatusCode < 300 {
		return false, false, 0
	}
	var result struct {
		Error struct {
			Details []struct {
				Code string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	_ = json.NewDecoder(io.LimitReader(response.Body, 64<<10)).Decode(&result)
	for _, detail := range result.Error.Details {
		if detail.Code == "UNREGISTERED" {
			return false, true, 0
		}
	}
	if seconds, err := strconv.Atoi(response.Header.Get("Retry-After")); err == nil && seconds > 0 {
		delay = max(delay, time.Duration(seconds)*time.Second)
	} else if retryAt, err := http.ParseTime(response.Header.Get("Retry-After")); err == nil {
		delay = max(delay, time.Until(retryAt))
	}
	slog.Warn("chat push rejected by provider", "status", response.StatusCode)
	return response.StatusCode == 429 || response.StatusCode >= 500, false, delay
}
