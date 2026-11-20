# Believers Palace

A church/community management REST API built with Go and PostgreSQL. It
implements the Church Management API specification (v1.6.0): authentication,
users, churches, announcements, halls, bookings, events, catechism (faith
formation classes), cemetery services, and per-user certificate storage.

## Tech Stack

| Concern     | Choice                        |
|-------------|-------------------------------|
| Language    | Go 1.25 minimum, Go 1.27.4 in Docker |
| Router      | chi/v5                        |
| Database    | PostgreSQL (pgx/v5 pool)      |
| Auth        | JWT (golang-jwt/v5) + bcrypt  |
| Migrations  | golang-migrate (SQL files)    |
| Config      | godotenv + env vars           |
| File storage| Local filesystem (PDF uploads)|

## Project Layout

```
believers_palace/
├── cmd/api/                # application entrypoint
├── internal/
│   ├── config/             # env configuration
│   ├── database/           # pgx connection pool
│   ├── httpx/              # shared JSON HTTP helpers, pagination
│   ├── auth/               # roles, JWT, bcrypt, middleware
│   ├── user/               # auth + user management
│   ├── church/             # church CRUD
│   ├── announcement/       # church announcements
│   ├── hall/               # bookable halls
│   ├── booking/            # hall bookings + lifecycle
│   ├── event/              # events + registrations
│   ├── catechism/          # faith-formation classes, enrollments, lessons
│   ├── personalcalendar/   # per-user calendar, tasks, goals, schedule
│   ├── cemetery/           # cemetery plots + service requests
│   ├── certificate/        # per-user PDF certificate storage
│   ├── marketplace/        # community ads + shop catalog
│   └── server/             # router + middleware wiring
├── migrations/             # SQL migrations (0001..0027)
├── .env.example
├── Makefile
└── go.mod
```

Each domain package follows the same layering: a model file, a `repository.go`
(SQL access), a `service.go` (business logic + authorization), and a
`handler.go` (HTTP). Nested JSON (priest details, hall arrays) is stored as
JSONB; list endpoints return a `{data, pagination}` envelope.

## Roles & Authorization

Five roles: `user`, `priest`, `associate_priest`, `church_admin`, `super_admin`.

- `super_admin` may perform any action.
- `church_admin` is scoped to their own church (enforced in both routing and
  the service layer): full administrative control of that church's resources.
- `priest` and `associate_priest` are church staff scoped to their own church.
  They may manage pastoral **content** — announcements, events, and catechism
  classes — for their church. They do NOT have administrative powers (hall CRUD, booking status
  changes, cemetery plots, cemetery request status, user role changes remain
  `church_admin` / `super_admin` only).
- Regular users may create bookings and cemetery service requests, register for
  events, enroll students in open catechism classes, and manage their own profile
  and certificates. They see only their own bookings, service requests,
  catechism enrollments, and certificates.

Booking integrity: a hall cannot be double-booked for overlapping time ranges.
Overlaps with active (`pending`/`approved`) bookings are rejected with `409`,
enforced both in the service layer and by a database exclusion constraint.

## Running with Docker (recommended)

The compose stack runs `db` (PostgreSQL), `migrate` (applies migrations then
exits), and `api`. Migrations run automatically before the API starts.

```bash
cp .env.example .env      # optional: override defaults
make docker-up            # build + start everything
make docker-logs          # tail API logs
make docker-down          # stop and remove containers
```

The API is then available at http://localhost:8080 (or http://localhost:8080
from other devices on the same network).

## Getting Started (local, without Docker)

1. Copy the environment file and adjust values:
   ```bash
   cp .env.example .env
   ```
2. Create the database:
   ```bash
   make db-create
   ```
3. Run migrations (requires [golang-migrate](https://github.com/golang-migrate/migrate)):
   ```bash
   make migrate-up
   ```
4. Run the server:
   ```bash
   make run
   ```

## Configuration

Key environment variables (see `.env.example` for the full list):

| Variable           | Default                    | Notes                                  |
|--------------------|----------------------------|----------------------------------------|
| `HTTP_PORT`        | `8080`                     | API listen port                        |
| `JWT_SECRET`       | (dev default)              | **Required in production**             |
| `ACCESS_TOKEN_TTL` | `15m`                      | Access-token lifetime (`JWT_TTL` is accepted as a fallback) |
| `REFRESH_TOKEN_TTL`| `720h` (30 days)           | Refresh-token lifetime                 |
| `RESET_TOKEN_TTL`  | `1h`                       | Password-reset-token lifetime          |
| `CORS_ALLOWED_ORIGINS` | `*` (dev only)         | Comma-separated allowed origins; **required in production** |
| `RATE_LIMIT_ENABLED` / `RATE_LIMIT_GENERAL_PER_MIN` / `RATE_LIMIT_AUTH_PER_MIN` | `true` / `120` / `10` | Per-IP rate limits (auth endpoints stricter); auto-disabled under `SKIP_JWT_VALIDATION` |
| `LOG_LEVEL`        | `info`                     | `debug`/`info`/`warn`/`error`; JSON output in production |
| `PUBLIC_BASE_URL`  | `http://localhost:8080` | External base URL for links in emails and uploaded-image URLs |
| `STORAGE_DIR`      | `./storage/certificates`   | Where uploaded PDFs are stored         |
| `MAX_UPLOAD_BYTES` | `10485760` (10 MiB)        | Max certificate file size              |
| `MEDIA_DIR`        | `./storage/media`          | Where uploaded images are stored       |
| `MAX_IMAGE_BYTES`  | `5242880` (5 MiB)          | Max image upload size                  |
| `MAIL_PROVIDER`    | `log`                      | `log` (console) or `smtp` (real email) |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `MAIL_FROM` | — | Required when `MAIL_PROVIDER=smtp` (e.g. Gmail: host `smtp.gmail.com`, port `587`, a 16-char App Password) |

## API Overview

Base path: `/api`. All routes except `/auth/*` require a
`Authorization: Bearer <JWT>` header.

> **Local testing shortcut:** set `SKIP_JWT_VALIDATION=true` (development only;
> refused when `APP_ENV=production`) to bypass JWT auth entirely. Requests then
> run as a synthetic `super_admin`. Override the identity per request with the
> headers `X-Debug-User-Id`, `X-Debug-Role`, and `X-Debug-Church-Id`. This makes
> it easy to exercise the API from Postman without logging in.
>
> The default debug identity uses a fixed user ID that has no row in the
> database until you seed it. Run the development seed once so that
> foreign-key-bound operations (bookings, service requests, certificates,
> registrations) succeed:
>
> ```bash
> make seed          # local Postgres
> make docker-seed   # Docker Postgres container
> ```
>
> You can also log in as this user: `debug@example.com` / `password`.

List endpoints accept `page`/`limit` pagination and a `search` query parameter
for case-insensitive text matching (churches by name/address; announcements by
title/content; halls and events by name/description/location; catechism classes by
name/description and sessions by title/topic; enrollments by student name;
bookings by purpose/notes; cemetery plots by number/section/location; cemetery
service requests by name/deceased/description).

### Authentication
| Method | Path                     | Description                                   |
|--------|--------------------------|-----------------------------------------------|
| POST   | `/auth/register`         | Register a user                               |
| POST   | `/auth/login`            | Log in                                        |
| POST   | `/auth/refresh`          | Exchange a refresh token for a new token pair |
| POST   | `/auth/logout`           | Revoke a single refresh token                 |
| POST   | `/auth/forgot-password`  | Request a password reset (always 200)         |
| POST   | `/auth/reset-password`   | Set a new password using a reset token        |
| POST   | `/auth/verify-email`     | Verify an email address using a token         |
| POST   | `/auth/resend-verification` | Re-send a verification token (always 200)  |
| POST   | `/users/logout-all`      | Revoke all refresh tokens (authenticated)     |

Register/login/refresh return `{accessToken, refreshToken, expiresIn, user}`.
`token` is still returned as a deprecated alias of `accessToken`. The access
token is a short-lived JWT; the refresh token is an opaque, server-stored
(SHA-256 hashed), revocable credential. `/auth/refresh` rotates the refresh
token (the old one is revoked). A password reset revokes all of the user's
refresh tokens.

Password reset delivery uses a pluggable `Mailer`. The default development
implementation (`MAIL_PROVIDER=log`) logs the reset/verification token to the
server log; set `MAIL_PROVIDER=smtp` with the `SMTP_*`/`MAIL_FROM` vars to send
real email (e.g. via Gmail).

New users receive a six-digit email verification code on registration. In Profile,
tap the email address to request or enter a code. The verified icon appears after
confirmation. Codes expire after 10 minutes or five failed attempts, and a new
code can be issued once per minute. The app passes the email and code (as
`token`) to `/auth/verify-email`.

### Users
| Method | Path                   | Access                         |
|--------|------------------------|--------------------------------|
| GET    | `/users`               | church_admin / super_admin     |
| GET    | `/users/stats`         | church_admin / super_admin     |
| GET    | `/users/me`            | current user                   |
| PUT    | `/users/me`            | current user                   |
| PATCH  | `/users/{userId}/role` | super_admin                    |

### Churches
| Method | Path                  | Access                                  |
|--------|-----------------------|-----------------------------------------|
| GET    | `/churches`           | any authenticated                       |
| POST   | `/churches`           | super_admin                             |
| GET    | `/churches/{id}`      | any authenticated                       |
| PUT    | `/churches/{id}`      | owning church_admin / super_admin       |
| DELETE | `/churches/{id}`      | super_admin                             |

Church records include a `description`, a `logo`, a multi-image gallery
`images[]` (URLs from `POST /media/upload`), and `priest` / `associatePriest`
details (name, phone, email, profilePic). List items return `id`, `name`,
`description`, `address`, `logo` and `images`; `search` also matches the
description. Migration `0013` adds the `description` and `images` columns.

### Announcements, Halls, Events (per church)
| Method | Path                                      |
|--------|-------------------------------------------|
| GET/POST | `/churches/{churchId}/announcements`    |
| PUT/DELETE | `/announcements/{announcementId}`     |
| GET/POST | `/churches/{churchId}/halls`            |
| GET/PUT/DELETE | `/halls/{hallId}`                 |
| GET/POST | `/churches/{churchId}/events`           |
| GET/PUT/DELETE | `/events/{eventId}`               |
| POST/DELETE | `/events/{eventId}/register`         |
| GET    | `/events/{eventId}/registrations`         |
| GET/POST | `/events/{eventId}/messages`            |
| DELETE | `/events/{eventId}/messages/{messageId}`  |

Create/update/delete of these resources require the owning church_admin or
super_admin.

**Event chat:** every event has a chat (`GET /events/{eventId}/messages`,
paginated, oldest-first; `POST /events/{eventId}/messages` with `{content}`).
Reading, posting, and deleting messages in event and community chats requires
a verified email. The API returns `403 email_verification_required` for
unverified accounts.
If the event has `registrationRequired: true`, only users who registered
(`POST /events/{eventId}/register`) and church staff of the owning church (plus
super_admin) may read and post; anyone else gets `403` with code
`not_registered`. If `registrationRequired` is false, any verified user may
chat and registration is not offered in the app. Admins can see the attendee
list and count via `GET /events/{eventId}/registrations` (`pagination.total`).
Users can cancel their own registration with `DELETE /events/{eventId}/register`
(204, or 404 if not registered); event list items include `registered` for the
caller.
A message may be deleted by its author, or by the owning church_admin /
super_admin (`DELETE /events/{eventId}/messages/{messageId}`). The author's name and photo
are snapshotted when the message is posted. The Flutter client refreshes the
chat through one WebSocket per foreground session. The client requests a
single-use ticket at `POST /api/chat/live-ticket` and uses it to connect to
`/api/chat/live`. Room subscriptions follow the chat access rules. Live
signals trigger cursor-based reads to catch up, and HTTP polling remains a
fallback when the socket is unavailable. Migration `0023` adds persistent
message cursors and optional `clientId` keys for safe send retries.

Migrations `0024` and `0025` add shared one-time tickets, account-level mute
preferences, and the push delivery queue. Each API replica uses a dedicated
PostgreSQL `LISTEN` connection for committed chat changes. If that connection
fails, the affected replica closes its sockets so clients reconnect and
catch up from PostgreSQL. Route both chat endpoints through a proxy that
supports WebSocket upgrades. Use a direct or session-mode PostgreSQL
connection for `LISTEN`, since transaction-mode pooling discards session
state. Apply migrations before starting the new API replicas.

### Background chat notifications

Set `FCM_PROJECT_ID` on the API and provide Firebase Application Default
Credentials with permission to send messages for that project. In Docker,
mount a read-only credential file through a deployment override and set
`GOOGLE_APPLICATION_CREDENTIALS` to its container path, or use workload
identity. Keep credential files outside the repository and build context.
Register the Android and iOS apps with the same Firebase project. Follow the
frontend README for build settings and Apple push setup. The server queues
one delivery per eligible device and checks current membership, mute settings
and device ownership before sending. Push alerts contain a generic preview.

### Capacity and rollout

- Set a connection budget before scaling replicas. Each API process uses
  up to `DB_MAX_CONNS` pooled connections plus one chat listener. Set
  `TRUST_PROXY_HEADERS=true` only behind a proxy that overwrites `X-Real-IP`
  with the client address and prevents direct access to the API. Configure any
  shared rate limits at that proxy. The built-in limits are per replica.
- The optional `TestDistributedChat` integration test uses disposable
  PostgreSQL, two listeners and a simulated push provider. Set
  `CHAT_TEST_DATABASE_URL` and optionally `CHAT_TEST_CONNECTIONS`, then run
  `go test -v ./internal/chatlive -run TestDistributedChat -count=1`.
  It checks cross-replica ticket use, fan-out latency, and mute enforcement.
- Before production rollout, measure message send latency, socket fan-out,
  reconnection storms, database pool waits, and push queue age with a
  representative dataset and traffic mix. Run these through the production-like
  proxy and test an API restart, database listener interruption, and FCM throttling.

The app uses cursor pagination for the All and Joined community lists. API
clients can pass `limit`, `joined`, and the returned `nextCursor` as `cursor`.
The original request without pagination parameters remains available to older
clients.

The server caps concurrent HTTP requests and live connections separately using
`HTTP_MAX_IN_FLIGHT` and `CHAT_MAX_CONNECTIONS`. Excess requests return 503 with
`Retry-After: 1`. Tune both limits against the database and proxy capacities.

The optional `TestMixedAPILoad` test exercises the authenticated HTTP router on a
migrated disposable database with a 10,000-community catalog. Set
`API_LOAD_DATABASE_URL` and optionally `API_LOAD_CONCURRENCY` and
`API_LOAD_REQUESTS`, then run
`go test -v ./internal/server -run TestMixedAPILoad -count=1`.
One isolated Docker run completed 60,000 authenticated requests with
64 concurrent workers and a 10-connection database pool. It observed zero
failures, 1,274 requests/s, 92 ms p95, and 123 ms p99. This workload uses a
local database and disables per-IP throttling.

Several public list queries,
including churches, events, and marketplace listings, use offset pagination and
substring search. Use staging query plans on representative data to prioritize
cursor pagination and search indexes. Media and certificate storage are
filesystem-backed. Deploy shared storage before spreading uploads across hosts.

### Bookings
| Method | Path                               | Access                         |
|--------|------------------------------------|--------------------------------|
| GET    | `/churches/{churchId}/bookings`    | admins see all; users see own  |
| GET    | `/bookings`                        | current user's bookings        |
| POST   | `/churches/{churchId}/bookings`    | any authenticated              |
| GET    | `/bookings/{bookingId}`            | owner / church admin           |
| PATCH  | `/bookings/{bookingId}/status`     | church_admin / super_admin     |
| PATCH  | `/bookings/{bookingId}/cancel`     | owner / church admin           |

### Catechism
| Method | Path | Access |
|--------|------|--------|
| GET/POST | `/churches/{churchId}/catechism-classes` | list: any authenticated; create: church staff / super_admin |
| GET/PUT/DELETE | `/catechism-classes/{classId}` | get: any authenticated; write: church staff / super_admin |
| GET/POST | `/catechism-classes/{classId}/enrollments` | list: staff see all, users see own; create: any authenticated |
| GET | `/catechism-enrollments` | current user's enrollments |
| PATCH | `/catechism-enrollments/{id}/status` | church staff / super_admin (approve / reject / complete) |
| PATCH | `/catechism-enrollments/{id}/withdraw` | owner or church staff |
| GET/POST | `/catechism-classes/{classId}/sessions` | list: approved guardian or staff; create: staff |
| PUT/DELETE | `/catechism-sessions/{sessionId}` | church staff / super_admin |

Church staff (`church_admin`, `priest`, `associate_priest`, `super_admin`) manage
catechism for their own church only. Users browse open classes, submit enrollments
for their children, and view or withdraw their own enrollments. Enrollment statuses
flow `pending` → `approved` / `rejected` / `withdrawn`, and staff may mark
`completed` after the class status is `completed`. Capacity and duplicate active
enrollments (same student name + date of birth in one class) are enforced in a
database transaction and return `409` when violated. Enrolling in a class that is
not `open` returns `400`.

Class list supports `status` and `level` filters in addition to `search`. List
items include `enrolledCount`, `availableSeats`, and `enrolled` (for the caller).

```bash
# Create a class (staff)
curl -X POST "http://localhost:8080/api/churches/$CHURCH_ID/catechism-classes" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"Confirmation 2026","level":"confirmation","startDate":"2026-09-01","endDate":"2027-04-30","capacity":30,"status":"open"}'

# Enroll a student
curl -X POST "http://localhost:8080/api/catechism-classes/$CLASS_ID/enrollments" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"studentName":"Maria Gomez","dateOfBirth":"2012-03-10"}'

# Approve enrollment (staff)
curl -X PATCH "http://localhost:8080/api/catechism-enrollments/$ENROLLMENT_ID/status" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"status":"approved"}'
```

The Flutter client adds a **Catechism** bottom-nav tab (when the user has a church)
and a **Catechism** pill tab on the church detail page (`frontend/lib/features/catechism/`).

### Cemetery
| Method | Path                                                | Access                        |
|--------|-----------------------------------------------------|-------------------------------|
| GET    | `/churches/{churchId}/cemetery-plots`               | any authenticated             |
| POST   | `/churches/{churchId}/cemetery-plots`               | church_admin / super_admin    |
| PUT    | `/cemetery-plots/{plotId}`                          | church_admin / super_admin    |
| DELETE | `/cemetery-plots/{plotId}`                          | church_admin / super_admin    |
| GET    | `/churches/{churchId}/cemetery-service-requests`    | admins see all; users see own |
| POST   | `/churches/{churchId}/cemetery-service-requests`    | any authenticated             |
| GET    | `/cemetery-service-requests/{requestId}`            | owner / church admin          |
| PATCH  | `/cemetery-service-requests/{requestId}/status`     | church_admin / super_admin    |

### Certificates
| Method | Path                                    | Access                                   |
|--------|-----------------------------------------|------------------------------------------|
| GET    | `/users/{userId}/certificates`          | self / managing admin                    |
| POST   | `/users/{userId}/certificates`          | self / managing admin (multipart PDF)    |
| GET    | `/certificates/{certificateId}/download`| self / managing admin                    |

Uploads are `multipart/form-data` with a `file` part (PDF) plus `type`,
`certificateNumber`, `fullName`, and optional `issueDate` (YYYY-MM-DD) and
`notes` fields. Files are validated for type and size, stored on disk under
`STORAGE_DIR`, and streamed back on download.

### Media (image uploads)
| Method | Path                | Access               |
|--------|---------------------|----------------------|
| POST   | `/media/upload`     | any authenticated    |
| GET    | `/media/{key}`      | public (no auth)     |

Image uploads back the photo fields on other resources (church `logo`, user
`profilePic`, event/announcement `image`, hall `images[]`). `POST /media/upload`
is `multipart/form-data` with a single `file` part; it accepts JPEG, PNG, WebP,
and GIF up to `MAX_IMAGE_BYTES` (default 5 MiB), stores the file under
`MEDIA_DIR` with path-traversal protection, and returns:

```json
{ "url": "http://localhost:8080/api/media/<key>", "fileName": "<key>", "mimeType": "image/png", "fileSize": 12345 }
```

Save the returned `url` into the relevant field via the normal create/update
endpoint. Images are served publicly at `GET /media/{key}` (no `Authorization`
header) so they load directly in `<img>`/`NetworkImage`. The returned URL is
built from `PUBLIC_BASE_URL`, so set that to your externally reachable base URL
in production.

### Marketplace (migration 0021)

Authenticated **Marketplace** for member-to-member sales and a separate **shop**
catalog. Community listings require admin approval before they appear in browse;
users manage their own ads. Admins manage categories (per `community` / `shop`
scope), moderate ads, and CRUD shop products.

| Method | Path | Access |
|--------|------|--------|
| GET | `/marketplace/categories?scope=community\|shop` | any authenticated |
| POST/PUT/DELETE | `/marketplace/categories[...]` | church_admin / super_admin |
| GET | `/marketplace/community-ads` | browse approved (+ sold) |
| GET/POST | `/marketplace/community-ads/mine`, `POST /marketplace/community-ads` | owner flows |
| GET | `/marketplace/community-ads/admin` | admin moderation queue |
| POST | `/marketplace/community-ads/{id}/approve\|reject\|sold` | admin or owner (sold) |
| GET | `/marketplace/shop/products` | active shop catalog |
| POST/PUT/DELETE | `/marketplace/shop/products[...]` | church_admin / super_admin |

See [interfaces.md](interfaces.md) for query parameters and payloads.

### Example

```bash
# Register and capture the token
TOKEN=$(curl -s -X POST http://localhost:8080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"Jane Doe","email":"jane@example.com","password":"supersecret"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

# Upload a certificate for yourself (USER_ID from /users/me)
curl -X POST "http://localhost:8080/api/users/$USER_ID/certificates" \
  -H "Authorization: Bearer $TOKEN" \
  -F 'file=@baptism.pdf;type=application/pdf' \
  -F 'type=baptism' \
  -F 'certificateNumber=BAP-001' \
  -F 'fullName=Jane Doe'
```
## Personal calendar (migrations 0017, 0020)
 
Authenticated users have a **per-user** private calendar at `/api/users/me/calendar/*`. Events, tasks, goals, check-ins, achievements, and preferences are stored with `user_id` and are never shared between accounts. The aggregated **schedule** also includes defaults only: public holidays (country from the user's preferences) and church platform events for the church selected on the user's profile (`users.church_id`, not the JWT claim). After logout or switching accounts, the Flutter app clears in-memory calendar state and local reminders.
 
Endpoints:
 
- Personal events (categories, colors, recurrence, local reminder metadata; edit/delete in app)
- `GET /users/me/calendar/events` — optional query: `search`, `category`, `fromDate`/`toDate` (`YYYY-MM-DD`), `upcomingDays`, `order` (`asc`|`desc`)
- Tasks with due **date and time** (`due_date` is `TIMESTAMPTZ`, default timezone `Asia/Kolkata`)
- Goals with daily check-ins and achievements (check in for the **selected calendar day**, not only “today”)
- `GET /users/me/calendar/schedule` — prefer query `fromDate` / `toDate` (`YYYY-MM-DD`, inclusive, user timezone) plus aggregated bookings, church events, holidays, and goal check-in markers
 
Apply migration **0020** (`calendar_tasks.due_date` → timestamptz, `user_calendar_preferences.timezone`).
 
Open **Calendar** from Profile. Local reminders use `flutter_local_notifications`
with event lead times and task due-time alerts. Run `flutter pub get` in
`frontend/` after pulling.

## Testing

```bash
make test        # go test ./...
```

Unit tests cover authorization helpers, validation, enum validity, JSONB array
encoding, and certificate file storage (including path-traversal protection).



& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080

& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse --list
