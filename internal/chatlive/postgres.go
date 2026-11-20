package chatlive

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"time"

	"believers_palace/internal/auth"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Postgres struct{ Pool *pgxpool.Pool }

func (p Postgres) Issue(ctx context.Context, hash string, id auth.Identity) error {
	_, err := p.Pool.Exec(ctx, `INSERT INTO chat_live_tickets (token_hash,user_id,role,church_id)
		VALUES ($1,$2,$3,$4)`, hash, id.UserID, string(id.Role), id.ChurchID)
	return err
}

func (p Postgres) Consume(ctx context.Context, hash string) (auth.Identity, bool, error) {
	var id auth.Identity
	err := p.Pool.QueryRow(ctx, `DELETE FROM chat_live_tickets
		WHERE token_hash=$1 AND expires_at > now() RETURNING user_id,role,church_id`, hash).
		Scan(&id.UserID, &id.Role, &id.ChurchID)
	if errors.Is(err, pgx.ErrNoRows) {
		return id, false, nil
	}
	return id, err == nil, err
}

func (p Postgres) Run(ctx context.Context, hub *Hub) {
	go p.expireTickets(ctx)
	config := p.Pool.Config().ConnConfig
	for ctx.Err() == nil {
		if err := p.listen(ctx, config, hub); err != nil && ctx.Err() == nil {
			slog.Warn("chat database listener disconnected", "error", err)
		}
		hub.setAvailable(false)
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}

func (p Postgres) listen(ctx context.Context, config *pgx.ConnConfig, hub *Hub) error {
	conn, err := pgx.ConnectConfig(ctx, config.Copy())
	if err != nil {
		return err
	}
	defer conn.Close(context.Background())
	if _, err := conn.Exec(ctx, "LISTEN chat_changes"); err != nil {
		return err
	}
	hub.setAvailable(true)
	for {
		notification, err := conn.WaitForNotification(ctx)
		if err != nil {
			return err
		}
		var signal Signal
		if json.Unmarshal([]byte(notification.Payload), &signal) == nil {
			hub.Publish(signal.Kind, signal.ID, signal.Deleted)
		}
	}
}

func (p Postgres) expireTickets(ctx context.Context) {
	timer := time.NewTicker(time.Minute)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			if _, err := p.Pool.Exec(ctx, "DELETE FROM chat_live_tickets WHERE expires_at <= now()"); err != nil && ctx.Err() == nil {
				slog.Warn("could not expire chat tickets", "error", err)
			}
		}
	}
}
