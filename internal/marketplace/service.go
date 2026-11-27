package marketplace

import (
	"context"
	"strings"

	"believers_palace/internal/auth"
)

type store interface {
	ListCategories(ctx context.Context, scope string, activeOnly bool) ([]Category, error)
	GetCategory(ctx context.Context, id string) (*Category, error)
	CreateCategory(ctx context.Context, name, scope string, sortOrder int, active bool) (*Category, error)
	UpdateCategory(ctx context.Context, id, name string, sortOrder int, active bool) (*Category, error)
	DeleteCategory(ctx context.Context, id string) error
	CategoryInUse(ctx context.Context, id string) (bool, error)

	CreateAd(ctx context.Context, sellerID string, in CommunityAdRequest) (*CommunityAd, error)
	GetAdByID(ctx context.Context, id string) (*CommunityAd, error)
	UpdateAd(ctx context.Context, id string, in CommunityAdRequest, status string) (*CommunityAd, error)
	SetAdStatus(ctx context.Context, id, status string, reason *string, reviewerID *string) (*CommunityAd, error)
	DeleteAd(ctx context.Context, id string) error
	ListAds(ctx context.Context, f AdListFilter) ([]CommunityAd, int, error)

	CreateShopProduct(ctx context.Context, createdBy string, in ShopProductRequest, active bool) (*ShopProduct, error)
	GetShopProduct(ctx context.Context, id string) (*ShopProduct, error)
	UpdateShopProduct(ctx context.Context, id string, in ShopProductRequest, active bool) (*ShopProduct, error)
	DeleteShopProduct(ctx context.Context, id string) error
	ListShopProducts(ctx context.Context, f ShopListFilter) ([]ShopProduct, int, error)
}

type displayResolver interface {
	DisplayOf(context.Context, string) (string, *string, bool, error)
}

type Service struct {
	repo  store
	users displayResolver
}

func NewService(repo store, users displayResolver) *Service {
	return &Service{repo: repo, users: users}
}

func isAdmin(id auth.Identity) bool {
	return id.Role.IsAdmin() || id.Role.IsSuperAdmin()
}

func (s *Service) ListCategories(ctx context.Context, id auth.Identity, scope string, adminView bool) ([]Category, error) {
	if !validScope(scope) {
		return nil, invalid("scope must be community or shop")
	}
	activeOnly := !adminView || !isAdmin(id)
	return s.repo.ListCategories(ctx, scope, activeOnly)
}

func (s *Service) CreateCategory(ctx context.Context, id auth.Identity, scope string, in CategoryRequest) (*Category, error) {
	if !isAdmin(id) {
		return nil, ErrForbidden
	}
	if !validScope(scope) {
		return nil, invalid("scope must be community or shop")
	}
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return nil, invalid("name is required")
	}
	if len(name) > 100 {
		return nil, invalid("name is too long")
	}
	sortOrder := 0
	if in.SortOrder != nil {
		sortOrder = *in.SortOrder
	}
	active := true
	if in.Active != nil {
		active = *in.Active
	}
	return s.repo.CreateCategory(ctx, name, scope, sortOrder, active)
}

func (s *Service) UpdateCategory(ctx context.Context, id auth.Identity, categoryID string, in CategoryRequest) (*Category, error) {
	if !isAdmin(id) {
		return nil, ErrForbidden
	}
	cat, err := s.repo.GetCategory(ctx, categoryID)
	if err != nil {
		return nil, err
	}
	name := strings.TrimSpace(in.Name)
	if name == "" {
		name = cat.Name
	}
	if len(name) > 100 {
		return nil, invalid("name is too long")
	}
	sortOrder := cat.SortOrder
	if in.SortOrder != nil {
		sortOrder = *in.SortOrder
	}
	active := cat.Active
	if in.Active != nil {
		active = *in.Active
	}
	return s.repo.UpdateCategory(ctx, categoryID, name, sortOrder, active)
}

func (s *Service) DeleteCategory(ctx context.Context, id auth.Identity, categoryID string) error {
	if !isAdmin(id) {
		return ErrForbidden
	}
	if _, err := s.repo.GetCategory(ctx, categoryID); err != nil {
		return err
	}
	inUse, err := s.repo.CategoryInUse(ctx, categoryID)
	if err != nil {
		return err
	}
	if inUse {
		return ErrConflict
	}
	return s.repo.DeleteCategory(ctx, categoryID)
}

func normalizeAdRequest(in CommunityAdRequest) (CommunityAdRequest, error) {
	in.Title = strings.TrimSpace(in.Title)
	in.Description = strings.TrimSpace(in.Description)
	in.Location = strings.TrimSpace(in.Location)
	in.Condition = strings.ToLower(strings.TrimSpace(in.Condition))
	if in.Title == "" {
		return in, invalid("title is required")
	}
	if len(in.Title) > 200 {
		return in, invalid("title is too long")
	}
	if len(in.Description) > 5000 {
		return in, invalid("description is too long")
	}
	if in.CategoryID == "" {
		return in, invalid("categoryId is required")
	}
	if in.PriceCents <= 0 {
		return in, invalid("priceCents must be positive")
	}
	if !validCondition(in.Condition) {
		return in, invalid("condition must be new or used")
	}
	if in.Location == "" {
		return in, invalid("location is required")
	}
	if in.ContactPhone != nil {
		t := strings.TrimSpace(*in.ContactPhone)
		if t == "" {
			in.ContactPhone = nil
		} else {
			in.ContactPhone = &t
		}
	}
	if in.ContactEmail != nil {
		t := strings.TrimSpace(*in.ContactEmail)
		if t == "" {
			in.ContactEmail = nil
		} else {
			in.ContactEmail = &t
		}
	}
	if in.ContactPhone == nil && in.ContactEmail == nil {
		return in, invalid("at least one contact method is required")
	}
	if in.Images == nil {
		in.Images = []string{}
	}
	return in, nil
}

func (s *Service) verifyCommunityCategory(ctx context.Context, categoryID string) error {
	cat, err := s.repo.GetCategory(ctx, categoryID)
	if err != nil {
		return err
	}
	if cat.Scope != ScopeCommunity || !cat.Active {
		return invalid("invalid community category")
	}
	return nil
}

func (s *Service) verifyShopCategory(ctx context.Context, categoryID *string) error {
	if categoryID == nil || *categoryID == "" {
		return nil
	}
	cat, err := s.repo.GetCategory(ctx, *categoryID)
	if err != nil {
		return err
	}
	if cat.Scope != ScopeShop {
		return invalid("invalid shop category")
	}
	return nil
}

func (s *Service) CreateAd(ctx context.Context, id auth.Identity, in CommunityAdRequest) (*CommunityAd, error) {
	norm, err := normalizeAdRequest(in)
	if err != nil {
		return nil, err
	}
	if err := s.verifyCommunityCategory(ctx, norm.CategoryID); err != nil {
		return nil, err
	}
	ad, err := s.repo.CreateAd(ctx, id.UserID, norm)
	if err != nil {
		return nil, err
	}
	return s.attachSeller(ctx, ad)
}

func (s *Service) BrowseAds(ctx context.Context, search, categoryID string, minPrice, maxPrice int, excludeSold bool, limit, offset int) ([]CommunityAd, int, error) {
	statuses := []string{StatusApproved, StatusSold}
	f := AdListFilter{
		Statuses:    statuses,
		Search:      search,
		CategoryID:  categoryID,
		MinPrice:    minPrice,
		MaxPrice:    maxPrice,
		ExcludeSold: excludeSold,
		Limit:       limit,
		Offset:      offset,
	}
	return s.repo.ListAds(ctx, f)
}

func (s *Service) ListMyAds(ctx context.Context, id auth.Identity, limit, offset int) ([]CommunityAd, int, error) {
	f := AdListFilter{SellerID: id.UserID, Limit: limit, Offset: offset}
	return s.repo.ListAds(ctx, f)
}

func (s *Service) ListAdsAdmin(ctx context.Context, id auth.Identity, status, search string, limit, offset int) ([]CommunityAd, int, error) {
	if !isAdmin(id) {
		return nil, 0, ErrForbidden
	}
	if status == "" {
		status = StatusPending
	}
	if !validAdStatus(status) {
		return nil, 0, invalid("invalid status filter")
	}
	f := AdListFilter{Statuses: []string{status}, Search: search, Limit: limit, Offset: offset}
	return s.repo.ListAds(ctx, f)
}

func (s *Service) GetAd(ctx context.Context, id auth.Identity, adID string) (*CommunityAd, error) {
	ad, err := s.repo.GetAdByID(ctx, adID)
	if err != nil {
		return nil, err
	}
	if ad.Status == StatusApproved || ad.Status == StatusSold {
		return s.attachSeller(ctx, ad)
	}
	if ad.SellerID == id.UserID || isAdmin(id) {
		return s.attachSeller(ctx, ad)
	}
	return nil, ErrForbidden
}

func (s *Service) UpdateAd(ctx context.Context, id auth.Identity, adID string, in CommunityAdRequest) (*CommunityAd, error) {
	ad, err := s.repo.GetAdByID(ctx, adID)
	if err != nil {
		return nil, err
	}
	if ad.SellerID != id.UserID {
		return nil, ErrForbidden
	}
	if ad.Status == StatusRemoved || ad.Status == StatusSold {
		return nil, invalid("this advertisement cannot be edited")
	}
	norm, err := normalizeAdRequest(in)
	if err != nil {
		return nil, err
	}
	if err := s.verifyCommunityCategory(ctx, norm.CategoryID); err != nil {
		return nil, err
	}
	nextStatus := ad.Status
	if ad.Status == StatusApproved {
		nextStatus = StatusPending
	}
	updated, err := s.repo.UpdateAd(ctx, adID, norm, nextStatus)
	if err != nil {
		return nil, err
	}
	return s.attachSeller(ctx, updated)
}

func (s *Service) DeleteAd(ctx context.Context, id auth.Identity, adID string) error {
	ad, err := s.repo.GetAdByID(ctx, adID)
	if err != nil {
		return err
	}
	if isAdmin(id) {
		_, err := s.repo.SetAdStatus(ctx, adID, StatusRemoved, nil, nil)
		return err
	}
	if ad.SellerID != id.UserID {
		return ErrForbidden
	}
	switch ad.Status {
	case StatusPending, StatusRejected:
		return s.repo.DeleteAd(ctx, adID)
	default:
		_, err := s.repo.SetAdStatus(ctx, adID, StatusRemoved, nil, nil)
		return err
	}
}

func (s *Service) ApproveAd(ctx context.Context, id auth.Identity, adID string) (*CommunityAd, error) {
	if !isAdmin(id) {
		return nil, ErrForbidden
	}
	ad, err := s.repo.GetAdByID(ctx, adID)
	if err != nil {
		return nil, err
	}
	if ad.Status != StatusPending {
		return nil, invalid("only pending advertisements can be approved")
	}
	reviewer := id.UserID
	updated, err := s.repo.SetAdStatus(ctx, adID, StatusApproved, nil, &reviewer)
	if err != nil {
		return nil, err
	}
	return s.attachSeller(ctx, updated)
}

func (s *Service) RejectAd(ctx context.Context, id auth.Identity, adID string, reason *string) (*CommunityAd, error) {
	if !isAdmin(id) {
		return nil, ErrForbidden
	}
	ad, err := s.repo.GetAdByID(ctx, adID)
	if err != nil {
		return nil, err
	}
	if ad.Status != StatusPending {
		return nil, invalid("only pending advertisements can be rejected")
	}
	var trimmed *string
	if reason != nil {
		t := strings.TrimSpace(*reason)
		if t != "" {
			trimmed = &t
		}
	}
	reviewer := id.UserID
	updated, err := s.repo.SetAdStatus(ctx, adID, StatusRejected, trimmed, &reviewer)
	if err != nil {
		return nil, err
	}
	return s.attachSeller(ctx, updated)
}

func (s *Service) MarkAdSold(ctx context.Context, id auth.Identity, adID string) (*CommunityAd, error) {
	ad, err := s.repo.GetAdByID(ctx, adID)
	if err != nil {
		return nil, err
	}
	if ad.SellerID != id.UserID {
		return nil, ErrForbidden
	}
	if ad.Status != StatusApproved {
		return nil, invalid("only approved advertisements can be marked sold")
	}
	updated, err := s.repo.SetAdStatus(ctx, adID, StatusSold, nil, nil)
	if err != nil {
		return nil, err
	}
	return s.attachSeller(ctx, updated)
}

func (s *Service) attachSeller(ctx context.Context, ad *CommunityAd) (*CommunityAd, error) {
	if s.users == nil {
		return ad, nil
	}
	name, pic, ok, err := s.users.DisplayOf(ctx, ad.SellerID)
	if err != nil {
		return nil, err
	}
	if ok {
		ad.Seller = &SellerSummary{ID: ad.SellerID, Name: name, ProfilePic: pic}
	}
	return ad, nil
}

func normalizeShopRequest(in ShopProductRequest) (ShopProductRequest, bool, error) {
	in.Title = strings.TrimSpace(in.Title)
	in.Description = strings.TrimSpace(in.Description)
	if in.Title == "" {
		return in, false, invalid("title is required")
	}
	if len(in.Title) > 200 {
		return in, false, invalid("title is too long")
	}
	if len(in.Description) > 5000 {
		return in, false, invalid("description is too long")
	}
	if in.PriceCents <= 0 {
		return in, false, invalid("priceCents must be positive")
	}
	if in.Images == nil {
		in.Images = []string{}
	}
	active := true
	if in.Active != nil {
		active = *in.Active
	}
	return in, active, nil
}

func (s *Service) BrowseShop(ctx context.Context, search, categoryID string, minPrice, maxPrice int, limit, offset int) ([]ShopProduct, int, error) {
	f := ShopListFilter{
		ActiveOnly: true,
		Search:     search,
		CategoryID: categoryID,
		MinPrice:   minPrice,
		MaxPrice:   maxPrice,
		Limit:      limit,
		Offset:     offset,
	}
	return s.repo.ListShopProducts(ctx, f)
}

func (s *Service) ListShopAdmin(ctx context.Context, id auth.Identity, search string, limit, offset int) ([]ShopProduct, int, error) {
	if !isAdmin(id) {
		return nil, 0, ErrForbidden
	}
	f := ShopListFilter{Search: search, Limit: limit, Offset: offset}
	return s.repo.ListShopProducts(ctx, f)
}

func (s *Service) GetShopProduct(ctx context.Context, id auth.Identity, productID string) (*ShopProduct, error) {
	p, err := s.repo.GetShopProduct(ctx, productID)
	if err != nil {
		return nil, err
	}
	if !p.Active && !isAdmin(id) {
		return nil, ErrNotFound
	}
	return p, nil
}

func (s *Service) CreateShopProduct(ctx context.Context, id auth.Identity, in ShopProductRequest) (*ShopProduct, error) {
	if !isAdmin(id) {
		return nil, ErrForbidden
	}
	norm, active, err := normalizeShopRequest(in)
	if err != nil {
		return nil, err
	}
	if err := s.verifyShopCategory(ctx, norm.CategoryID); err != nil {
		return nil, err
	}
	return s.repo.CreateShopProduct(ctx, id.UserID, norm, active)
}

func (s *Service) UpdateShopProduct(ctx context.Context, id auth.Identity, productID string, in ShopProductRequest) (*ShopProduct, error) {
	if !isAdmin(id) {
		return nil, ErrForbidden
	}
	existing, err := s.repo.GetShopProduct(ctx, productID)
	if err != nil {
		return nil, err
	}
	norm, active, err := normalizeShopRequest(in)
	if err != nil {
		return nil, err
	}
	if in.Active == nil {
		active = existing.Active
	}
	if err := s.verifyShopCategory(ctx, norm.CategoryID); err != nil {
		return nil, err
	}
	return s.repo.UpdateShopProduct(ctx, productID, norm, active)
}

func (s *Service) DeleteShopProduct(ctx context.Context, id auth.Identity, productID string) error {
	if !isAdmin(id) {
		return ErrForbidden
	}
	return s.repo.DeleteShopProduct(ctx, productID)
}
