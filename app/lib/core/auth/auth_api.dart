import 'package:dio/dio.dart';

import '../api/api_exception.dart';
import '../api/models.dart';

/// The sign-in endpoints. They don't need an access token, so they use their own client.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// Returns the Instagram URL to open in a browser.
  Future<String> startInstagramLogin({required String codeChallenge, required String redirectUri}) async {
    final data = await _post('/v1/auth/instagram/start', {
      'code_challenge': codeChallenge,
      'redirect_uri': redirectUri,
    });
    return data['authorize_url'] as String;
  }

  Future<TokenPair> exchangeCode({required String code, required String codeVerifier}) async =>
      TokenPair.fromJson(await _post('/v1/auth/token', {'code': code, 'code_verifier': codeVerifier}));

  Future<TokenPair> refresh(String refreshToken) async =>
      TokenPair.fromJson(await _post('/v1/auth/refresh', {'refresh_token': refreshToken}));

  Future<Map<String, dynamic>> _post(String path, Map<String, Object> body) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return response.data ?? const {};
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
