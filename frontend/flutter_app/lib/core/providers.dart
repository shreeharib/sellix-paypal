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

/// Where requests really go. Null means Dio's own network adapter; tests put a fake server here to
/// check the exact requests the sign-in sends.
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

Dio _dio(Ref ref) {
  final dio = Dio(_options());
  final adapter = ref.watch(httpAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

/// On macOS the default data protection keychain needs a `keychain-access-groups` entitlement and
/// a signing team; without them every write fails (errSecMissingEntitlement) and the sandboxed app could never keep
/// a session. The login keychain works in the sandbox with no entitlement. Other platforms ignore it.
const secureStorage = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(secureStorage));

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(_dio(ref)));

/// The merchant API. Screens read it through this provider; tests override it with a fake.
final sellixApiProvider = Provider<SellixApi>((ref) {
  final dio = _dio(ref);
  dio.interceptors.add(
    ref.watch(devSignInProvider)
        // DEV ONLY: a fixed bearer token with no refresh, until a real Instagram sign-in replaces
        // it. See AppConfig.devAccessToken.
        ? DevTokenInterceptor(AppConfig.devAccessToken)
        : AuthInterceptor(
            dio: dio,
            tokens: ref.watch(tokenStoreProvider),
            authApi: ref.watch(authApiProvider),
            onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
          ),
  );
  return HttpSellixApi(dio);
});
