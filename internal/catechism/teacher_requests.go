package catechism

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

type teacherRequest struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	ClassID   string    `json:"classId"`
	ClassName string    `json:"className"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"createdAt"`
}

// Teacher request reviews use the current database role and church assignment.
// This avoids rejecting a newly promoted church admin whose access token still
// contains their previous church claim, while keeping approval church-scoped.
func (h *Handler) canReviewTeacherRequests(r *http.Request, userID, churchID string) (bool, error) {
	var allowed bool
	err := h.svc.repo.pool.QueryRow(r.Context(), `SELECT EXISTS(
		SELECT 1 FROM users WHERE id=$1 AND (
			role='super_admin' OR (role='church_admin' AND church_id::text=$2)
		)
	)`, userID, churchID).Scan(&allowed)
	return allowed, err
}

func (h *Handler) requestTeacher(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	if id.Role != auth.RoleUser || id.UserID == "" || id.ChurchID == "" {
		h.writeError(w, ErrForbidden)
		return
	}
	var in struct {
		ClassID string `json:"classId"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil || strings.TrimSpace(in.ClassID) == "" {
		httpx.ErrorCode(w, http.StatusBadRequest, "select a class", "bad_request")
		return
	}
	in.ClassID = strings.TrimSpace(in.ClassID)
	var requestID string
	err := h.svc.repo.pool.QueryRow(r.Context(), `INSERT INTO catechism_teacher_requests(church_id,user_id,class_id)
		SELECT u.church_id,u.id,c.id FROM users u JOIN catechism_classes c
			ON c.id=$3 AND c.church_id=u.church_id
		WHERE u.id=$1 AND u.church_id=$2 AND u.role='user'
		AND NOT EXISTS(SELECT 1 FROM catechism_teachers t WHERE t.user_id=u.id AND t.class_id=c.id)
		AND c.teacher_user_id IS DISTINCT FROM u.id
		ON CONFLICT (church_id,user_id,class_id) WHERE status='pending' AND class_id IS NOT NULL DO NOTHING
		RETURNING id`, id.UserID, id.ChurchID, in.ClassID).Scan(&requestID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		h.writeError(w, err)
		return
	}
	var status string
	err = h.svc.repo.pool.QueryRow(r.Context(), `SELECT CASE WHEN EXISTS(
			SELECT 1 FROM catechism_teachers t WHERE t.user_id=$1 AND t.class_id=$3) OR EXISTS(
			SELECT 1 FROM catechism_classes c WHERE c.teacher_user_id=$1 AND c.id=$3)
			THEN 'approved' ELSE COALESCE((SELECT status FROM catechism_teacher_requests
			WHERE user_id=$1 AND church_id=$2 AND class_id=$3 ORDER BY created_at DESC LIMIT 1),'none') END`,
		id.UserID, id.ChurchID, in.ClassID).Scan(&status)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if status == "none" {
		h.writeError(w, ErrNotFound)
		return
	}
	code := http.StatusOK
	if requestID != "" {
		code = http.StatusCreated
	}
	httpx.JSON(w, code, map[string]string{"status": status})
}

func (h *Handler) listTeacherRequests(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")
	allowed, err := h.canReviewTeacherRequests(r, id.UserID, churchID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !allowed {
		h.writeError(w, ErrForbidden)
		return
	}
	rows, err := h.svc.repo.pool.Query(r.Context(), `SELECT q.id,q.user_id,COALESCE(q.class_id::text,''),
		COALESCE(c.name,''),u.name,u.email,q.created_at
		FROM catechism_teacher_requests q JOIN users u ON u.id=q.user_id
		LEFT JOIN catechism_classes c ON c.id=q.class_id AND c.church_id=q.church_id
		WHERE q.church_id=$1 AND q.status='pending' AND u.church_id=q.church_id
		ORDER BY q.created_at,q.id`, churchID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	defer rows.Close()
	items := []teacherRequest{}
	for rows.Next() {
		var item teacherRequest
		if err := rows.Scan(&item.ID, &item.UserID, &item.ClassID, &item.ClassName,
			&item.Name, &item.Email, &item.CreatedAt); err != nil {
			h.writeError(w, err)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"requests": items})
}

func (h *Handler) reviewTeacherRequest(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	churchID := chi.URLParam(r, "churchId")
	allowed, err := h.canReviewTeacherRequests(r, id.UserID, churchID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !allowed {
		h.writeError(w, ErrForbidden)
		return
	}
	var in struct {
		Status  string `json:"status"`
		ClassID string `json:"classId"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil || (in.Status != "approved" && in.Status != "rejected") {
		httpx.ErrorCode(w, http.StatusBadRequest, "choose approved or rejected", "bad_request")
		return
	}
	in.ClassID = strings.TrimSpace(in.ClassID)
	if in.Status == "approved" && in.ClassID == "" {
		httpx.ErrorCode(w, http.StatusBadRequest, "select a class for the approved teacher", "bad_request")
		return
	}
	tx, err := h.svc.repo.pool.Begin(r.Context())
	if err != nil {
		h.writeError(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	var userID, requestedClassID string
	err = tx.QueryRow(r.Context(), `SELECT q.user_id,COALESCE(q.class_id::text,'') FROM catechism_teacher_requests q
		JOIN users u ON u.id=q.user_id AND u.church_id=q.church_id AND u.role='user'
		WHERE q.id=$1 AND q.church_id=$2 AND q.status='pending' FOR UPDATE OF q`,
		chi.URLParam(r, "requestId"), churchID).Scan(&userID, &requestedClassID)
	if errors.Is(err, pgx.ErrNoRows) {
		h.writeError(w, ErrNotFound)
		return
	}
	if err != nil {
		h.writeError(w, err)
		return
	}
	if in.Status == "approved" {
		if requestedClassID != "" {
			in.ClassID = requestedClassID
		}
		if in.ClassID == "" {
			httpx.ErrorCode(w, http.StatusBadRequest, "select a class for the approved teacher", "bad_request")
			return
		}
		tag, err := tx.Exec(r.Context(), `INSERT INTO catechism_teachers(class_id,user_id)
			SELECT c.id,$2 FROM catechism_classes c JOIN users u ON u.id=$2 AND u.church_id=c.church_id AND u.role='user'
			WHERE c.id=$1 AND c.church_id=$3 ON CONFLICT DO NOTHING`, in.ClassID, userID, churchID)
		if err != nil {
			h.writeError(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			h.writeError(w, ErrNotFound)
			return
		}
	}
	_, err = tx.Exec(r.Context(), `UPDATE catechism_teacher_requests
		SET status=$2,class_id=CASE WHEN $2='approved' THEN $3::uuid ELSE NULL END,
			reviewed_by=$4,reviewed_at=now()
		WHERE id=$1 AND church_id=$5 AND status='pending'`,
		chi.URLParam(r, "requestId"), in.Status, nullableClassID(in.ClassID, in.Status), id.UserID, churchID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"status": in.Status})
}

func nullableClassID(classID, status string) any {
	if status != "approved" {
		return nil
	}
	return classID
}
