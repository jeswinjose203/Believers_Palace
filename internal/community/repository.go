package community

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("community resource not found")
var ErrConflict = errors.New("membership request already exists")
var ErrLastAdmin = errors.New("the only community admin cannot leave")

type Repository struct{ pool *pgxpool.Pool }

func NewRepository(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

func scanCommunity(row pgx.Row) (*Community, error) {
	var c Community
	err := row.Scan(&c.ID, &c.CreatorID, &c.Name, &c.Description, &c.CreatedAt)
	return &c, err
}

func (r *Repository) Create(ctx context.Context, userID, name, description string) (*Community, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin community creation: %w", err)
	}
	defer tx.Rollback(ctx)
	var c Community
	err = tx.QueryRow(ctx, `INSERT INTO communities (creator_id,name,description) VALUES ($1,$2,$3)
		RETURNING id,creator_id,name,description,created_at`, userID, name, description).
		Scan(&c.ID, &c.CreatorID, &c.Name, &c.Description, &c.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("create community: %w", err)
	}
	_, err = tx.Exec(ctx, `INSERT INTO community_memberships (community_id,user_id,status,is_admin) VALUES ($1,$2,'active',true)`, c.ID, userID)
	if err != nil {
		return nil, fmt.Errorf("add creator membership: %w", err)
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit community: %w", err)
	}
	c.Status = "active"
	c.IsAdmin = true
	return &c, nil
}

func (r *Repository) List(ctx context.Context, userID string) ([]Community, error) {
	rows, err := r.pool.Query(ctx, `SELECT c.id,c.creator_id,c.name,c.description,c.created_at,
		COALESCE(m.status,''),COALESCE(m.is_admin,false) FROM communities c
		LEFT JOIN community_memberships m ON m.community_id=c.id AND m.user_id=$1
		ORDER BY c.created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("list communities: %w", err)
	}
	defer rows.Close()
	out := make([]Community, 0)
	for rows.Next() {
		var c Community
		if err := rows.Scan(&c.ID, &c.CreatorID, &c.Name, &c.Description, &c.CreatedAt, &c.Status, &c.IsAdmin); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *Repository) Get(ctx context.Context, id string) (*Community, error) {
	c, err := scanCommunity(r.pool.QueryRow(ctx, `SELECT id,creator_id,name,description,created_at FROM communities WHERE id=$1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get community: %w", err)
	}
	return c, nil
}

func (r *Repository) Membership(ctx context.Context, communityID, userID string) (status string, admin bool, err error) {
	err = r.pool.QueryRow(ctx, `SELECT status,is_admin FROM community_memberships WHERE community_id=$1 AND user_id=$2`, communityID, userID).Scan(&status, &admin)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	return
}

func (r *Repository) RequestMembership(ctx context.Context, communityID, userID string) (*Membership, error) {
	var m Membership
	err := r.pool.QueryRow(ctx, `INSERT INTO community_memberships (community_id,user_id,status)
		VALUES ($1,$2,'pending') ON CONFLICT (community_id,user_id) DO UPDATE
		SET status='pending',updated_at=now() WHERE community_memberships.status='declined'
		RETURNING id,community_id,user_id,status,is_admin,created_at`, communityID, userID).
		Scan(&m.ID, &m.CommunityID, &m.UserID, &m.Status, &m.IsAdmin, &m.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrConflict
	}
	if err != nil {
		return nil, fmt.Errorf("request membership: %w", err)
	}
	return &m, nil
}

func (r *Repository) ListMembers(ctx context.Context, communityID, status string) ([]Membership, error) {
	query := `SELECT m.id,m.community_id,m.user_id,u.name,m.status,m.is_admin,m.created_at
		FROM community_memberships m JOIN users u ON u.id=m.user_id WHERE m.community_id=$1`
	args := []any{communityID}
	if status != "" {
		query += ` AND m.status=$2`
		args = append(args, status)
	}
	query += ` ORDER BY m.created_at`
	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list memberships: %w", err)
	}
	defer rows.Close()
	out := make([]Membership, 0)
	for rows.Next() {
		var m Membership
		if err := rows.Scan(&m.ID, &m.CommunityID, &m.UserID, &m.UserName, &m.Status, &m.IsAdmin, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (r *Repository) ReviewRequest(ctx context.Context, communityID, requestID string, approve bool) error {
	status := "declined"
	if approve {
		status = "active"
	}
	tag, err := r.pool.Exec(ctx, `UPDATE community_memberships SET status=$3,updated_at=now() WHERE community_id=$1 AND id=$2 AND status='pending'`, communityID, requestID, status)
	if err != nil {
		return fmt.Errorf("review membership: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) RemoveMember(ctx context.Context, communityID, userID string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM community_memberships WHERE community_id=$1 AND user_id=$2 AND is_admin=false`, communityID, userID)
	if err != nil {
		return fmt.Errorf("remove member: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) Leave(ctx context.Context, communityID, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var status string
	var admin bool
	err = tx.QueryRow(ctx, `SELECT status,is_admin FROM community_memberships WHERE community_id=$1 AND user_id=$2 FOR UPDATE`, communityID, userID).Scan(&status, &admin)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if status != "active" {
		if _, err = tx.Exec(ctx, `DELETE FROM community_memberships WHERE community_id=$1 AND user_id=$2`, communityID, userID); err != nil {
			return err
		}
		return tx.Commit(ctx)
	}
	if admin {
		var successor string
		err = tx.QueryRow(ctx, `SELECT user_id FROM community_memberships WHERE community_id=$1 AND status='active' AND user_id<>$2 ORDER BY created_at LIMIT 1 FOR UPDATE`, communityID, userID).Scan(&successor)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrLastAdmin
		}
		if err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE community_memberships SET is_admin=true,updated_at=now() WHERE community_id=$1 AND user_id=$2 AND status='active'`, communityID, successor)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrLastAdmin
		}
	}
	if _, err = tx.Exec(ctx, `DELETE FROM community_memberships WHERE community_id=$1 AND user_id=$2`, communityID, userID); err != nil {
		return fmt.Errorf("leave community: %w", err)
	}
	return tx.Commit(ctx)
}

func (r *Repository) CreateMessage(ctx context.Context, communityID, userID, name string, pic *string, content string) (*Message, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	var active bool
	err = tx.QueryRow(ctx, `SELECT true FROM community_memberships
		WHERE community_id=$1 AND user_id=$2 AND status='active' FOR SHARE`, communityID, userID).Scan(&active)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotMember
	}
	if err != nil {
		return nil, fmt.Errorf("verify community membership: %w", err)
	}
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, communityID); err != nil {
		return nil, err
	}
	var m Message
	err = tx.QueryRow(ctx, `INSERT INTO community_messages (community_id,seq,user_id,author_name,author_pic,content)
		VALUES ($1,COALESCE((SELECT max(seq) FROM community_messages WHERE community_id=$1),0)+1,$2,$3,$4,$5)
		RETURNING id,community_id,seq,user_id,author_name,author_pic,content,created_at`, communityID, userID, name, pic, content).
		Scan(&m.ID, &m.CommunityID, &m.Seq, &m.UserID, &m.AuthorName, &m.AuthorPic, &m.Content, &m.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("create community message: %w", err)
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &m, nil
}

const messageColumns = `id,community_id,seq,user_id,author_name,author_pic,content,created_at`

func scanMessage(row pgx.Row) (*Message, error) {
	var m Message
	err := row.Scan(&m.ID, &m.CommunityID, &m.Seq, &m.UserID, &m.AuthorName, &m.AuthorPic, &m.Content, &m.CreatedAt)
	return &m, err
}
func (r *Repository) ListMessages(ctx context.Context, cid string, q CursorQuery) ([]Message, bool, error) {
	sql := `SELECT ` + messageColumns + ` FROM community_messages WHERE community_id=$1 ORDER BY seq DESC LIMIT $2`
	args := []any{cid, q.Limit + 1}
	desc := true
	if q.Before > 0 {
		sql = `SELECT ` + messageColumns + ` FROM community_messages WHERE community_id=$1 AND seq<$2 ORDER BY seq DESC LIMIT $3`
		args = []any{cid, q.Before, q.Limit + 1}
	}
	if q.After > 0 {
		sql = `SELECT ` + messageColumns + ` FROM community_messages WHERE community_id=$1 AND seq>$2 ORDER BY seq ASC LIMIT $3`
		args = []any{cid, q.After, q.Limit + 1}
		desc = false
	}
	rows, err := r.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, false, fmt.Errorf("list community messages: %w", err)
	}
	defer rows.Close()
	items := make([]Message, 0, q.Limit+1)
	for rows.Next() {
		m, e := scanMessage(rows)
		if e != nil {
			return nil, false, e
		}
		items = append(items, *m)
	}
	if err = rows.Err(); err != nil {
		return nil, false, err
	}
	more := len(items) > q.Limit
	if more {
		items = items[:q.Limit]
	}
	if desc {
		for i, j := 0, len(items)-1; i < j; i, j = i+1, j-1 {
			items[i], items[j] = items[j], items[i]
		}
	}
	return items, more, nil
}
func (r *Repository) DeleteMessage(ctx context.Context, cid, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM community_messages WHERE community_id=$1 AND id=$2`, cid, id)
	if err != nil {
		return fmt.Errorf("delete community message: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
func (r *Repository) GetMessage(ctx context.Context, cid, id string) (*Message, error) {
	m, err := scanMessage(r.pool.QueryRow(ctx, `SELECT `+messageColumns+` FROM community_messages WHERE community_id=$1 AND id=$2`, cid, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get community message: %w", err)
	}
	return m, nil
}
