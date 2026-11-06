# Believers Palace

A church/community management REST API built with Go and PostgreSQL. It
implements the Church Management API specification (v1.6.0): authentication,
users, churches, announcements, halls, bookings, events, cemetery services, and
per-user certificate storage.

## Tech Stack

| Concern     | Choice                        |
|-------------|-------------------------------|
| Language    | Go 1.24                       |
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
│   ├── cemetery/           # cemetery plots + service requests
│   ├── certificate/        # per-user PDF certificate storage
│   └── server/             # router + middleware wiring
├── migrations/             # SQL migrations (0001..0008)
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
  They may manage pastoral **content** — announcements and events — for their
  church. They do NOT have administrative powers (hall CRUD, booking status
  changes, cemetery plots, cemetery request status, user role changes remain
  `church_admin` / `super_admin` only).
- Regular users may create bookings and cemetery service requests, register for
  events, and manage their own profile and certificates. They see only their
  own bookings, service requests, and certificates.

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

The API is then available at http://localhost:8080.

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
| `PUBLIC_BASE_URL`  | `http://localhost:8080`    | External base URL for links in emails  |
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
title/content; halls and events by name/description/location; bookings by
purpose/notes; cemetery plots by number/section/location; cemetery service
requests by name/deceased/description).

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

New users receive an email verification token on registration. Verification is
"soft": accounts are usable immediately and `emailVerified` becomes true once
the user calls `/auth/verify-email` with their token (`/auth/resend-verification`
re-issues one).

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
| POST   | `/events/{eventId}/register`              |
| GET    | `/events/{eventId}/registrations`         |
| GET/POST | `/events/{eventId}/messages`            |
| DELETE | `/events/{eventId}/messages/{messageId}`  |

Create/update/delete of these resources require the owning church_admin or
super_admin.

**Event chat:** every event has a chat (`GET /events/{eventId}/messages`,
paginated, oldest-first; `POST /events/{eventId}/messages` with `{content}`).
If the event has `registrationRequired: true`, only users who registered
(`POST /events/{eventId}/register`) and church staff of the owning church (plus
super_admin) may read and post; anyone else gets `403` with code
`not_registered`. If `registrationRequired` is false, any authenticated user may
chat and registration is not offered in the app. Admins can see the attendee
list and count via `GET /events/{eventId}/registrations` (`pagination.total`).
A message may be deleted by its author, or by the owning church_admin /
super_admin (`DELETE /events/{eventId}/messages/{messageId}`). The author's name and photo
are snapshotted when the message is posted. The Flutter client refreshes the
chat by polling.

### Bookings
| Method | Path                               | Access                         |
|--------|------------------------------------|--------------------------------|
| GET    | `/churches/{churchId}/bookings`    | admins see all; users see own  |
| GET    | `/bookings`                        | current user's bookings        |
| POST   | `/churches/{churchId}/bookings`    | any authenticated              |
| GET    | `/bookings/{bookingId}`            | owner / church admin           |
| PATCH  | `/bookings/{bookingId}/status`     | church_admin / super_admin     |
| PATCH  | `/bookings/{bookingId}/cancel`     | owner / church admin           |

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

## Testing

```bash
make test        # go test ./...
```

Unit tests cover authorization helpers, validation, enum validity, JSONB array
encoding, and certificate file storage (including path-traversal protection).



& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080

& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse --list