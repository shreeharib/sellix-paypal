import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/sellix_api.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_interceptor.dart';
import 'auth/token_store.dart';
import 'config.dart';

BaseOptions _options() => BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    );

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(const FlutterSecureStorage()));

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(Dio(_options())));

final sellixApiProvider = Provider<SellixApi>((ref) {
  final dio = Dio(_options());
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      tokens: ref.watch(tokenStoreProvider),
      authApi: ref.watch(authApiProvider),
      onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
    ),
  );
  return HttpSellixApi(dio);
});
