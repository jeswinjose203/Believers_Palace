package server

import (
	"net"
	"net/http"
	"net/netip"

	"believers_palace/internal/httpx"
)

// trustedProxyIP uses the single address overwritten by the trusted ingress.
func trustedProxyIP(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		values := r.Header.Values("X-Real-IP")
		if len(values) == 1 {
			if ip, err := netip.ParseAddr(values[0]); err == nil && ip.Zone() == "" {
				r.RemoteAddr = net.JoinHostPort(ip.Unmap().String(), "0")
			}
		}
		next.ServeHTTP(w, r)
	})
}

// limitInFlight sheds excess traffic before it can queue on the database pool.
func limitInFlight(limit int, exemptPath string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		if limit <= 0 {
			return next
		}
		slots := make(chan struct{}, limit)
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if exemptPath != "" && r.URL.Path == exemptPath {
				next.ServeHTTP(w, r)
				return
			}
			select {
			case slots <- struct{}{}:
				defer func() { <-slots }()
				next.ServeHTTP(w, r)
			default:
				w.Header().Set("Retry-After", "1")
				httpx.ErrorCode(w, http.StatusServiceUnavailable, "server is busy, try again shortly", "server_busy")
			}
		})
	}
}
