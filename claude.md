# Believers Palace — agent notes

## Catechism (migration 0018)

End-to-end faith-formation feature:

- **Backend:** `internal/catechism/` (class, enrollment, session). Mounted under `/api/churches/{churchId}/catechism-classes`, `/api/catechism-classes`, `/api/catechism-enrollments`, `/api/catechism-sessions`.
- **Auth:** Same pastoral rule as announcements/events — `auth.CanManageChurchContent`.
- **Flutter:** `frontend/lib/features/catechism/` — bottom nav **Catechism** tab and church detail pill tab.
- **Seed:** `seeds/dev_seed.sql` adds sample church `…0010`, class `…0020`, enrollment `…0021`.

Run `make test` (Go) and `flutter analyze` in `frontend/` after changes.