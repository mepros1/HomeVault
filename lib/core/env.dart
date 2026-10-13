/// Build-time configuration, injected with `--dart-define` (see CLAUDE.md).
/// Nothing here is secret.
abstract final class Env {
  /// Base URL of the HomeVault server, e.g. `https://api.example.com`.
  /// From the Android emulator the host machine is `http://10.0.2.2:8080`.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// RevenueCat public SDK key for Google Play. Empty = purchases disabled.
  static const String revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

  /// Shown on the paywall and in settings (spec section 8).
  static const String privacyPolicyUrl =
      String.fromEnvironment('PRIVACY_POLICY_URL', defaultValue: 'https://homevault.app/privacy');

  /// Google Cloud project NUMBER linked to the Play app; enables Play
  /// Integrity tokens on `POST /v1/devices` and `/v1/analyze-room`.
  /// Empty or 0 = no `X-App-Check` header.
  static const int playIntegrityProjectNumber =
      int.fromEnvironment('PLAY_INTEGRITY_PROJECT_NUMBER', defaultValue: 0);

  static bool get isApiConfigured => apiBaseUrl.isNotEmpty;

  static Uri get analyzeRoomEndpoint => Uri.parse('$apiBaseUrl/v1/analyze-room');

  static Uri get registerDeviceEndpoint => Uri.parse('$apiBaseUrl/v1/devices');

  static Uri get reviewStatsEndpoint => Uri.parse('$apiBaseUrl/v1/stats/review');

  static Uri get backupsEndpoint => Uri.parse('$apiBaseUrl/v1/backups');
}
