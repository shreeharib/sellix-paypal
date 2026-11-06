import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../api/api_exception.dart';
import '../config.dart';
import '../providers.dart';
import 'pkce.dart';

enum AuthStatus { signedIn, signedOut }

/// Thrown when the merchant cancels the Instagram login.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Opens [url] in the system's sign-in browser and returns the URL it was redirected to once it
/// reaches [callbackUrlScheme]. Throws a [PlatformException] coded `CANCELED` when closed.
typedef WebAuthenticate = Future<String> Function({required String url, required String callbackUrlScheme});

/// The browser login. Tests replace it so the real flow runs without a browser.
final webAuthenticateProvider = Provider<WebAuthenticate>((ref) => FlutterWebAuth2.authenticate);

/// DEV ONLY: true while requests carry AppConfig.devAccessToken. A real Instagram sign-in ends it,
/// so the session it creates is the one the app uses from then on. Always false without the define.
class DevSignIn extends Notifier<bool> {
  @override
  bool build() => AppConfig.usesDevSignIn;

  void end() => state = false;
}

final devSignInProvider = NotifierProvider<DevSignIn, bool>(DevSignIn.new);

/// Whether the merchant is signed in, and "Continue with Instagram".
class AuthController extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    // DEV ONLY: see AppConfig.devAccessToken. Inert when the define is empty.
    if (ref.read(devSignInProvider)) return AuthStatus.signedIn;

    final refreshToken = await ref.read(tokenStoreProvider).refreshToken();
    return refreshToken == null ? AuthStatus.signedOut : AuthStatus.signedIn;
  }

  /// Opens Instagram's login, then trades the returned one-time code (with PKCE) for a session.
  ///
  /// This is also how a signed-in shop connects or reconnects Instagram: the API has no separate
  /// "connect to this shop" endpoint, and it signs the same Instagram account into the same shop.
  Future<void> signInWithInstagram() async {
    final pkce = Pkce.generate();
    final authApi = ref.read(authApiProvider);
    final url = await authApi.startInstagramLogin(
      codeChallenge: pkce.challenge,
      redirectUri: AppConfig.authRedirectUri,
    );

    final String result;
    try {
      result = await ref.read(webAuthenticateProvider)(
        url: url,
        callbackUrlScheme: AppConfig.authCallbackScheme,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') throw const SignInCancelled();
      rethrow;
    }

    final query = Uri.parse(result).queryParameters;
    final error = query['error'];
    if (error != null) throw ApiException(error);
    final code = query['code'];
    if (code == null) throw const ApiException('Instagram sent no login code. Please try again.');

    final pair = await authApi.exchangeCode(code: code, codeVerifier: pkce.verifier);
    await ref.read(tokenStoreProvider).save(pair);
    // DEV ONLY: from here on the API client sends this session, not the command-line token.
    ref.read(devSignInProvider.notifier).end();
    state = const AsyncData(AuthStatus.signedIn);
  }

  Future<void> signOut() async {
    // DEV ONLY: the token came from the command line and stays valid until it expires, so don't
    // revoke it; signing out lasts until the app restarts.
    if (ref.read(devSignInProvider)) {
      state = const AsyncData(AuthStatus.signedOut);
      return;
    }
    try {
      await ref.read(sellixApiProvider).logout();
    } on ApiException {
      // Already invalid on the server: signing out locally is all that's left.
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(AuthStatus.signedOut);
  }

  /// Called when the server rejects the refresh token (expired, revoked, or reused).
  void sessionExpired() => state = const AsyncData(AuthStatus.signedOut);
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthStatus>(AuthController.new);
