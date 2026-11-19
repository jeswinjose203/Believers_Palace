package marketplace

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func encodeStrings(ss []string) ([]byte, error) {
	if ss == nil {
		ss = []string{}
	}
	return json.Marshal(ss)
}

func decodeStrings(raw []byte) ([]string, error) {
	if len(raw) == 0 {
		return []string{}, nil
	}
	var out []string
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	if out == nil {
		out = []string{}
	}
	return out, nil
}

const categoryCols = `id, name, scope, sort_order, active, created_at, updated_at`

func scanCategory(row pgx.Row) (*Category, error) {
	var c Category
	if err := row.Scan(&c.ID, &c.Name, &c.Scope, &c.SortOrder, &c.Active, &c.CreatedAt, &c.UpdatedAt); err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) ListCategories(ctx context.Context, scope string, activeOnly bool) ([]Category, error) {
	q := `SELECT ` + categoryCols + ` FROM marketplace_categories WHERE scope = $1`
	args := []any{scope}
	if activeOnly {
		q += ` AND active = true`
	}
	q += ` ORDER BY sort_order ASC, name ASC`
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("list categories: %w", err)
	}
	defer rows.Close()
	var out []Category
	for rows.Next() {
		c, err := scanCategory(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	return out, rows.Err()
}

func (r *Repository) GetCategory(ctx context.Context, id string) (*Category, error) {
	const q = `SELECT ` + categoryCols + ` FROM marketplace_categories WHERE id = $1`
	c, err := scanCategory(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return c, err
}

func (r *Repository) CreateCategory(ctx context.Context, name, scope string, sortOrder int, active bool) (*Category, error) {
	const q = `
		INSERT INTO marketplace_categories (name, scope, sort_order, active)
		VALUES ($1, $2, $3, $4)
		RETURNING ` + categoryCols
	return scanCategory(r.pool.QueryRow(ctx, q, name, scope, sortOrder, active))
}

func (r *Repository) UpdateCategory(ctx context.Context, id, name string, sortOrder int, active bool) (*Category, error) {
	const q = `
		UPDATE marketplace_categories
		SET name = $2, sort_order = $3, active = $4, updated_at = now()
		WHERE id = $1
		RETURNING ` + categoryCols
	c, err := scanCategory(r.pool.QueryRow(ctx, q, id, name, sortOrder, active))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return c, err
}

func (r *Repository) DeleteCategory(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM marketplace_categories WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) CategoryInUse(ctx context.Context, id string) (bool, error) {
	var n int
	err := r.pool.QueryRow(ctx, `
		SELECT (
			(SELECT COUNT(*) FROM community_advertisements WHERE category_id = $1) +
			(SELECT COUNT(*) FROM shop_products WHERE category_id = $1)
		)`, id).Scan(&n)
	return n > 0, err
}

const adCols = `a.id, a.seller_id, a.category_id, c.name, a.title, a.description, a.images,
	a.price_cents, a.condition, a.location, a.contact_phone, a.contact_email,
	a.status, a.rejection_reason, a.reviewed_at, a.created_at, a.updated_at`

func scanAd(row pgx.Row) (*CommunityAd, error) {
	var (
		ad        CommunityAd
		imagesRaw []byte
		phone     *string
		email     *string
		reason    *string
		reviewed  *time.Time
	)
	if err := row.Scan(
		&ad.ID, &ad.SellerID, &ad.CategoryID, &ad.CategoryName, &ad.Title, &ad.Description, &imagesRaw,
		&ad.PriceCents, &ad.Condition, &ad.Location, &phone, &email,
		&ad.Status, &reason, &reviewed, &ad.CreatedAt, &ad.UpdatedAt,
	); err != nil {
		return nil, err
	}
	var err error
	if ad.Images, err = decodeStrings(imagesRaw); err != nil {
		return nil, fmt.Errorf("decode images: %w", err)
	}
	ad.ContactPhone = phone
	ad.ContactEmail = email
	ad.RejectionReason = reason
	ad.ReviewedAt = reviewed
	return &ad, nil
}

func (r *Repository) CreateAd(ctx context.Context, sellerID string, in CommunityAdRequest) (*CommunityAd, error) {
	imgs, err := encodeStrings(in.Images)
	if err != nil {
		return nil, err
	}
	const q = `
		INSERT INTO community_advertisements (
			seller_id, category_id, title, description, images, price_cents,
			condition, location, contact_phone, contact_email, status
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id`
	var id string
	if err := r.pool.QueryRow(ctx, q,
		sellerID, in.CategoryID, in.Title, in.Description, imgs, in.PriceCents,
		in.Condition, in.Location, in.ContactPhone, in.ContactEmail, StatusPending,
	).Scan(&id); err != nil {
		return nil, fmt.Errorf("create ad: %w", err)
	}
	return r.GetAdByID(ctx, id)
}

func (r *Repository) GetAdByID(ctx context.Context, id string) (*CommunityAd, error) {
	const q = `SELECT ` + adCols + ` FROM community_advertisements a
		JOIN marketplace_categories c ON c.id = a.category_id WHERE a.id = $1`
	ad, err := scanAd(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return ad, err
}

func (r *Repository) UpdateAd(ctx context.Context, id string, in CommunityAdRequest, status string) (*CommunityAd, error) {
	imgs, err := encodeStrings(in.Images)
	if err != nil {
		return nil, err
	}
	const q = `
		UPDATE community_advertisements SET
			category_id = $2, title = $3, description = $4, images = $5,
			price_cents = $6, condition = $7, location = $8,
			contact_phone = $9, contact_email = $10, status = $11,
			rejection_reason = NULL, reviewed_at = NULL, reviewed_by = NULL,
			updated_at = now()
		WHERE id = $1`
	tag, err := r.pool.Exec(ctx, q,
		id, in.CategoryID, in.Title, in.Description, imgs, in.PriceCents,
		in.Condition, in.Location, in.ContactPhone, in.ContactEmail, status,
	)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrNotFound
	}
	return r.GetAdByID(ctx, id)
}

func (r *Repository) SetAdStatus(ctx context.Context, id, status string, reason *string, reviewerID *string) (*CommunityAd, error) {
	const q = `
		UPDATE community_advertisements SET
			status = $2,
			rejection_reason = $3,
			reviewed_at = CASE WHEN $4::uuid IS NOT NULL THEN now() ELSE reviewed_at END,
			reviewed_by = COALESCE($4, reviewed_by),
			updated_at = now()
		WHERE id = $1`
	tag, err := r.pool.Exec(ctx, q, id, status, reason, reviewerID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrNotFound
	}
	return r.GetAdByID(ctx, id)
}

func (r *Repository) DeleteAd(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM community_advertisements WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) ListAds(ctx context.Context, f AdListFilter) ([]CommunityAd, int, error) {
	where, args := buildAdWhere(f)
	countQ := `SELECT COUNT(*) FROM community_advertisements a
		JOIN marketplace_categories c ON c.id = a.category_id ` + where
	var total int
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit := f.Limit
	if limit <= 0 {
		limit = 20
	}
	args = append(args, limit, f.Offset)
	q := `SELECT ` + adCols + ` FROM community_advertisements a
		JOIN marketplace_categories c ON c.id = a.category_id ` + where +
		` ORDER BY a.created_at DESC LIMIT $` + fmt.Sprint(len(args)-1) +
		` OFFSET $` + fmt.Sprint(len(args))
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var out []CommunityAd
	for rows.Next() {
		ad, err := scanAd(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *ad)
	}
	return out, total, rows.Err()
}

func buildAdWhere(f AdListFilter) (string, []any) {
	var parts []string
	var args []any
	n := 1
	add := func(clause string, val any) {
		parts = append(parts, fmt.Sprintf(clause, n))
		args = append(args, val)
		n++
	}
	if len(f.Statuses) > 0 {
		parts = append(parts, fmt.Sprintf("a.status = ANY($%d)", n))
		args = append(args, f.Statuses)
		n++
	}
	if f.SellerID != "" {
		add("a.seller_id = $%d", f.SellerID)
	}
	if f.CategoryID != "" {
		add("a.category_id = $%d", f.CategoryID)
	}
	if f.Search != "" {
		parts = append(parts, fmt.Sprintf("(a.title ILIKE $%d OR a.description ILIKE $%d)", n, n))
		args = append(args, "%"+strings.TrimSpace(f.Search)+"%")
		n++
	}
	if f.MinPrice > 0 {
		add("a.price_cents >= $%d", f.MinPrice)
	}
	if f.MaxPrice > 0 {
		add("a.price_cents <= $%d", f.MaxPrice)
	}
	if f.ExcludeSold {
		parts = append(parts, "a.status <> 'sold'")
	}
	where := ""
	if len(parts) > 0 {
		where = "WHERE " + strings.Join(parts, " AND ")
	}
	return where, args
}

const shopCols = `p.id, p.category_id, c.name, p.title, p.description, p.images,
	p.price_cents, p.active, p.created_by, p.created_at, p.updated_at`

func scanShop(row pgx.Row) (*ShopProduct, error) {
	var (
		p         ShopProduct
		imagesRaw []byte
		catID     *string
		catName   *string
	)
	if err := row.Scan(
		&p.ID, &catID, &catName, &p.Title, &p.Description, &imagesRaw,
		&p.PriceCents, &p.Active, &p.CreatedBy, &p.CreatedAt, &p.UpdatedAt,
	); err != nil {
		return nil, err
	}
	p.CategoryID = catID
	if catName != nil {
		p.CategoryName = *catName
	}
	var err error
	if p.Images, err = decodeStrings(imagesRaw); err != nil {
		return nil, fmt.Errorf("decode images: %w", err)
	}
	return &p, nil
}

func (r *Repository) CreateShopProduct(ctx context.Context, createdBy string, in ShopProductRequest, active bool) (*ShopProduct, error) {
	imgs, err := encodeStrings(in.Images)
	if err != nil {
		return nil, err
	}
	const q = `
		INSERT INTO shop_products (category_id, title, description, images, price_cents, active, created_by)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		RETURNING id`
	var id string
	if err := r.pool.QueryRow(ctx, q,
		in.CategoryID, in.Title, in.Description, imgs, in.PriceCents, active, createdBy,
	).Scan(&id); err != nil {
		return nil, fmt.Errorf("create shop product: %w", err)
	}
	return r.GetShopProduct(ctx, id)
}

func (r *Repository) GetShopProduct(ctx context.Context, id string) (*ShopProduct, error) {
	const q = `SELECT ` + shopCols + ` FROM shop_products p
		LEFT JOIN marketplace_categories c ON c.id = p.category_id WHERE p.id = $1`
	p, err := scanShop(r.pool.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return p, err
}

func (r *Repository) UpdateShopProduct(ctx context.Context, id string, in ShopProductRequest, active bool) (*ShopProduct, error) {
	imgs, err := encodeStrings(in.Images)
	if err != nil {
		return nil, err
	}
	const q = `
		UPDATE shop_products SET
			category_id = $2, title = $3, description = $4, images = $5,
			price_cents = $6, active = $7, updated_at = now()
		WHERE id = $1`
	tag, err := r.pool.Exec(ctx, q,
		id, in.CategoryID, in.Title, in.Description, imgs, in.PriceCents, active,
	)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrNotFound
	}
	return r.GetShopProduct(ctx, id)
}

func (r *Repository) DeleteShopProduct(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM shop_products WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) ListShopProducts(ctx context.Context, f ShopListFilter) ([]ShopProduct, int, error) {
	var parts []string
	var args []any
	n := 1
	if f.ActiveOnly {
		parts = append(parts, "p.active = true")
	}
	if f.CategoryID != "" {
		parts = append(parts, fmt.Sprintf("p.category_id = $%d", n))
		args = append(args, f.CategoryID)
		n++
	}
	if f.Search != "" {
		parts = append(parts, fmt.Sprintf("(p.title ILIKE $%d OR p.description ILIKE $%d)", n, n))
		args = append(args, "%"+strings.TrimSpace(f.Search)+"%")
		n++
	}
	if f.MinPrice > 0 {
		parts = append(parts, fmt.Sprintf("p.price_cents >= $%d", n))
		args = append(args, f.MinPrice)
		n++
	}
	if f.MaxPrice > 0 {
		parts = append(parts, fmt.Sprintf("p.price_cents <= $%d", n))
		args = append(args, f.MaxPrice)
		n++
	}
	where := ""
	if len(parts) > 0 {
		where = "WHERE " + strings.Join(parts, " AND ")
	}
	countQ := `SELECT COUNT(*) FROM shop_products p ` + where
	var total int
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit := f.Limit
	if limit <= 0 {
		limit = 20
	}
	args = append(args, limit, f.Offset)
	q := `SELECT ` + shopCols + ` FROM shop_products p
		LEFT JOIN marketplace_categories c ON c.id = p.category_id ` + where +
		` ORDER BY p.created_at DESC LIMIT $` + fmt.Sprint(len(args)-1) +
		` OFFSET $` + fmt.Sprint(len(args))
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var out []ShopProduct
	for rows.Next() {
		p, err := scanShop(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *p)
	}
	return out, total, rows.Err()
}