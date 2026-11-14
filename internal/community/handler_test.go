package community

import (
	"net/http/httptest"
	"testing"
)

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
