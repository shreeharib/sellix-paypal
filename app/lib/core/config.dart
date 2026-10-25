import 'package:flutter/foundation.dart';

/// Build-time configuration, passed with `--dart-define`.
abstract final class AppConfig {
  /// Base URL of the sellix API.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// The mobile deep link "Continue with Instagram" returns to. It must be listed in the
  /// API's APP_REDIRECT_URIS.
  static const mobileAuthRedirectUri = String.fromEnvironment(
    'AUTH_REDIRECT_URI',
    defaultValue: 'sellix://auth/callback',
  );

  static const authCallbackScheme = 'sellix';

  /// On the web, Instagram returns to `auth.html` on the app's own origin.
  static String get authRedirectUri =>
      kIsWeb ? '${Uri.base.origin}/auth.html' : mobileAuthRedirectUri;
}
