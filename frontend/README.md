# Believers Palace — Flutter Frontend

A Flutter mobile/web frontend for the Believers Palace church management API.

## Setup

1. Make sure Flutter is installed (`flutter --version` >= 3.24 / Dart ^3.5).
2. Set the API base URL, or use the default `http://localhost:8080/api`.
   To use `localhost` instead (desktop, web, or Android with
   `adb reverse tcp:8080 tcp:8080`):

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
- Incoming message alerts for joined communities and event chats a user
  has opened. The bell in each chat saves its mute setting to the account.

## Mobile chat push

For an Android or iOS build, supply the Firebase project values with
`--dart-define` for `FCM_PROJECT_ID`, `FCM_SENDER_ID`, `FCM_API_KEY`, and
`FCM_ANDROID_APP_ID` or `FCM_IOS_APP_ID` for the target platform. Use the API key
and Firebase app ID from the registered app's configuration. The API needs
FCM credentials for the same project. For a generated iOS project, set
`FirebaseMessagingInstallationIdEnabled` to `YES` and
`FirebaseMessagingAutoInitEnabled` to `NO` in `Runner/Info.plist`.
Enable Push Notifications and Remote notifications in Xcode and configure
the APNs key in Firebase.
Test on physical devices with the app foregrounded and backgrounded.
Foreground polling and live updates continue to work on builds without push
configuration.
- **Joined** tab in Communities lists memberships and groups you administer.
- **Marketplace** tab inside each church: community listings (search, categories, post/edit/delete,
  mark sold, contact seller) and official **shop** catalog; admins moderate
  pending ads and manage categories + shop products

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
