import 'package:dio/dio.dart';

import '../api/api_exception.dart';
import 'auth_api.dart';
import 'token_store.dart';

/// DEV ONLY: sends a fixed token from `--dart-define=DEV_ACCESS_TOKEN` and never refreshes it, so
/// the app can run locally without Meta credentials (see AppConfig.devAccessToken). An expired
/// token surfaces as an ordinary 401 error. Used only when the define is set.
class DevTokenInterceptor extends Interceptor {
  DevTokenInterceptor(this._token);

  final String _token;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer $_token';
    handler.next(options);
  }
}

/// The refresh call's outcome when it gives no new token.
sealed class _NoToken {
  const _NoToken();
}

/// There is no session (no refresh token), or the server really refused it (401).
class _SignedOut extends _NoToken {
  const _SignedOut();
}

/// The refresh call failed some other way: offline, timed out, or a server error. The session may
/// be fine, so nothing is cleared and the merchant stays signed in.
class _RefreshFailed extends _NoToken {
  const _RefreshFailed(this.error);

  final ApiException error;
}

/// Adds the access token to every request and refreshes it when it has expired.
///
/// A [QueuedInterceptor] handles one request at a time, so a burst of requests after the
/// token expires triggers a single refresh, not one per request.
///
/// Only a real 401 from `POST /auth/refresh` ends the session. A network failure stays a network
/// failure ("Can't reach sellix"), so a phone on patchy mobile data is never signed out by it.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this._dio,
    required this._tokens,
    required this._authApi,
    required this._onSessionExpired,
  });

  static const _retried = 'sellix.retried';

  final Dio _dio;
  final TokenStore _tokens;
  final AuthApi _authApi;
  final void Function() _onSessionExpired;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final valid = await _tokens.validAccessToken();
    if (valid != null) {
      options.headers['Authorization'] = 'Bearer $valid';
      handler.next(options);
      return;
    }
    switch (await _refresh()) {
      case final String token:
        options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      case _SignedOut():
        handler.reject(_signedOut(options), true);
      case _RefreshFailed(:final error):
        handler.reject(_failed(options, error), true);
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retried] == true) {
      handler.next(err);
      return;
    }
    // The server refused the token (revoked or rotated elsewhere): refresh once and retry.
    switch (await _refresh()) {
      case final String token:
        options.extra[_retried] = true;
        options.headers['Authorization'] = 'Bearer $token';
        try {
          handler.resolve(await _dio.fetch<Object?>(options));
        } on DioException catch (retryError) {
          handler.next(retryError);
        }
      case _SignedOut():
        handler.next(err);
      case _RefreshFailed(:final error):
        handler.next(_failed(options, error));
    }
  }

  /// A new access token, or why there is none.
  Future<Object> _refresh() async {
    final refreshToken = await _tokens.refreshToken();
    if (refreshToken == null) return const _SignedOut();
    try {
      final pair = await _authApi.refresh(refreshToken);
      await _tokens.save(pair);
      return pair.accessToken;
    } on ApiException catch (error) {
      if (!error.isUnauthorized) return _RefreshFailed(error);
      await _tokens.clear();
      _onSessionExpired();
      return const _SignedOut();
    }
  }

  DioException _signedOut(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 401,
          data: const {'detail': 'Please sign in again.'},
        ),
      );

  /// Carries the refresh call's own failure, so the screen shows its words, e.g. "Can't reach
  /// sellix. Check your connection." (see ApiException.from).
  DioException _failed(RequestOptions options, ApiException error) => DioException(
        requestOptions: options,
        type: error.statusCode == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
        error: error,
        message: error.message,
      );
}
