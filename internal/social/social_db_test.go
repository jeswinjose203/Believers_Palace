package social

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"believers_palace/internal/auth"
	"believers_palace/internal/media"
	"believers_palace/internal/user"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSocialWorkflowsDB(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	suffix := fmt.Sprint(time.Now().UnixNano())
	account := func(label string, verified bool) string {
		t.Helper()
		var id string
		err := db.QueryRow(ctx, `INSERT INTO users(name,email,password_hash,email_verified,phone,phone_verified,username)
            VALUES($1,$2,'unused',true,$3,$4,$5) RETURNING id`,
			label, label+suffix+"@example.test", "+1"+suffix[len(suffix)-12:], verified, label+"_"+suffix).Scan(&id)
		if err != nil {
			t.Fatal(err)
		}
		return id
	}
	alice, bob, other := account("alice", true), account("bob", false), account("other", false)
	defer db.Exec(context.Background(), `DELETE FROM users WHERE id IN ($1,$2,$3)`, alice, bob, other)
	storage, err := media.NewStorage(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	mediaService := media.NewService(storage, "https://example.test", 1<<20)
	router := auth.DebugMiddleware()(New(db, mediaService).Routes(user.NewRepository(db).RequireVerifiedEmail))
	call := func(who, method, path, body string, status int) map[string]any {
		t.Helper()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("X-Debug-User-Id", who)
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		if res.Code != status {
			t.Fatalf("%s %s: got %d, want %d: %s", method, path, res.Code, status, res.Body.String())
		}
		var parsed map[string]any
		if res.Body.Len() > 0 {
			if err := json.Unmarshal(res.Body.Bytes(), &parsed); err != nil {
				t.Fatal(err)
			}
		}
		return parsed
	}

	postBody := `{"body":"A new post","clientId":"11111111111111111111111111111111"}`
	call(bob, "POST", "/posts", postBody, 403)
	var upload bytes.Buffer
	writer := multipart.NewWriter(&upload)
	part, err := writer.CreateFormFile("file", "photo.png")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = part.Write([]byte("\x89PNG\r\n\x1a\n"))
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/media", &upload)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("X-Debug-User-Id", alice)
	res := httptest.NewRecorder()
	router.ServeHTTP(res, req)
	if res.Code != 201 {
		t.Fatalf("upload: %d %s", res.Code, res.Body.String())
	}
	var asset media.UploadResult
	if err := json.Unmarshal(res.Body.Bytes(), &asset); err != nil {
		t.Fatal(err)
	}
	postBody = fmt.Sprintf(`{"body":"A new post","clientId":"11111111111111111111111111111111","mediaKey":%q}`, asset.FileName)
	first := call(alice, "POST", "/posts", postBody, 201)["id"]
	if retry := call(alice, "POST", "/posts", postBody, 201)["id"]; retry != first {
		t.Fatal("Post retry created a duplicate")
	}
	call(bob, "PUT", "/posts/"+first.(string)+"/like", "", 200)
	feed := call(bob, "GET", "/feed", "", 200)["data"].([]any)
	found := false
	for _, row := range feed {
		p := row.(map[string]any)
		if p["id"] == first {
			found = p["likes"] == float64(1) && p["liked"] == true && p["mediaKey"] == asset.FileName
		}
	}
	if !found {
		t.Fatal("Expected the liked post with its attachment")
	}
	call(bob, "DELETE", "/posts/"+first.(string)+"/like", "", 200)
	if _, err := db.Exec(ctx, `INSERT INTO social_posts(author_id,body,client_id)
		SELECT $1,'Ranked seed','ranked-'||i FROM generate_series(1,129) i`, alice); err != nil {
		t.Fatal(err)
	}
	seen := map[any]bool{}
	path := "/feed"
	for page := 0; page < 8; page++ {
		result := call(bob, "GET", path, "", 200)
		for _, raw := range result["data"].([]any) {
			id := raw.(map[string]any)["id"]
			if seen[id] {
				t.Fatal("Ranked cursor repeated a post")
			}
			seen[id] = true
		}
		next, ok := result["nextCursor"].(string)
		if !ok {
			break
		}
		if page == 0 {
			// Interacting mid-scroll changes ranking signals but must leave the
			// in-flight candidate ordering intact.
			call(bob, "PUT", "/posts/"+first.(string)+"/like", "", 200)
		}
		path = "/feed?cursor=" + url.QueryEscape(next)
	}
	if len(seen) != 130 {
		t.Fatalf("Expected 130 unique feed items, got %d", len(seen))
	}

	if len(call(alice, "GET", "/people?q=bob_"+suffix, "", 200)["data"].([]any)) != 1 {
		t.Fatal("Username search did not find Bob")
	}
	send := func(who, peer, body string, key int) string {
		t.Helper()
		data := fmt.Sprintf(`{"peerId":%q,"body":%q,"clientId":%q}`, peer, body, fmt.Sprintf("%032x", key))
		return call(who, "POST", "/messages", data, 201)["id"].(string)
	}
	thread := send(alice, bob, "Hello", 1)
	if send(alice, bob, "Hello", 1) != thread {
		t.Fatal("Expected the same thread on retry")
	}
	history := "/threads/" + thread + "/messages"
	size := func(who, path string) int {
		return len(call(who, "GET", path, "", 200)["data"].([]any))
	}
	if size(bob, "/threads") != 1 || size(bob, history) != 1 || size(other, history) != 0 {
		t.Fatal("Inbox visibility or message idempotency failed")
	}
	call(other, "DELETE", "/threads/"+thread, "", 204)
	if size(bob, history) != 1 {
		t.Fatal("Third party changed the thread")
	}
	call(bob, "DELETE", "/threads/"+thread, "", 204)
	if size(bob, "/threads") != 0 || size(bob, history) != 0 || size(alice, history) != 1 {
		t.Fatal("Deletion should hide history for the requester")
	}
	if send(alice, bob, "New message", 2) != thread || size(bob, history) != 1 || size(alice, history) != 2 {
		t.Fatal("New messages should reopen the chat without restoring deleted history")
	}
}
