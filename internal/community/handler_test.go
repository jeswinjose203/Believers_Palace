package community

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"believers_palace/internal/auth"
)

func TestUpdateCommunityRoute(t *testing.T) {
	repo := newMemoryStore()
	group, err := repo.Create(context.Background(), "admin", "Old name", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	repo.members[group.ID]["member"] = &Membership{Status: "active"}
	router := auth.DebugMiddleware()(NewHandler(NewService(repo, testUsers{})).Routes())
	body := `{"name":" New name ","description":" Updated description ","image":" https://example.test/photo.jpg "}`

	for _, tc := range []struct {
		user, body string
		status     int
	}{
		{"member", body, http.StatusForbidden},
		{"admin", `{"name":" "}`, http.StatusBadRequest},
		{"admin", body, http.StatusOK},
	} {
		req := httptest.NewRequest(http.MethodPut, "/"+group.ID, strings.NewReader(tc.body))
		req.Header.Set("X-Debug-User-Id", tc.user)
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		if res.Code != tc.status {
			t.Fatalf("%s: status %d, want %d: %s", tc.user, res.Code, tc.status, res.Body.String())
		}
		if res.Code == http.StatusOK {
			var updated Community
			if err := json.NewDecoder(res.Body).Decode(&updated); err != nil {
				t.Fatal(err)
			}
			if updated.Name != "New name" || updated.Description != "Updated description" ||
				updated.Image == nil || *updated.Image != "https://example.test/photo.jpg" {
				t.Fatalf("unexpected updated details: %+v", updated)
			}
		}
	}
}

func TestParseCursorQuery(t *testing.T) {
	tests := []struct {
		url       string
		wantAfter int64
		wantSet   bool
		wantError bool
	}{
		{url: "/?latest=1"},
		{url: "/?after=0", wantSet: true},
		{url: "/?after=12", wantAfter: 12, wantSet: true},
		{url: "/?after=-1", wantError: true},
		{url: "/?before=0", wantError: true},
	}

	for _, test := range tests {
		t.Run(test.url, func(t *testing.T) {
			query, err := parseCursorQuery(httptest.NewRequest("GET", test.url, nil))
			if (err != nil) != test.wantError {
				t.Fatalf("error = %v, wantError %v", err, test.wantError)
			}
			if err == nil && (query.After != test.wantAfter || query.AfterSet != test.wantSet) {
				t.Fatalf("query = %+v", query)
			}
		})
	}
}
