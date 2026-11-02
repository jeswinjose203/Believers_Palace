# Believers Palace — Flutter Frontend

A Flutter mobile/web frontend for the Believers Palace church management API.

## Setup

1. Make sure Flutter is installed (`flutter --version` >= 3.24 / Dart ^3.5).
2. Set the API base URL, or use the default `http://localhost:8080/api`:

   ```bash
   flutter run --dart-define=API_BASE_URL=http://localhost:8080/api
   ```

   Alternatively edit `lib/config.dart`.

3. Generate platform files and fetch dependencies:

   ```bash
   cd /home/jeswin/believers_palace/frontend
   flutter create .
   flutter pub get
   ```

4. Run the app:

   ```bash
   flutter run
   ```

## Features

- JWT login / registration (access token + refresh token)
- Forgot password / reset password
- Browse churches with search
- Church details with tabs for:
  - Announcements
  - Halls (book a hall)
  - Events (register for an event)
  - Cemetery plots
  - Cemetery service requests (submit new request)
- My bookings list and cancel
- My certificates list, download, and PDF upload
- Profile view and edit, plus "log out everywhere"

## Authentication

On login/registration the app stores the access token and refresh token.
If the access token has expired on startup, the app automatically refreshes it
using the stored refresh token. Logging out revokes the refresh token
server-side; "log out everywhere" (on the Profile screen) revokes all of the
user's sessions.

Password reset: from the login screen, tap "Forgot password?", enter your email,
then enter the reset token (delivered by email in production; printed to the API
server log in development) along with a new password.

## State management

Uses `flutter_riverpod` for dependency injection and app state.
The `ApiClient` in `lib/core/api_client.dart` handles JWT-bearing HTTP calls,
and `lib/services/api_service.dart` exposes all backend endpoints.
