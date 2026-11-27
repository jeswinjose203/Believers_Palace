package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"believers_palace/internal/auth"
	"believers_palace/internal/config"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestCatechismWorkspace(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires migrated disposable PostgreSQL")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	cfg.MaxConns = 10
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	const (
		church       = "ad000000-0000-0000-0000-000000000001"
		otherChurch  = "ad000000-0000-0000-0000-000000000002"
		class        = "ad000000-0000-0000-0000-000000000003"
		otherClass   = "ad000000-0000-0000-0000-000000000004"
		admin        = "ad000000-0000-0000-0000-000000000005"
		guardian     = "ad000000-0000-0000-0000-000000000006"
		outsider     = "ad000000-0000-0000-0000-000000000007"
		otherStudent = "ad000000-0000-0000-0000-000000000008"
		requestID    = "ad000000-0000-0000-0000-000000000009"
	)
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO churches(id,name,address) VALUES ($1,'Catechism test','Test'),($2,'Other catechism test','Test')`, church, otherChurch)
	defer pool.Exec(context.Background(), `DELETE FROM churches WHERE id IN ($1,$2)`, church, otherChurch)
	defer pool.Exec(context.Background(), `DELETE FROM users WHERE email LIKE 'catechism-check-%@example.test'`)
	hash, err := auth.HashPassword("guardian-password")
	if err != nil {
		t.Fatal(err)
	}
	exec(`INSERT INTO users (id,name,email,password_hash,role,church_id) VALUES
		($1,'Admin','catechism-check-admin@example.test',$5,'church_admin',$4),
		($2,'Guardian','catechism-check-guardian@example.test',$5,'user',$4),
		($3,'Outsider','catechism-check-outsider@example.test',$5,'user',$4)`, admin, guardian, outsider, church, hash)
	exec(`INSERT INTO catechism_classes(id,church_id,name,level,status,start_date,end_date,capacity) VALUES
		($1,$3,'Primary class','other','open',CURRENT_DATE,CURRENT_DATE,2002),
		($2,$4,'Other class','other','open',CURRENT_DATE,CURRENT_DATE,10)`, class, otherClass, church, otherChurch)
	exec(`INSERT INTO catechism_enrollments(id,class_id,guardian_id,student_name,date_of_birth,status)
		VALUES ($1,$2,$3,'Other student','2013-01-01','approved')`, otherStudent, otherClass, outsider)

	const secret = "catechism-workspace-integration-only"
	const issuer = "catechism-test"
	appConfig := &config.Config{
		AppEnv: "test", HTTPMaxInFlight: 128, ChatMaxConnections: 128,
		JWT:     config.JWTConfig{Secret: secret, Issuer: issuer, TTL: time.Hour, RefreshTTL: time.Hour},
		Storage: config.StorageConfig{Dir: t.TempDir(), MediaDir: t.TempDir()},
	}
	appCtx, stop := context.WithCancel(ctx)
	defer stop()
	handler, err := New(appCtx, appConfig, pool)
	if err != nil {
		t.Fatal(err)
	}
	makeToken := func(id string, role auth.Role, churchID string) string {
		t.Helper()
		token, err := auth.NewTokenManager(secret, time.Hour, issuer).Generate(id, role, churchID)
		if err != nil {
			t.Fatal(err)
		}
		return token
	}
	adminToken := makeToken(admin, auth.RoleChurchAdmin, church)
	guardianToken := makeToken(guardian, auth.RoleUser, church)
	outsiderToken := makeToken(outsider, auth.RoleUser, church)
	workspace := "/api/catechism-classes/" + class + "/workspace"
	otherWorkspace := "/api/catechism-classes/" + otherClass + "/workspace"

	call := func(method, path, token string, body any) *httptest.ResponseRecorder {
		var raw []byte
		if body != nil {
			raw, _ = json.Marshal(body)
		}
		req := httptest.NewRequest(method, path, bytes.NewReader(raw)).WithContext(ctx)
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}
	request := func(method, path, token string, body any, status int) map[string]json.RawMessage {
		t.Helper()
		rec := call(method, path, token, body)
		if rec.Code != status {
			t.Fatalf("%s %s: got %d, want %d: %s", method, path, rec.Code, status, rec.Body.String())
		}
		var out map[string]json.RawMessage
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	rows := func(out map[string]json.RawMessage, key string) []map[string]any {
		t.Helper()
		var data []map[string]any
		if err := json.Unmarshal(out[key], &data); err != nil {
			t.Fatal(err)
		}
		return data
	}

	request("GET", workspace, "", nil, 401)
	request("GET", "/api/catechism-classes/bad/workspace", adminToken, nil, 404)
	request("POST", otherWorkspace+"/students", adminToken, map[string]any{}, 403)
	request("POST", workspace+"/teachers", guardianToken, map[string]any{}, 403)
	if visible := rows(request("GET", workspace, outsiderToken, nil, 200), "students"); len(visible) != 0 {
		t.Fatalf("unassigned user saw class roster: %v", visible)
	}
	request("POST", workspace+"/unknown", adminToken, map[string]any{}, 404)
	request("POST", workspace+"/teachers", adminToken, map[string]any{"email": "invalid"}, 400)
	request("POST", workspace+"/teachers", adminToken, map[string]any{"email": "missing@example.test"}, 400)
	login := "/api/auth/teacher-login"
	request("POST", login, "", map[string]string{
		"email": "catechism-check-guardian@example.test", "password": "guardian-password",
	}, 401)
	teacher := map[string]any{
		"email": "catechism-check-teacher@example.test", "name": "Teacher", "password": "teacher-password",
	}
	request("POST", workspace+"/teachers", adminToken, teacher, 200)
	request("POST", workspace+"/teachers", adminToken, map[string]any{
		"email": "catechism-check-outsider@example.test", "substitute": true,
	}, 200)
	request("POST", login, "", map[string]string{
		"email": "catechism-check-teacher@example.test", "password": "incorrect-password",
	}, 401)
	out := request("POST", login, "", map[string]string{
		"email": "catechism-check-teacher@example.test", "password": "teacher-password",
	}, 200)
	var teacherToken string
	if err := json.Unmarshal(out["accessToken"], &teacherToken); err != nil || teacherToken == "" {
		t.Fatalf("no teacher access token: %v", err)
	}
	var refreshToken string
	if err := json.Unmarshal(out["refreshToken"], &refreshToken); err != nil || refreshToken == "" {
		t.Fatalf("no teacher refresh token: %v", err)
	}
	refreshed := request("POST", "/api/auth/refresh", "", map[string]string{"refreshToken": refreshToken}, 200)
	if err := json.Unmarshal(refreshed["accessToken"], &teacherToken); err != nil || teacherToken == "" {
		t.Fatalf("no renewed teacher access token: %v", err)
	}
	assigned := rows(request("GET", "/api/catechism-teacher/classes", outsiderToken, nil, 200), "classes")
	if len(assigned) != 1 || assigned[0]["substitute"] != true {
		t.Fatalf("substitute assignments: %v", assigned)
	}
	student := map[string]any{"studentName": "Registered Student", "dateOfBirth": "2014-01-01T00:00:00Z",
		"email": "catechism-check-guardian@example.test"}
	request("POST", workspace+"/students", adminToken, map[string]any{}, 400)
	request("POST", workspace+"/students", adminToken, student, 200)
	request("POST", workspace+"/students", adminToken, student, 409)
	registered := rows(request("GET", workspace, guardianToken, nil, 200), "students")
	if len(registered) != 1 {
		t.Fatalf("guardian roster: %v", registered)
	}
	studentID := registered[0]["id"].(string)
	history := workspace + "/students/" + studentID
	attendance := map[string]any{"enrollmentId": studentID, "date": "2026-11-22", "status": "present"}
	mark := map[string]any{"enrollmentId": studentID, "assessment": "Term exam", "score": 8, "maximum": 10}
	announcement := map[string]any{"title": "Class news", "body": "News", "requestId": requestID}
	syllabus := map[string]any{"title": "Updated syllabus", "body": "Class outline"}

	request("GET", history, adminToken, nil, 404)
	request("GET", otherWorkspace+"/students/"+studentID, teacherToken, nil, 404)
	request("GET", otherWorkspace+"/students/"+otherStudent, teacherToken, nil, 404)
	request("GET", otherWorkspace+"/students/"+otherStudent, guardianToken, nil, 404)
	for _, path := range []string{"/attendance", "/marks", "/syllabus", "/announcement"} {
		request("POST", workspace+path, guardianToken, map[string]any{}, 403)
		request("POST", otherWorkspace+path, teacherToken, map[string]any{}, 403)
		request("POST", workspace+path, teacherToken, map[string]any{}, 400)
	}
	request("POST", workspace+"/attendance", teacherToken, map[string]any{
		"enrollmentId": otherStudent, "date": "2026-11-22", "status": "present",
	}, 400)
	request("POST", workspace+"/attendance", teacherToken, map[string]any{
		"enrollmentId": studentID, "date": "2026-02-30", "status": "present",
	}, 400)
	request("POST", workspace+"/marks", teacherToken, map[string]any{
		"enrollmentId": studentID, "assessment": "Invalid result", "score": 11, "maximum": 10,
	}, 400)
	request("POST", workspace+"/syllabus", teacherToken, map[string]any{
		"title": "Too long", "body": strings.Repeat("x", 65<<10),
	}, 400)
	request("POST", workspace+"/attendance", outsiderToken, map[string]any{
		"enrollmentId": studentID, "date": "2026-11-22", "status": "absent",
	}, 200)
	request("POST", workspace+"/marks", teacherToken, map[string]any{
		"enrollmentId": studentID, "assessment": "Term exam", "score": 7, "maximum": 10,
	}, 200)
	request("POST", workspace+"/attendance", outsiderToken, attendance, 200)
	request("POST", workspace+"/marks", teacherToken, mark, 200)
	request("POST", workspace+"/syllabus", teacherToken, map[string]string{"title": "First syllabus", "body": "First outline"}, 200)
	request("POST", workspace+"/syllabus", teacherToken, syllabus, 200)
	request("POST", workspace+"/announcement", teacherToken, announcement, 200)
	request("POST", workspace+"/announcement", teacherToken, announcement, 200)
	if published := rows(request("GET", workspace, guardianToken, nil, 200), "publications"); len(published) != 1 {
		t.Fatalf("duplicate announcement: %v", published)
	}
	historyData := request("GET", history, guardianToken, nil, 200)
	if len(rows(historyData, "marks")) != 1 || len(rows(historyData, "attendance")) != 1 {
		t.Fatalf("missing history: %v", historyData)
	}

	// Fill a large class and test bounded responses while teachers make concurrent retryable writes.
	exec(`INSERT INTO catechism_enrollments(class_id,guardian_id,student_name,date_of_birth,status)
		SELECT $1,$2,'Load student ' || i,'2013-01-01','approved' FROM generate_series(1,2000) i`, class, outsider)
	exec(`INSERT INTO catechism_publications(class_id,kind,title,body)
		SELECT $1,'announcement','Load announcement ' || i,repeat('x',2000) FROM generate_series(1,100) i`, class)
	exec(`INSERT INTO catechism_attendance(enrollment_id,lesson_date,status)
		SELECT $1,DATE '2025-01-01'+i,'present' FROM generate_series(1,100) i`, studentID)
	firstPage := request("GET", workspace+"?limit=20", teacherToken, nil, 200)
	nextPage := request("GET", workspace+"?page=2&limit=20", teacherToken, nil, 200)
	for _, key := range []string{"students", "publications"} {
		first, next := rows(firstPage, key), rows(nextPage, key)
		if len(first) != 21 || len(next) != 21 || first[20]["id"] != next[0]["id"] {
			t.Fatalf("unstable or unbounded %s page", key)
		}
	}
	if len(rows(request("GET", history+"?page=2", guardianToken, nil, 200), "attendance")) != 21 {
		t.Fatal("unbounded or missing history page")
	}
	cases := []struct {
		method, path, token string
		body                any
	}{
		{"GET", workspace, teacherToken, nil},
		{"GET", workspace, guardianToken, nil},
		{"GET", history, guardianToken, nil},
		{"POST", workspace + "/attendance", teacherToken, attendance},
		{"POST", workspace + "/marks", teacherToken, mark},
		{"POST", workspace + "/announcement", teacherToken, announcement},
		{"POST", workspace + "/syllabus", teacherToken, syllabus},
	}
	const workers, requestsPerWorker = 32, 35
	durations := make([]time.Duration, workers*requestsPerWorker)
	errs := make(chan error, workers)
	var wg sync.WaitGroup
	start := time.Now()
	for worker := 0; worker < workers; worker++ {
		wg.Add(1)
		go func(worker int) {
			defer wg.Done()
			for i := 0; i < requestsPerWorker; i++ {
				c := cases[(worker+i)%len(cases)]
				begin := time.Now()
				rec := call(c.method, c.path, c.token, c.body)
				durations[worker*requestsPerWorker+i] = time.Since(begin)
				if rec.Code != 200 || rec.Body.Len() > 64<<10 {
					errs <- fmt.Errorf("%s %s: status=%d size=%d", c.method, c.path, rec.Code, rec.Body.Len())
					return
				}
			}
		}(worker)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	elapsed := time.Since(start)
	sort.Slice(durations, func(i, j int) bool { return durations[i] < durations[j] })
	t.Logf("%d mixed workspace requests in %s, p95=%s, with %d workers and %d database connections",
		len(durations), elapsed, durations[len(durations)*95/100-1], workers, cfg.MaxConns)

	capacityResults := make(chan int, 2)
	for _, name := range []string{"Last candidate A", "Last candidate B"} {
		go func() {
			capacityResults <- call("POST", workspace+"/students", adminToken, map[string]any{
				"studentName": name, "dateOfBirth": "2014-01-01T00:00:00Z",
				"email": "catechism-check-guardian@example.test",
			}).Code
		}()
	}
	capacityStatuses := []int{<-capacityResults, <-capacityResults}
	sort.Ints(capacityStatuses)
	if capacityStatuses[0] != 200 || capacityStatuses[1] != 409 {
		t.Errorf("concurrent requests for the last seat: %v", capacityStatuses)
	}
	for _, check := range []struct {
		sql  string
		args []any
	}{
		{`SELECT count(*) FROM catechism_publications WHERE id=$1`, []any{requestID}},
		{`SELECT count(*) FROM catechism_publications WHERE class_id=$1 AND kind='syllabus' AND title='Updated syllabus'`, []any{class}},
		{`SELECT count(*) FROM catechism_marks WHERE enrollment_id=$1 AND assessment='Term exam' AND score=8`, []any{studentID}},
		{`SELECT count(*) FROM catechism_attendance WHERE enrollment_id=$1 AND lesson_date='2026-11-22' AND status='present'`, []any{studentID}},
	} {
		var count int
		if err := pool.QueryRow(ctx, check.sql, check.args...).Scan(&count); err != nil || count != 1 {
			t.Errorf("retry invariant failed: count=%d error=%v", count, err)
		}
	}

	exec(`DELETE FROM catechism_teachers WHERE class_id=$1 AND user_id=(
		SELECT id FROM users WHERE email='catechism-check-teacher@example.test')`, class)
	request("GET", history, teacherToken, nil, 404)
	request("POST", workspace+"/attendance", teacherToken, attendance, 403)
	request("POST", login, "", map[string]string{
		"email": "catechism-check-teacher@example.test", "password": "teacher-password",
	}, 401)
}
