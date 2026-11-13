package personalcalendar
 
import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "strings"
    "sync"
    "time"
)
 
type holidayCacheEntry struct {
    items     []Holiday
    expiresAt time.Time
}
 
var (
    holidayMu    sync.Mutex
    holidayCache = map[string]holidayCacheEntry{}
)
 
type nagerHoliday struct {
    Date string `json:"date"`
    Name string `json:"name"`
}
 
func fetchPublicHolidays(ctx context.Context, year int, country string) ([]Holiday, error) {
    country = strings.ToUpper(strings.TrimSpace(country))
    if country == "" {
        country = "IN"
    }
    key := fmt.Sprintf("%d:%s", year, country)
 
    holidayMu.Lock()
    if e, ok := holidayCache[key]; ok && time.Now().Before(e.expiresAt) {
        holidayMu.Unlock()
        return e.items, nil
    }
    holidayMu.Unlock()
 
    url := fmt.Sprintf("https://date.nager.at/api/v3/PublicHolidays/%d/%s", year, country)
    req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
    if err != nil {
        return nil, err
    }
    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()
    if resp.StatusCode != http.StatusOK {
        return nil, fmt.Errorf("holidays api: status %d", resp.StatusCode)
    }
    var raw []nagerHoliday
    if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
        return nil, err
    }
    items := make([]Holiday, 0, len(raw))
    for _, h := range raw {
        items = append(items, Holiday{Date: h.Date, Name: h.Name})
    }
 
    holidayMu.Lock()
    holidayCache[key] = holidayCacheEntry{items: items, expiresAt: time.Now().Add(24 * time.Hour)}
    holidayMu.Unlock()
    return items, nil
}
 
func holidaysInRange(ctx context.Context, country string, from, to time.Time) ([]Holiday, error) {
    years := map[int]struct{}{}
    years[from.Year()] = struct{}{}
    years[to.Year()] = struct{}{}
    var all []Holiday
    for y := range years {
        part, err := fetchPublicHolidays(ctx, y, country)
        if err != nil {
            return nil, err
        }
        all = append(all, part...)
    }
    out := make([]Holiday, 0)
    fromDay := from.Format("2006-01-02")
    toDay := to.Format("2006-01-02")
    for _, h := range all {
        if h.Date >= fromDay && h.Date <= toDay {
            out = append(out, h)
        }
    }
    return out, nil
}
 