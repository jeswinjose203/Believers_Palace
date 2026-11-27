# Believers Palace — HTTP interfaces

Base path: `/api` (JWT required except `/auth/*` and public `GET /media/{key}`).

## Catechism

| Method | Path | Description |
|--------|------|-------------|
| GET | `/churches/{churchId}/catechism-classes` | Paginated class list (`search`, `status`, `level`) |
| POST | `/churches/{churchId}/catechism-classes` | Create class (staff) |
| GET | `/catechism-classes/{classId}` | Class detail + seats / enrolled flag |
| PUT | `/catechism-classes/{classId}` | Update class (staff) |
| DELETE | `/catechism-classes/{classId}` | Delete class (staff) |
| GET | `/catechism-classes/{classId}/enrollments` | List enrollments (staff all, user own) |
| POST | `/catechism-classes/{classId}/enrollments` | Create enrollment |
| GET | `/catechism-enrollments` | Current user's enrollments |
| PATCH | `/catechism-enrollments/{id}/status` | Approve / reject / complete (staff) |
| PATCH | `/catechism-enrollments/{id}/withdraw` | Withdraw (owner or staff) |
| GET | `/catechism-classes/{classId}/sessions` | List lessons (approved guardian or staff) |
| POST | `/catechism-classes/{classId}/sessions` | Create lesson (staff) |
| PUT | `/catechism-sessions/{sessionId}` | Update lesson (staff) |
| DELETE | `/catechism-sessions/{sessionId}` | Delete lesson (staff) |

List responses use `{ "data": [...], "pagination": { "page", "limit", "total", "totalPages" } }`.

See [README.md](README.md) for roles, conflict rules, and curl examples.