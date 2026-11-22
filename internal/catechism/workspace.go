package catechism

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"believers_palace/internal/auth"
	"believers_palace/internal/httpx"
)

type workspaceInput struct {
	RequestID string `json:"requestId"`
	EnrollmentRequest
	Email        string `json:"email"`
	Name         string `json:"name"`
	Password     string `json:"password"`
	Substitute   bool   `json:"substitute"`
	EnrollmentID string `json:"enrollmentId"`
	Date         string `json:"date"`
	Status       string `json:"status"`
	Assessment   string `json:"assessment"`
	Score        *int   `json:"score"`
	Maximum      int    `json:"maximum"`
	Title        string `json:"title"`
	Body         string `json:"body"`
}

func (h *Handler) TeacherRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/", h.teacherClasses)
	return r
}

func (h *Handler) teacherClasses(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	p := httpx.ParsePageParams(r)
	h.workspaceJSON(w, r, `WITH assigned AS (
		SELECT class_id FROM catechism_teachers WHERE user_id=$1
		UNION SELECT id FROM catechism_classes WHERE teacher_user_id=$1
	), classes AS (
		SELECT c.id, c.name, ch.name AS church, COALESCE(t.substitute,false) AS substitute
		FROM assigned a JOIN catechism_classes c ON c.id=a.class_id
		JOIN churches ch ON ch.id=c.church_id
		LEFT JOIN catechism_teachers t ON t.class_id=c.id AND t.user_id=$1
		ORDER BY ch.name, c.name, c.id LIMIT $2 OFFSET $3
	)
	SELECT jsonb_build_object('classes', COALESCE(jsonb_agg(to_jsonb(classes)
		ORDER BY church,name,id), '[]')) FROM classes`, id.UserID, p.Limit+1, p.Offset)
}
func (h *Handler) workspaceJSON(w http.ResponseWriter, r *http.Request, query string, args ...any) {
	w.Header().Set("Cache-Control", "no-store")
	var result json.RawMessage
	if err := h.svc.repo.pool.QueryRow(r.Context(), query, args...).Scan(&result); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			err = ErrNotFound
		}
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, result)
}

func (h *Handler) workspaceAccess(r *http.Request) (*Class, bool, bool, error) {
	id := auth.MustFromContext(r.Context())
	var classID pgtype.UUID
	if err := classID.Scan(chi.URLParam(r, "classId")); err != nil {
		return nil, false, false, ErrNotFound
	}
	var cls Class
	var admin, teacher bool
	err := h.svc.repo.pool.QueryRow(r.Context(), `SELECT c.id,c.church_id,c.min_age,c.max_age,c.start_date,
		a.admin,a.teacher FROM (`+workspacePermissions+`) a JOIN catechism_classes c ON c.id=a.id`,
		classID, id.UserID, id.Role, id.ChurchID).
		Scan(&cls.ID, &cls.ChurchID, &cls.MinAge, &cls.MaxAge, &cls.StartDate, &admin, &teacher)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return &cls, admin, teacher, err
}

const workspaceTeacher = `(COALESCE(c.teacher_user_id=$2,false) OR EXISTS (
	SELECT 1 FROM catechism_teachers WHERE class_id=c.id AND user_id=$2
))`

const workspacePermissions = `
	SELECT c.id, c.teacher_user_id,
		($3='super_admin' OR ($3='church_admin' AND c.church_id=NULLIF($4,'')::uuid)) AS admin,
		` + workspaceTeacher + ` AS teacher
	FROM catechism_classes c WHERE c.id=$1`

func (h *Handler) getWorkspace(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	var classID pgtype.UUID
	if err := classID.Scan(chi.URLParam(r, "classId")); err != nil {
		h.writeError(w, ErrNotFound)
		return
	}
	p := httpx.ParsePageParams(r)
	h.workspaceJSON(w, r, `WITH access AS (`+workspacePermissions+`),
		students AS (
			SELECT page.* FROM access a CROSS JOIN LATERAL (
				(SELECT e.id,e.student_name AS name,e.status,(a.teacher OR e.guardian_id=$2) AS "canViewHistory"
				FROM catechism_enrollments e WHERE e.class_id=a.id AND (a.teacher OR a.admin)
				AND e.status IN ('approved','completed')
				ORDER BY e.student_name,e.id LIMIT $5 OFFSET $6)
				UNION ALL
				(SELECT e.id,e.student_name,e.status,true
				FROM catechism_enrollments e WHERE e.class_id=a.id AND NOT (a.teacher OR a.admin)
				AND e.guardian_id=$2 AND e.status IN ('approved','completed')
				ORDER BY e.student_name,e.id LIMIT $5 OFFSET $6)
			) page
		), publications AS (
			SELECT p.id,p.kind,p.title,p.body,p.published_at FROM access a
			JOIN catechism_publications p ON p.class_id=a.id
			WHERE p.kind='announcement' AND (a.teacher OR a.admin OR EXISTS (
				SELECT 1 FROM catechism_enrollments WHERE class_id=a.id AND guardian_id=$2
				AND status IN ('approved','completed')
			))
			ORDER BY p.published_at DESC,p.id DESC LIMIT $5 OFFSET $6
		), teachers AS (
			SELECT u.id,u.name,u.email,COALESCE(t.substitute,false) AS substitute
			FROM (
				SELECT id AS class_id,teacher_user_id AS user_id FROM access WHERE admin AND teacher_user_id IS NOT NULL
				UNION SELECT t.class_id,t.user_id FROM access a JOIN catechism_teachers t ON t.class_id=a.id WHERE a.admin
			) assigned JOIN users u ON u.id=assigned.user_id
			LEFT JOIN catechism_teachers t ON t.class_id=assigned.class_id AND t.user_id=u.id
			ORDER BY u.name,u.id LIMIT $5 OFFSET $6
		)
		SELECT jsonb_build_object('canRegister',a.admin,'canTeach',a.teacher,
			'students',COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.name,s.id) FROM students s),'[]'),
			'teachers',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.name,t.id) FROM teachers t),'[]'),
			'publications',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.published_at DESC,p.id DESC) FROM publications p),'[]'),
			'syllabus',(SELECT to_jsonb(p) - 'class_id' FROM catechism_publications p
				WHERE p.class_id=a.id AND p.kind='syllabus' AND (a.teacher OR a.admin OR EXISTS (
					SELECT 1 FROM catechism_enrollments WHERE class_id=a.id AND guardian_id=$2
					AND status IN ('approved','completed')
				)))
		) FROM access a`, classID, id.UserID, id.Role, id.ChurchID, p.Limit+1, p.Offset)
}

func (h *Handler) studentHistory(w http.ResponseWriter, r *http.Request) {
	id := auth.MustFromContext(r.Context())
	var classID, studentID pgtype.UUID
	if classID.Scan(chi.URLParam(r, "classId")) != nil ||
		studentID.Scan(chi.URLParam(r, "studentId")) != nil {
		h.writeError(w, ErrNotFound)
		return
	}
	p := httpx.ParsePageParams(r)
	h.workspaceJSON(w, r, `WITH access AS (`+workspacePermissions+`),
		student AS (
			SELECT e.id FROM access a JOIN catechism_enrollments e ON e.class_id=a.id
			WHERE e.id=$5 AND e.status IN ('approved','completed') AND (a.teacher OR e.guardian_id=$2)
		), attendance AS (
			SELECT a.* FROM student e JOIN catechism_attendance a ON a.enrollment_id=e.id
			ORDER BY a.lesson_date DESC LIMIT $6 OFFSET $7
		), marks AS (
			SELECT m.* FROM student e JOIN catechism_marks m ON m.enrollment_id=e.id
			ORDER BY m.published_at DESC,m.assessment LIMIT $6 OFFSET $7
		)
		SELECT jsonb_build_object(
			'attendance',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.lesson_date DESC) FROM attendance a),'[]'),
			'marks',COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.published_at DESC,m.assessment) FROM marks m),'[]')
		) FROM student`, classID, id.UserID, id.Role, id.ChurchID, studentID, p.Limit+1, p.Offset)
}
func (h *Handler) changeWorkspace(w http.ResponseWriter, r *http.Request) {
	cls, admin, teacher, err := h.workspaceAccess(r)
	if err != nil {
		h.writeError(w, err)
		return
	}
	action := chi.URLParam(r, "action")
	switch action {
	case "students", "teachers":
		if !admin {
			h.writeError(w, ErrForbidden)
			return
		}
	case "attendance", "marks", "syllabus", "announcement":
		if !teacher {
			h.writeError(w, ErrForbidden)
			return
		}
	default:
		h.writeError(w, ErrNotFound)
		return
	}
	var in workspaceInput
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	if err := httpx.DecodeJSON(r, &in); err != nil {
		h.writeError(w, invalid("invalid JSON body"))
		return
	}
	ctx := r.Context()
	userID := auth.MustFromContext(ctx).UserID
	repo := h.svc.repo
	switch action {
	case "students":
		err = repo.registerStudent(ctx, cls, in)
	case "teachers":
		err = repo.registerTeacher(ctx, cls, in)
	case "attendance", "marks":
		err = repo.saveStudentRecord(ctx, cls.ID, userID, action, in)
	default:
		err = repo.publish(ctx, cls.ID, userID, action, in)
	}
	if err != nil {
		h.writeError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"saved": true})
}

func workspaceEmail(value string) (string, error) {
	email := strings.ToLower(strings.TrimSpace(value))
	addr, err := mail.ParseAddress(email)
	if err != nil || addr.Address != email {
		return "", invalid("enter a valid email address")
	}
	return email, nil
}

func (r *Repository) registerStudent(ctx context.Context, cls *Class, in workspaceInput) error {
	if err := validateEnrollmentRequest(in.EnrollmentRequest, cls); err != nil {
		return err
	}
	email, err := workspaceEmail(in.Email)
	if err != nil {
		return err
	}
	var guardianID string
	err = r.pool.QueryRow(ctx, `SELECT id FROM users WHERE email=$1`, email).Scan(&guardianID)
	if errors.Is(err, pgx.ErrNoRows) {
		return invalid("the guardian needs an existing account")
	}
	if err != nil {
		return err
	}
	_, err = r.createEnrollment(ctx, cls.ID, guardianID, in.EnrollmentRequest, EnrollApproved)
	return err
}

func (r *Repository) registerTeacher(ctx context.Context, cls *Class, in workspaceInput) error {
	email, err := workspaceEmail(in.Email)
	if err != nil {
		return err
	}
	var hash string
	if in.Password != "" {
		if len(in.Password) < 8 || len(in.Password) > 72 || strings.TrimSpace(in.Name) == "" {
			return invalid("new teacher accounts require a name and an 8–72 byte password")
		}
		hash, err = auth.HashPassword(in.Password)
		if err != nil {
			return err
		}
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if hash != "" {
		_, err = tx.Exec(ctx, `INSERT INTO users (name,email,password_hash,church_id)
			VALUES ($1,$2,$3,$4) ON CONFLICT (email) DO NOTHING`,
			strings.TrimSpace(in.Name), email, hash, cls.ChurchID)
		if err != nil {
			return err
		}
	}
	tag, err := tx.Exec(ctx, `INSERT INTO catechism_teachers (class_id,user_id,substitute)
		SELECT $1::uuid,id,$3::boolean FROM users WHERE email=$2
		ON CONFLICT (class_id,user_id) DO UPDATE SET substitute=EXCLUDED.substitute`,
		cls.ID, email, in.Substitute)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return invalid("provide a name and initial password to create this teacher account")
	}
	return tx.Commit(ctx)
}

func (r *Repository) saveStudentRecord(ctx context.Context, classID, userID, action string, in workspaceInput) error {
	var enrollmentUUID pgtype.UUID
	if err := enrollmentUUID.Scan(in.EnrollmentID); err != nil {
		return invalid("select a registered student")
	}
	const eligible = `WITH eligible AS (
		SELECT e.id FROM catechism_classes c JOIN catechism_enrollments e ON e.class_id=c.id
		WHERE c.id=$1 AND e.id=$3 AND e.status IN ('approved','completed') AND ` + workspaceTeacher + `
		FOR SHARE OF c,e
	), saved AS (`
	const result = `) SELECT EXISTS(SELECT 1 FROM eligible)`
	var query string
	var args []any
	if action == "attendance" {
		date, err := time.Parse(time.DateOnly, in.Date)
		if err != nil || (in.Status != "present" && in.Status != "absent" && in.Status != "excused") {
			return invalid("select a date and an attendance status")
		}
		query = eligible + `INSERT INTO catechism_attendance (enrollment_id,lesson_date,status)
			SELECT id,$4::date,$5::text FROM eligible ON CONFLICT (enrollment_id,lesson_date)
			DO UPDATE SET status=EXCLUDED.status
			WHERE catechism_attendance.status IS DISTINCT FROM EXCLUDED.status` + result
		args = []any{date, in.Status}
	} else {
		assessment := strings.TrimSpace(in.Assessment)
		if assessment == "" || len(assessment) > 200 || in.Score == nil ||
			*in.Score < 0 || in.Maximum < 1 || *in.Score > in.Maximum || in.Maximum > 2147483647 {
			return invalid("enter an assessment and a score between zero and the maximum")
		}
		query = eligible + `INSERT INTO catechism_marks (enrollment_id,assessment,score,maximum)
			SELECT id,$4::text,$5::integer,$6::integer FROM eligible ON CONFLICT (enrollment_id,assessment)
			DO UPDATE SET score=EXCLUDED.score,maximum=EXCLUDED.maximum,published_at=now()
			WHERE (catechism_marks.score,catechism_marks.maximum) IS DISTINCT FROM (EXCLUDED.score,EXCLUDED.maximum)` + result
		args = []any{assessment, *in.Score, in.Maximum}
	}
	var eligibleStudent bool
	err := r.pool.QueryRow(ctx, query, append([]any{classID, userID, enrollmentUUID}, args...)...).Scan(&eligibleStudent)
	if err == nil && !eligibleStudent {
		return invalid("select a registered student in this class")
	}
	return err
}

func (r *Repository) publish(ctx context.Context, classID, userID, kind string, in workspaceInput) error {
	title, body := strings.TrimSpace(in.Title), strings.TrimSpace(in.Body)
	if title == "" || body == "" || len(title) > 200 || len(body) > 20000 {
		return invalid("enter a title and publication text within the length limits")
	}
	var publicationID pgtype.UUID
	if in.RequestID != "" {
		if kind != "announcement" || publicationID.Scan(in.RequestID) != nil {
			return invalid("invalid publication request ID")
		}
	}
	query := `WITH eligible AS (
		SELECT c.id FROM catechism_classes c WHERE c.id=$1 AND ` + workspaceTeacher + ` FOR SHARE
	), saved AS (
		INSERT INTO catechism_publications (id,class_id,kind,title,body)
		SELECT COALESCE($6::uuid,gen_random_uuid()),id,$3::text,$4::text,$5::text FROM eligible`
	if kind == "syllabus" {
		query += ` ON CONFLICT (class_id) WHERE kind='syllabus'
			DO UPDATE SET title=EXCLUDED.title,body=EXCLUDED.body,published_at=now()
			WHERE (catechism_publications.title,catechism_publications.body) IS DISTINCT FROM (EXCLUDED.title,EXCLUDED.body)`
	} else {
		query += ` ON CONFLICT (id) DO NOTHING`
	}
	var allowed bool
	err := r.pool.QueryRow(ctx, query+`) SELECT EXISTS(SELECT 1 FROM eligible)`,
		classID, userID, kind, title, body, publicationID).Scan(&allowed)
	if err == nil && !allowed {
		return ErrForbidden
	}
	return err
}
