package marketplace

import (
	"context"
	"testing"
	"time"

	"believers_palace/internal/auth"
)

type memStore struct {
	categories map[string]*Category
	ads        map[string]*CommunityAd
	shop       map[string]*ShopProduct
}

func newMemStore() *memStore {
	return &memStore{
		categories: map[string]*Category{},
		ads:        map[string]*CommunityAd{},
		shop:       map[string]*ShopProduct{},
	}
}

func (m *memStore) seedCommunityCategory() *Category {
	c := &Category{ID: "cat1", Name: "General", Scope: ScopeCommunity, Active: true}
	m.categories[c.ID] = c
	return c
}

func (m *memStore) ListCategories(_ context.Context, scope string, activeOnly bool) ([]Category, error) {
	var out []Category
	for _, c := range m.categories {
		if c.Scope != scope {
			continue
		}
		if activeOnly && !c.Active {
			continue
		}
		out = append(out, *c)
	}
	return out, nil
}

func (m *memStore) GetCategory(_ context.Context, id string) (*Category, error) {
	c := m.categories[id]
	if c == nil {
		return nil, ErrNotFound
	}
	return c, nil
}

func (m *memStore) CreateCategory(_ context.Context, name, scope string, sortOrder int, active bool) (*Category, error) {
	c := &Category{ID: "cat-new", Name: name, Scope: scope, SortOrder: sortOrder, Active: active, CreatedAt: time.Now()}
	m.categories[c.ID] = c
	return c, nil
}

func (m *memStore) UpdateCategory(_ context.Context, id, name string, sortOrder int, active bool) (*Category, error) {
	c := m.categories[id]
	if c == nil {
		return nil, ErrNotFound
	}
	c.Name = name
	c.SortOrder = sortOrder
	c.Active = active
	return c, nil
}

func (m *memStore) DeleteCategory(_ context.Context, id string) error {
	if m.categories[id] == nil {
		return ErrNotFound
	}
	delete(m.categories, id)
	return nil
}

func (m *memStore) CategoryInUse(_ context.Context, id string) (bool, error) {
	for _, a := range m.ads {
		if a.CategoryID == id {
			return true, nil
		}
	}
	for _, p := range m.shop {
		if p.CategoryID != nil && *p.CategoryID == id {
			return true, nil
		}
	}
	return false, nil
}

func (m *memStore) CreateAd(_ context.Context, sellerID string, in CommunityAdRequest) (*CommunityAd, error) {
	ad := &CommunityAd{
		ID: sellerID + "-ad", SellerID: sellerID, CategoryID: in.CategoryID, Title: in.Title,
		Description: in.Description, Images: in.Images, PriceCents: in.PriceCents,
		Condition: in.Condition, Location: in.Location, ContactPhone: in.ContactPhone,
		ContactEmail: in.ContactEmail, Status: StatusPending,
	}
	m.ads[ad.ID] = ad
	return ad, nil
}

func (m *memStore) GetAdByID(_ context.Context, id string) (*CommunityAd, error) {
	ad := m.ads[id]
	if ad == nil {
		return nil, ErrNotFound
	}
	copy := *ad
	return &copy, nil
}

func (m *memStore) UpdateAd(_ context.Context, id string, in CommunityAdRequest, status string) (*CommunityAd, error) {
	ad := m.ads[id]
	if ad == nil {
		return nil, ErrNotFound
	}
	ad.Title = in.Title
	ad.Status = status
	return ad, nil
}

func (m *memStore) SetAdStatus(_ context.Context, id, status string, reason *string, _ *string) (*CommunityAd, error) {
	ad := m.ads[id]
	if ad == nil {
		return nil, ErrNotFound
	}
	ad.Status = status
	ad.RejectionReason = reason
	return ad, nil
}

func (m *memStore) DeleteAd(_ context.Context, id string) error {
	if m.ads[id] == nil {
		return ErrNotFound
	}
	delete(m.ads, id)
	return nil
}

func (m *memStore) ListAds(_ context.Context, f AdListFilter) ([]CommunityAd, int, error) {
	var out []CommunityAd
	for _, a := range m.ads {
		if f.SellerID != "" && a.SellerID != f.SellerID {
			continue
		}
		if len(f.Statuses) > 0 {
			ok := false
			for _, s := range f.Statuses {
				if a.Status == s {
					ok = true
					break
				}
			}
			if !ok {
				continue
			}
		}
		out = append(out, *a)
	}
	return out, len(out), nil
}

func (m *memStore) CreateShopProduct(_ context.Context, createdBy string, in ShopProductRequest, active bool) (*ShopProduct, error) {
	p := &ShopProduct{ID: "shop1", CategoryID: in.CategoryID, Title: in.Title, PriceCents: in.PriceCents, Active: active, CreatedBy: createdBy}
	m.shop[p.ID] = p
	return p, nil
}

func (m *memStore) GetShopProduct(_ context.Context, id string) (*ShopProduct, error) {
	p := m.shop[id]
	if p == nil {
		return nil, ErrNotFound
	}
	return p, nil
}

func (m *memStore) UpdateShopProduct(_ context.Context, id string, in ShopProductRequest, active bool) (*ShopProduct, error) {
	p := m.shop[id]
	if p == nil {
		return nil, ErrNotFound
	}
	p.Title = in.Title
	p.Active = active
	return p, nil
}

func (m *memStore) DeleteShopProduct(_ context.Context, id string) error {
	if m.shop[id] == nil {
		return ErrNotFound
	}
	delete(m.shop, id)
	return nil
}

func (m *memStore) ListShopProducts(_ context.Context, f ShopListFilter) ([]ShopProduct, int, error) {
	var out []ShopProduct
	for _, p := range m.shop {
		if f.ActiveOnly && !p.Active {
			continue
		}
		out = append(out, *p)
	}
	return out, len(out), nil
}

type testUsers struct{}

func (testUsers) DisplayOf(context.Context, string) (string, *string, bool, error) {
	return "Seller", nil, true, nil
}

func phone(s string) *string { return &s }

func TestAdApprovalAndPermissions(t *testing.T) {
	store := newMemStore()
	store.seedCommunityCategory()
	svc := NewService(store, testUsers{})
	ctx := context.Background()
	user := auth.Identity{UserID: "user1", Role: auth.RoleUser}
	admin := auth.Identity{UserID: "admin1", Role: auth.RoleSuperAdmin}

	req := CommunityAdRequest{
		CategoryID: "cat1", Title: "Chair", Description: "Nice", PriceCents: 500,
		Condition: ConditionUsed, Location: "Town", ContactPhone: phone("555"),
	}
	ad, err := svc.CreateAd(ctx, user, req)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if ad.Status != StatusPending {
		t.Fatalf("expected pending, got %s", ad.Status)
	}

	if _, err := svc.GetAd(ctx, user, ad.ID); err != nil {
		t.Fatalf("owner get: %v", err)
	}
	other := auth.Identity{UserID: "other", Role: auth.RoleUser}
	if _, err := svc.GetAd(ctx, other, ad.ID); err != ErrForbidden {
		t.Fatalf("expected forbidden for other user, got %v", err)
	}

	approved, err := svc.ApproveAd(ctx, admin, ad.ID)
	if err != nil {
		t.Fatalf("approve: %v", err)
	}
	if approved.Status != StatusApproved {
		t.Fatal("not approved")
	}

	sold, err := svc.MarkAdSold(ctx, user, ad.ID)
	if err != nil {
		t.Fatalf("sold: %v", err)
	}
	if sold.Status != StatusSold {
		t.Fatal("not sold")
	}
}

func TestShopAdminOnly(t *testing.T) {
	store := newMemStore()
	c := &Category{ID: "shopcat", Name: "Store", Scope: ScopeShop, Active: true}
	store.categories[c.ID] = c
	svc := NewService(store, testUsers{})
	ctx := context.Background()
	user := auth.Identity{UserID: "u1", Role: auth.RoleUser}
	admin := auth.Identity{UserID: "a1", Role: auth.RoleChurchAdmin}

	_, err := svc.CreateShopProduct(ctx, user, ShopProductRequest{Title: "X", PriceCents: 100})
	if err != ErrForbidden {
		t.Fatalf("expected forbidden, got %v", err)
	}
	cat := c.ID
	p, err := svc.CreateShopProduct(ctx, admin, ShopProductRequest{CategoryID: &cat, Title: "Hymnal", PriceCents: 1999})
	if err != nil {
		t.Fatalf("create shop: %v", err)
	}
	items, _, err := svc.BrowseShop(ctx, "", "", 0, 0, 20, 0)
	if err != nil || len(items) != 1 || items[0].ID != p.ID {
		t.Fatalf("browse shop: %v len=%d", err, len(items))
	}
}

func TestApprovedEditReturnsPending(t *testing.T) {
	store := newMemStore()
	store.seedCommunityCategory()
	svc := NewService(store, testUsers{})
	ctx := context.Background()
	user := auth.Identity{UserID: "user1", Role: auth.RoleUser}
	admin := auth.Identity{UserID: "admin1", Role: auth.RoleSuperAdmin}

	req := CommunityAdRequest{
		CategoryID: "cat1", Title: "Desk", PriceCents: 1000, Condition: ConditionNew,
		Location: "Here", ContactEmail: strPtr("a@b.c"),
	}
	ad, _ := svc.CreateAd(ctx, user, req)
	_, _ = svc.ApproveAd(ctx, admin, ad.ID)

	updated, err := svc.UpdateAd(ctx, user, ad.ID, req)
	if err != nil {
		t.Fatalf("update: %v", err)
	}
	if updated.Status != StatusPending {
		t.Fatalf("expected pending after edit, got %s", updated.Status)
	}
}

func strPtr(s string) *string { return &s }