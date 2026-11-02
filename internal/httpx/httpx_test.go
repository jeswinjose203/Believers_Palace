package httpx

import "testing"

func TestNewPagination(t *testing.T) {
	tests := []struct {
		page, limit, total int
		wantTotalPages     int
	}{
		{1, 20, 0, 0},
		{1, 20, 20, 1},
		{1, 20, 21, 2},
		{2, 10, 95, 10},
		{1, 0, 50, 0}, // guard against divide-by-zero
	}
	for _, tt := range tests {
		p := NewPagination(tt.page, tt.limit, tt.total)
		if p.TotalPages != tt.wantTotalPages {
			t.Errorf("NewPagination(%d,%d,%d).TotalPages = %d, want %d",
				tt.page, tt.limit, tt.total, p.TotalPages, tt.wantTotalPages)
		}
	}
}
