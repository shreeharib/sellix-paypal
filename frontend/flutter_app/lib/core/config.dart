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

  /// DEV ONLY: runs the app locally without Meta credentials.
  ///
  ///     cd backend && just cli issue-token --merchant-id <id>
  ///     flutter run --dart-define=DEV_ACCESS_TOKEN=<token>
  ///
  /// With the define set, the app counts as signed in and sends this token on every request,
  /// with no refresh; when it expires, issue a new one. "Connect Instagram" (onboarding, Channels)
  /// still runs the real Instagram login, and once it succeeds that session replaces this token
  /// until the app restarts (see devSignInProvider). Without the define this is empty and
  /// nothing changes: normal Instagram sign-in applies. Release builds ignore the define, so a
  /// token passed by mistake can't sign a shipped app in.
  static String get devAccessToken => kReleaseMode ? '' : _devAccessToken;

  static const _devAccessToken = String.fromEnvironment('DEV_ACCESS_TOKEN');

  /// Whether the DEV ONLY sign-in above is in use.
  static bool get usesDevSignIn => devAccessToken.isNotEmpty;
}
