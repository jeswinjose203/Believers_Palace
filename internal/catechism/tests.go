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

type catechismTest struct {
	Name       string    `json:"name"`
	Maximum    int       `json:"maximum"`
	MarksCount int       `json:"marksCount"`
	CreatedAt  time.Time `json:"createdAt"`
}

type catechismTestMark struct {
	EnrollmentID string `json:"enrollmentId"`
	StudentName  string `json:"studentName"`
	Score        *int   `json:"score"`
	Maximum      int    `json:"maximum"`
}

func (h *Handler) listTests(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	id := auth.MustFromContext(r.Context())
	rows, err := h.svc.repo.pool.Query(r.Context(), `SELECT t.name,t.maximum,
		count(e.id) FILTER (WHERE e.id IS NOT NULL AND e.status IN ('approved','completed')
			AND ($3::boolean OR e.guardian_id=$2::uuid))::int AS marks_count,t.created_at
		FROM catechism_tests t LEFT JOIN catechism_marks m ON m.assessment=t.name
		LEFT JOIN catechism_enrollments e ON e.id=m.enrollment_id AND e.class_id=t.class_id
		WHERE t.class_id=$1 GROUP BY t.id ORDER BY t.created_at DESC,t.name`,
		cls.ID, id.UserID, admin || teacher)
	if err != nil {
		h.writeError(w, err)
		return
	}
	defer rows.Close()
	items := []catechismTest{}
	for rows.Next() {
		var item catechismTest
		if err := rows.Scan(&item.Name, &item.Maximum, &item.MarksCount, &item.CreatedAt); err != nil {
			h.writeError(w, err)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"tests": items})
}

func (h *Handler) createTest(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !admin && !teacher {
		h.writeError(w, ErrForbidden)
		return
	}
	var in struct {
		Name    string `json:"name"`
		Maximum int    `json:"maximum"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "invalid JSON body", "bad_request")
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	if in.Name == "" || len(in.Name) > 200 || in.Maximum < 1 {
		httpx.ErrorCode(w, http.StatusBadRequest, "enter a test name and a positive maximum mark", "bad_request")
		return
	}
	id := auth.MustFromContext(r.Context())
	var item catechismTest
	err = h.svc.repo.pool.QueryRow(r.Context(), `INSERT INTO catechism_tests(class_id,name,maximum,created_by)
		VALUES ($1,$2,$3,$4) ON CONFLICT (class_id,name) DO NOTHING
		RETURNING name,maximum,0,created_at`, cls.ID, in.Name, in.Maximum, id.UserID).
		Scan(&item.Name, &item.Maximum, &item.MarksCount, &item.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.ErrorCode(w, http.StatusConflict, "a test with this name already exists", "conflict")
		return
	}
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, item)
}

func (h *Handler) getTestMarks(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	id := auth.MustFromContext(r.Context())
	name := chi.URLParam(r, "testName")
	var test catechismTest
	err = h.svc.repo.pool.QueryRow(r.Context(), `SELECT name,maximum,created_at FROM catechism_tests WHERE class_id=$1 AND name=$2`, cls.ID, name).
		Scan(&test.Name, &test.Maximum, &test.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		h.writeError(w, ErrNotFound)
		return
	}
	if err != nil {
		h.writeError(w, err)
		return
	}
	rows, err := h.svc.repo.pool.Query(r.Context(), `SELECT e.id,e.student_name,m.score,t.maximum
		FROM catechism_enrollments e CROSS JOIN catechism_tests t
		LEFT JOIN catechism_marks m ON m.enrollment_id=e.id AND m.assessment=t.name
		WHERE e.class_id=$1 AND t.class_id=e.class_id AND t.name=$2 AND e.status IN ('approved','completed')
		AND ($3::boolean OR e.guardian_id=$4::uuid)
		ORDER BY e.student_name,e.id`, cls.ID, name, admin || teacher, id.UserID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	defer rows.Close()
	marks := []catechismTestMark{}
	for rows.Next() {
		var item catechismTestMark
		if err := rows.Scan(&item.EnrollmentID, &item.StudentName, &item.Score, &item.Maximum); err != nil {
			h.writeError(w, err)
			return
		}
		marks = append(marks, item)
	}
	if err := rows.Err(); err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"test": test, "marks": marks})
}

func (h *Handler) updateTestMark(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.classMaterialAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !admin && !teacher {
		h.writeError(w, ErrForbidden)
		return
	}
	var in struct {
		Score *int `json:"score"`
	}
	if err := httpx.DecodeJSON(r, &in); err != nil || in.Score == nil {
		httpx.ErrorCode(w, http.StatusBadRequest, "enter a score", "bad_request")
		return
	}
	id := auth.MustFromContext(r.Context())
	var saved bool
	err = h.svc.repo.pool.QueryRow(r.Context(), `WITH eligible AS (
		SELECT e.id,t.name,t.maximum FROM catechism_enrollments e
		JOIN catechism_tests t ON t.class_id=e.class_id AND t.name=$2
		WHERE e.id=$3 AND e.class_id=$1 AND e.status IN ('approved','completed')
		AND ($6='super_admin' OR ($6='church_admin' AND EXISTS(SELECT 1 FROM catechism_classes c WHERE c.id=$1 AND c.church_id=NULLIF($7,'')::uuid))
			OR EXISTS(SELECT 1 FROM catechism_teachers ct WHERE ct.class_id=$1 AND ct.user_id=$4)
			OR EXISTS(SELECT 1 FROM catechism_classes c WHERE c.id=$1 AND c.teacher_user_id=$4))
	), saved AS (
		INSERT INTO catechism_marks(enrollment_id,assessment,score,maximum)
		SELECT id,name,$5,maximum FROM eligible WHERE $5 BETWEEN 0 AND maximum
		ON CONFLICT (enrollment_id,assessment) DO UPDATE
		SET score=EXCLUDED.score,maximum=EXCLUDED.maximum,published_at=now()
		RETURNING enrollment_id
	) SELECT EXISTS(SELECT 1 FROM eligible) AND EXISTS(SELECT 1 FROM saved)`,
		cls.ID, chi.URLParam(r, "testName"), chi.URLParam(r, "enrollmentId"), id.UserID, *in.Score, id.Role, id.ChurchID).Scan(&saved)
	if err != nil {
		h.writeError(w, err)
		return
	}
	if !saved {
		httpx.ErrorCode(w, http.StatusBadRequest, "check the selected approved student and score", "bad_request")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"saved": true})
}
