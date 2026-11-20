package marketplace

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()

	r.Route("/categories", func(cr chi.Router) {
		cr.Get("/", h.listCategories)
		cr.Post("/", h.createCategory)
		cr.Put("/{categoryId}", h.updateCategory)
		cr.Delete("/{categoryId}", h.deleteCategory)
	})

	r.Route("/community-ads", func(ar chi.Router) {
		ar.Get("/", h.browseAds)
		ar.Get("/mine", h.listMyAds)
		ar.Get("/admin", h.listAdsAdmin)
		ar.Post("/", h.createAd)
		ar.Get("/{adId}", h.getAd)
		ar.Put("/{adId}", h.updateAd)
		ar.Delete("/{adId}", h.deleteAd)
		ar.Post("/{adId}/approve", h.approveAd)
		ar.Post("/{adId}/reject", h.rejectAd)
		ar.Post("/{adId}/sold", h.markSold)
	})

	r.Route("/shop/products", func(sr chi.Router) {
		sr.Get("/", h.browseShop)
		sr.Get("/admin", h.listShopAdmin)
		sr.Post("/", h.createShopProduct)
		sr.Get("/{productId}", h.getShopProduct)
		sr.Put("/{productId}", h.updateShopProduct)
		sr.Delete("/{productId}", h.deleteShopProduct)
	})

	return r
}

func parsePriceQuery(r *http.Request) (min, max int) {
	q := r.URL.Query()
	if v := q.Get("minPrice"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			min = n
		}
	}
	if v := q.Get("maxPrice"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			max = n
		}
	}
	return min, max
}

func (h *Handler) listCategories(w http.ResponseWriter, r *http.Request) {
	scope := r.URL.Query().Get("scope")
	if scope == "" {
		httpx.ErrorCode(w, http.StatusBadRequest, "scope query parameter is required", "bad_request")
		return
	}
	adminView := r.URL.Query().Get("all") == "true"
	items, err := h.svc.ListCategories(r.Context(), auth.MustFromContext(r.Context()), scope, adminView)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"data": items})
}

func (h *Handler) createCategory(w http.ResponseWriter, r *http.Request) {
	scope := r.URL.Query().Get("scope")
	if scope == "" {
		httpx.ErrorCode(w, http.StatusBadRequest, "scope query parameter is required", "bad_request")
		return
	}
	var in CategoryRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	c, err := h.svc.CreateCategory(r.Context(), auth.MustFromContext(r.Context()), scope, in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, c)
}

func (h *Handler) updateCategory(w http.ResponseWriter, r *http.Request) {
	var in CategoryRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	c, err := h.svc.UpdateCategory(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "categoryId"), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, c)
}

func (h *Handler) deleteCategory(w http.ResponseWriter, r *http.Request) {
	err := h.svc.DeleteCategory(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "categoryId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) browseAds(w http.ResponseWriter, r *http.Request) {
	pp := httpx.ParsePageParams(r)
	minP, maxP := parsePriceQuery(r)
	excludeSold := r.URL.Query().Get("excludeSold") == "true"
	items, total, err := h.svc.BrowseAds(r.Context(),
		r.URL.Query().Get("search"),
		r.URL.Query().Get("categoryId"),
		minP, maxP,
		excludeSold,
		pp.Limit, pp.Offset,
	)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) listMyAds(w http.ResponseWriter, r *http.Request) {
	pp := httpx.ParsePageParams(r)
	items, total, err := h.svc.ListMyAds(r.Context(), auth.MustFromContext(r.Context()), pp.Limit, pp.Offset)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) listAdsAdmin(w http.ResponseWriter, r *http.Request) {
	pp := httpx.ParsePageParams(r)
	items, total, err := h.svc.ListAdsAdmin(r.Context(),
		auth.MustFromContext(r.Context()),
		r.URL.Query().Get("status"),
		r.URL.Query().Get("search"),
		pp.Limit, pp.Offset,
	)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createAd(w http.ResponseWriter, r *http.Request) {
	var in CommunityAdRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	ad, err := h.svc.CreateAd(r.Context(), auth.MustFromContext(r.Context()), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, ad)
}

func (h *Handler) getAd(w http.ResponseWriter, r *http.Request) {
	ad, err := h.svc.GetAd(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "adId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, ad)
}

func (h *Handler) updateAd(w http.ResponseWriter, r *http.Request) {
	var in CommunityAdRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	ad, err := h.svc.UpdateAd(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "adId"), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, ad)
}

func (h *Handler) deleteAd(w http.ResponseWriter, r *http.Request) {
	err := h.svc.DeleteAd(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "adId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) approveAd(w http.ResponseWriter, r *http.Request) {
	ad, err := h.svc.ApproveAd(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "adId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, ad)
}

func (h *Handler) rejectAd(w http.ResponseWriter, r *http.Request) {
	var in RejectRequest
	if r.ContentLength > 0 {
		if err := httpx.DecodeJSON(r, &in); err != nil {
			httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
			return
		}
	}
	ad, err := h.svc.RejectAd(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "adId"), in.Reason)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, ad)
}

func (h *Handler) markSold(w http.ResponseWriter, r *http.Request) {
	ad, err := h.svc.MarkAdSold(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "adId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, ad)
}

func (h *Handler) browseShop(w http.ResponseWriter, r *http.Request) {
	pp := httpx.ParsePageParams(r)
	minP, maxP := parsePriceQuery(r)
	items, total, err := h.svc.BrowseShop(r.Context(),
		r.URL.Query().Get("search"),
		r.URL.Query().Get("categoryId"),
		minP, maxP,
		pp.Limit, pp.Offset,
	)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) listShopAdmin(w http.ResponseWriter, r *http.Request) {
	pp := httpx.ParsePageParams(r)
	items, total, err := h.svc.ListShopAdmin(r.Context(),
		auth.MustFromContext(r.Context()),
		r.URL.Query().Get("search"),
		pp.Limit, pp.Offset,
	)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.Paged(w, items, pp.Page, pp.Limit, total)
}

func (h *Handler) createShopProduct(w http.ResponseWriter, r *http.Request) {
	var in ShopProductRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	p, err := h.svc.CreateShopProduct(r.Context(), auth.MustFromContext(r.Context()), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, p)
}

func (h *Handler) getShopProduct(w http.ResponseWriter, r *http.Request) {
	p, err := h.svc.GetShopProduct(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "productId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

func (h *Handler) updateShopProduct(w http.ResponseWriter, r *http.Request) {
	var in ShopProductRequest
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	p, err := h.svc.UpdateShopProduct(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "productId"), in)
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

func (h *Handler) deleteShopProduct(w http.ResponseWriter, r *http.Request) {
	err := h.svc.DeleteShopProduct(r.Context(), auth.MustFromContext(r.Context()), chi.URLParam(r, "productId"))
	if err != nil {
		h.writeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) writeError(w http.ResponseWriter, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.ErrorCode(w, http.StatusBadRequest, ve.Message, "bad_request")
	case errors.Is(err, ErrForbidden):
		httpx.ErrorCode(w, http.StatusForbidden, "insufficient permissions", "forbidden")
	case errors.Is(err, ErrNotFound):
		httpx.ErrorCode(w, http.StatusNotFound, ErrNotFound.Error(), "not_found")
	case errors.Is(err, ErrConflict):
		httpx.ErrorCode(w, http.StatusConflict, "category is in use", "conflict")
	default:
		httpx.ErrorCode(w, http.StatusInternalServerError, "internal server error", "internal")
	}
}