// Default API base URL. Override at build/run time with
//   --dart-define=API_BASE_URL=http://localhost:8080/api
// (use localhost with `adb reverse tcp:8080 tcp:8080` or on desktop/web).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.1.11:8080/api',
);
