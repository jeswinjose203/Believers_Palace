package community

import (
	"encoding/base64"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

type ListOptions struct {
	Joined bool
	Limit  int
	Before *time.Time
	ID     *string
}

func parseListOptions(r *http.Request) ([]ListOptions, error) {
	q := r.URL.Query()
	if !q.Has("limit") && !q.Has("cursor") && !q.Has("joined") {
		return nil, nil
	}
	page := ListOptions{Limit: 20}
	if q.Has("limit") {
		n, err := strconv.Atoi(q.Get("limit"))
		if err != nil || n < 1 || n > 100 {
			return nil, &ValidationError{"limit must be between 1 and 100"}
		}
		page.Limit = n
	}
	if q.Has("joined") {
		joined, err := strconv.ParseBool(q.Get("joined"))
		if err != nil {
			return nil, &ValidationError{"joined must be true or false"}
		}
		page.Joined = joined
	}
	if q.Has("cursor") {
		cursor := q.Get("cursor")
		if len(cursor) > 128 {
			return nil, &ValidationError{"invalid community cursor"}
		}
		raw, err := base64.RawURLEncoding.DecodeString(cursor)
		timestamp, id, ok := strings.Cut(string(raw), "|")
		at, timeErr := time.Parse(time.RFC3339Nano, timestamp)
		var uuid pgtype.UUID
		if err != nil || !ok || timeErr != nil || uuid.Scan(id) != nil {
			return nil, &ValidationError{"invalid community cursor"}
		}
		page.Before, page.ID = &at, &id
	}
	return []ListOptions{page}, nil
}

func communityCursor(item Community) string {
	return base64.RawURLEncoding.EncodeToString([]byte(item.CreatedAt.UTC().Format(time.RFC3339Nano) + "|" + item.ID))
}
