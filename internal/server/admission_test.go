package server

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestTrustedProxyIPUsesOneValidatedHeader(t *testing.T) {
	handler := trustedProxyIP(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(r.RemoteAddr))
	}))
	for _, example := range []struct {
		realIP []string
		want   string
	}{
		{nil, "192.0.2.1:1234"},
		{[]string{"198.51.100.8", "198.51.100.9"}, "192.0.2.1:1234"},
		{[]string{"malformed"}, "192.0.2.1:1234"},
		{[]string{"::ffff:198.51.100.8"}, "198.51.100.8:0"},
	} {
		req := httptest.NewRequest("GET", "/", nil)
		req.Header.Set("X-Forwarded-For", "198.51.100.99")
		for _, value := range example.realIP {
			req.Header.Add("X-Real-IP", value)
		}
		resp := httptest.NewRecorder()
		handler.ServeHTTP(resp, req)
		if got := resp.Body.String(); got != example.want {
			t.Errorf("X-Real-IP %v produced %q, want %q", example.realIP, got, example.want)
		}
	}
}

func TestLimitInFlightRejectsAndRecovers(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	done := make(chan struct{})
	handler := limitInFlight(1, "/live")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/slow" {
			close(started)
			<-release
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	go func() {
		defer close(done)
		handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/slow", nil))
	}()
	<-started
	defer func() {
		close(release)
		<-done
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest("GET", "/ordinary", nil))
		if response.Code != http.StatusNoContent {
			t.Errorf("request after release returned %d", response.Code)
		}
	}()
	busy := httptest.NewRecorder()
	handler.ServeHTTP(busy, httptest.NewRequest("GET", "/ordinary", nil))
	if busy.Code != http.StatusServiceUnavailable || busy.Header().Get("Retry-After") == "" {
		t.Errorf("overload returned %d with headers %v", busy.Code, busy.Header())
	}
	exempt := httptest.NewRecorder()
	handler.ServeHTTP(exempt, httptest.NewRequest("GET", "/live", nil))
	if exempt.Code != http.StatusNoContent {
		t.Errorf("exempt request returned %d", exempt.Code)
	}
}
