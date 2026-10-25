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

/// Whether the merchant is signed in, and "Continue with Instagram".
class AuthController extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    final refreshToken = await ref.read(tokenStoreProvider).refreshToken();
    return refreshToken == null ? AuthStatus.signedOut : AuthStatus.signedIn;
  }

  /// Opens Instagram's login, then trades the returned one-time code (with PKCE) for a session.
  Future<void> signInWithInstagram() async {
    final pkce = Pkce.generate();
    final authApi = ref.read(authApiProvider);
    final url = await authApi.startInstagramLogin(
      codeChallenge: pkce.challenge,
      redirectUri: AppConfig.authRedirectUri,
    );

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
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
    state = const AsyncData(AuthStatus.signedIn);
  }

  Future<void> signOut() async {
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
