/// Build-time configuration, set with `--dart-define`.
abstract final class Env {
  /// The `/api/v1` root the app talks to.
  ///
  /// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8082/api/v1` (Android emulator)
  /// or `http://localhost:8082/api/v1` (iOS simulator) for the local stack.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dinewise.riztechacademy.com/api/v1',
  );
}
