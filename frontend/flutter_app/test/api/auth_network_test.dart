import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/server_config.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How `POST /v1/auth/refresh` answers.
enum _Refresh { ok, offline, timeout, unauthorized, serverError }

/// The backend's auth routes plus `GET /v1/me`, with a switch for each way a refresh can go.
class _Server implements HttpClientAdapter {
  _Refresh refresh = _Refresh.ok;

  /// `GET /v1/me` refuses the token once, as after a rotation elsewhere.
  bool refuseOnce = false;
  final requests = <RequestOptions>[];

  List<String> get paths => [for (final r in requests) '${r.method} ${r.uri.host}${r.uri.path}'];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? _) async {
    requests.add(options);
    final route = '${options.method} ${options.path}';
    if (route == 'POST /v1/auth/refresh') {
      switch (refresh) {
        case _Refresh.offline:
          throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
        case _Refresh.timeout:
          throw DioException(requestOptions: options, type: DioExceptionType.receiveTimeout);
        case _Refresh.unauthorized:
          return _json(401, {'detail': 'Please sign in again.'});
        case _Refresh.serverError:
          return _json(503, {'detail': 'sellix is restarting. Try again in a minute.'});
        case _Refresh.ok:
          return _json(200, {'access_token': 'new', 'refresh_token': 'r2', 'expires_in': 900, 'token_type': 'bearer'});
      }
    }
    if (route == 'GET /v1/me') {
      if (refuseOnce) {
        refuseOnce = false;
        return _json(401, {'detail': 'Token expired'});
      }
      return _json(200, {
        'user_id': 'u1',
        'merchant': {'id': 'm1', 'name': 'Shop', 'timezone': 'Asia/Kolkata', 'agent_enabled': true},
        'role': 'owner',
        'channels': <Object>[],
        'onboarding_completed': true,
      });
    }
    if (route == 'POST /v1/auth/logout') return _json(204, null);
    return _json(404, {'detail': 'Not Found'});
  }

  ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _NoDev extends DevSignIn {
  @override
  bool build() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Signed in, with an access token that ran out a minute ago.
  void expiredSession() => FlutterSecureStorage.setMockInitialValues({
    'sellix.access_token': 'old',
    'sellix.refresh_token': 'r1',
    'sellix.access_expires_at': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
  });

  /// Signed in, with a fresh access token.
  void freshSession() => FlutterSecureStorage.setMockInitialValues({
    'sellix.access_token': 'old',
    'sellix.refresh_token': 'r1',
    'sellix.access_expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
  });

  Future<ProviderContainer> container(_Server server, {SharedPreferences? prefs}) async {
    final c = ProviderContainer(
      overrides: [
        httpAdapterProvider.overrideWithValue(server),
        devSignInProvider.overrideWith(_NoDev.new),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(c.dispose);
    expect(await c.read(authControllerProvider.future), AuthStatus.signedIn);
    return c;
  }

  group('a refresh that fails on the network keeps the merchant signed in', () {
    for (final (refresh, words) in [
      (_Refresh.offline, "Can't reach sellix. Check your connection."),
      (_Refresh.timeout, 'sellix took too long to answer. Please try again.'),
      (_Refresh.serverError, 'sellix is restarting. Try again in a minute.'),
    ]) {
      test('${refresh.name}: the error says so, and the session stays', () async {
        expiredSession();
        final server = _Server()..refresh = refresh;
        final c = await container(server);

        await expectLater(
          c.read(sellixApiProvider).me(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', words)
                .having((e) => e.isUnauthorized, 'isUnauthorized', isFalse),
          ),
        );
        expect(c.read(authControllerProvider).value, AuthStatus.signedIn);
        expect(await c.read(tokenStoreProvider).refreshToken(), 'r1');

        // Back online: the same session refreshes and the call goes through.
        server.refresh = _Refresh.ok;
        final me = await c.read(sellixApiProvider).me();
        expect(me.merchant.name, 'Shop');
        expect(await c.read(tokenStoreProvider).refreshToken(), 'r2');
      });
    }
  });

  test('a real 401 from the refresh signs out and clears the session', () async {
    expiredSession();
    final server = _Server()..refresh = _Refresh.unauthorized;
    final c = await container(server);
    await expectLater(
      c.read(sellixApiProvider).me(),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
    );
    expect(c.read(authControllerProvider).value, AuthStatus.signedOut);
    expect(await c.read(tokenStoreProvider).refreshToken(), isNull);
  });

  test('a refused token, then an offline refresh, is a network error and not a sign-out', () async {
    freshSession();
    final server = _Server()
      ..refuseOnce = true
      ..refresh = _Refresh.offline;
    final c = await container(server);
    await expectLater(
      c.read(sellixApiProvider).me(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', "Can't reach sellix. Check your connection.")),
    );
    expect(c.read(authControllerProvider).value, AuthStatus.signedIn);
    expect(await c.read(tokenStoreProvider).refreshToken(), 'r1');
  });

  test('a refused token is refreshed once and the call retried', () async {
    freshSession();
    final server = _Server()..refuseOnce = true;
    final c = await container(server);
    final me = await c.read(sellixApiProvider).me();
    expect(me.merchant.id, 'm1');
    expect(server.paths.where((p) => p.endsWith('/v1/me')), hasLength(2));
    expect(server.requests.last.headers['Authorization'], 'Bearer new');
  });

  group('server address', () {
    test('release builds need https; debug builds may use http', () {
      expect(serverUrlError('https://api.shop.in', release: true), isNull);
      expect(serverUrlError('http://192.168.1.5:8000', release: true), 'Use an https:// address.');
      expect(serverUrlError('http://192.168.1.5:8000', release: false), isNull);
      expect(serverUrlError('  ', release: false), 'Enter the server address.');
      expect(serverUrlError('api.shop.in', release: false), contains('not a web address'));
      expect(serverUrlError('ftp://api.shop.in', release: false), 'The address starts with https://');
      expect(serverUrlError('https://api.shop.in/?x=1', release: false), contains('after ?'));
      expect(normalizeServerUrl(' https://api.shop.in// '), 'https://api.shop.in');
    });

    test('requests follow the chosen server, which is kept on the phone', () async {
      freshSession();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = _Server();
      final c = await container(server, prefs: prefs);
      expect(c.read(serverUrlProvider), 'http://localhost:8000');
      await c.read(sellixApiProvider).me();
      expect(server.requests.last.uri.host, 'localhost');

      await c.read(serverUrlProvider.notifier).set('https://api.shop.in/');
      expect(prefs.getString('server_url'), 'https://api.shop.in');
      await c.read(sellixApiProvider).me();
      expect(server.requests.last.uri.toString(), 'https://api.shop.in/v1/me');

      // Back to the build's own address: nothing is kept.
      await c.read(serverUrlProvider.notifier).set('http://localhost:8000');
      expect(prefs.getString('server_url'), isNull);
    });

    test('changing the server signs out on the old one first', () async {
      freshSession();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = _Server();
      final c = await container(server, prefs: prefs);
      await c.read(authControllerProvider.notifier).changeServer('https://api.shop.in');
      expect(server.paths.last, 'POST localhost/v1/auth/logout');
      expect(c.read(authControllerProvider).value, AuthStatus.signedOut);
      expect(await c.read(tokenStoreProvider).refreshToken(), isNull);
      expect(c.read(serverUrlProvider), 'https://api.shop.in');
    });
  });
}
