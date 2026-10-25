import 'package:dio/dio.dart';

import '../api/api_exception.dart';
import 'auth_api.dart';
import 'token_store.dart';

/// Adds the access token to every request and refreshes it when it has expired.
///
/// A [QueuedInterceptor] handles one request at a time, so a burst of requests after the
/// token expires triggers a single refresh, not one per request.
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
    final token = await _tokens.validAccessToken() ?? await _refresh();
    if (token == null) {
      handler.reject(_signedOut(options), true);
      return;
    }
    options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retried] == true) {
      handler.next(err);
      return;
    }
    // The server refused the token (revoked or rotated elsewhere): refresh once and retry.
    final token = await _refresh();
    if (token == null) {
      handler.next(err);
      return;
    }
    options.extra[_retried] = true;
    options.headers['Authorization'] = 'Bearer $token';
    try {
      handler.resolve(await _dio.fetch<Object?>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refresh() async {
    final refreshToken = await _tokens.refreshToken();
    if (refreshToken == null) return null;
    try {
      final pair = await _authApi.refresh(refreshToken);
      await _tokens.save(pair);
      return pair.accessToken;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _tokens.clear();
        _onSessionExpired();
      }
      return null;
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
}
