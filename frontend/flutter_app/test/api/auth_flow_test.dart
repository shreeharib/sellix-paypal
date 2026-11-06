import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/auth/instagram_connect.dart';
import 'package:sellix_merchant/core/providers.dart';

/// The routes the backend really has (backend/app/api/v1/auth.py), answered like it answers them.
class _FakeServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, Object?> me = _me('m1', 'Dev Shop', const []);
  int tokenStatus = 200;

  List<String> get paths => [for (final r in requests) '${r.method} ${r.path}'];
  RequestOptions request(String path) => requests.lastWhere((r) => r.path == path);
  Map<String, dynamic> body(String path) => request(path).data as Map<String, dynamic>;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? _) async {
    requests.add(options);
    final (status, json) = switch ('${options.method} ${options.path}') {
      'POST /v1/auth/instagram/start' => (
        200,
        {'authorize_url': 'https://www.instagram.com/oauth/authorize?client_id=1&state=signed'},
      ),
      'POST /v1/auth/token' => tokenStatus == 200
          ? (200, {'access_token': 'acc', 'refresh_token': 'ref', 'expires_in': 3600, 'token_type': 'bearer'})
          : (tokenStatus, {'detail': 'This login wasn\'t started by this app. Please sign in again.'}),
      'GET /v1/me' => (200, me),
      _ => (404, {'detail': 'Not Found'}),
    };
    return ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _me(String id, String name, List<Map<String, Object?>> channels) => {
  'user_id': 'u1',
  'merchant': {'id': id, 'name': name, 'timezone': 'Asia/Kolkata', 'agent_enabled': true},
  'role': 'owner',
  'channels': channels,
  'onboarding_completed': false,
};

/// Stands in for ASWebAuthenticationSession / Custom Tabs: returns what Instagram's redirect would.
class _Browser {
  _Browser(this.answer);

  final String Function(String url) answer;
  final opened = <(String, String)>[];

  Future<String> call({required String url, required String callbackUrlScheme}) async {
    opened.add((url, callbackUrlScheme));
    return answer(url);
  }
}

/// Pins the DEV ONLY session on or off, so these tests mean the same with or without the define.
class _Dev extends DevSignIn {
  _Dev(this.on);

  final bool on;

  @override
  bool build() => on;
}

String _s256(String verifier) => base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container(_FakeServer server, _Browser browser, {bool dev = false}) {
    final c = ProviderContainer(
      overrides: [
        httpAdapterProvider.overrideWithValue(server),
        webAuthenticateProvider.overrideWithValue(browser.call),
        devSignInProvider.overrideWith(() => _Dev(dev)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('sign-in sends exactly what the API expects, with a matching PKCE pair', () async {
    final server = _FakeServer();
    final browser = _Browser((_) => 'sellix://auth/callback?code=one-time');
    final c = container(server, browser);
    expect(await c.read(authControllerProvider.future), AuthStatus.signedOut);

    await c.read(authControllerProvider.notifier).signInWithInstagram();

    expect(server.paths, ['POST /v1/auth/instagram/start', 'POST /v1/auth/token']);
    final start = server.body('/v1/auth/instagram/start');
    expect(start.keys, unorderedEquals(['code_challenge', 'redirect_uri']));
    expect(start['redirect_uri'], 'sellix://auth/callback');
    // The backend accepts only a base64url SHA-256 challenge, 43 characters, unpadded.
    expect(start['code_challenge'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));

    expect(browser.opened.single, ('https://www.instagram.com/oauth/authorize?client_id=1&state=signed', 'sellix'));

    final token = server.body('/v1/auth/token');
    expect(token.keys, unorderedEquals(['code', 'code_verifier']));
    expect(token['code'], 'one-time');
    final verifier = token['code_verifier'] as String;
    expect(verifier.length, inInclusiveRange(43, 128));
    expect(_s256(verifier), start['code_challenge']);

    expect(c.read(authControllerProvider).value, AuthStatus.signedIn);
    expect(await c.read(tokenStoreProvider).refreshToken(), 'ref');
    expect(await c.read(tokenStoreProvider).validAccessToken(), 'acc');
  });

  test('closing Instagram is a cancel, not an error', () async {
    final server = _FakeServer();
    final browser = _Browser((_) => throw PlatformException(code: 'CANCELED'));
    final c = container(server, browser);
    await c.read(authControllerProvider.future);
    await expectLater(c.read(authControllerProvider.notifier).signInWithInstagram(), throwsA(isA<SignInCancelled>()));
    expect(server.paths, ['POST /v1/auth/instagram/start']);
  });

  test('the server’s reason from the redirect reaches the merchant', () async {
    final server = _FakeServer();
    final browser = _Browser((_) => 'sellix://auth/callback?error=${Uri.encodeQueryComponent('Use your shop\'s professional account.')}');
    final c = container(server, browser);
    await c.read(authControllerProvider.future);
    await expectLater(
      c.read(authControllerProvider.notifier).signInWithInstagram(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Use your shop\'s professional account.')),
    );
    expect(await c.read(tokenStoreProvider).refreshToken(), isNull);
  });

  test('a refused code exchange keeps the merchant signed out', () async {
    final server = _FakeServer()..tokenStatus = 401;
    final c = container(server, _Browser((_) => 'sellix://auth/callback?code=x'));
    await c.read(authControllerProvider.future);
    await expectLater(c.read(authControllerProvider.notifier).signInWithInstagram(), throwsA(isA<ApiException>()));
    expect(c.read(authControllerProvider).value, AuthStatus.signedOut);
  });

  group('DEV_ACCESS_TOKEN session', () {
    test('signed in already, a real Instagram login still runs and its session takes over', () async {
      final server = _FakeServer();
      final c = container(server, _Browser((_) => 'sellix://auth/callback?code=one-time'), dev: true);
      expect(await c.read(authControllerProvider.future), AuthStatus.signedIn);

      await c.read(sellixApiProvider).me();
      expect(server.request('/v1/me').headers['Authorization'], isNot('Bearer acc'));

      server.me = _me('m1', 'Dev Shop', [
        {'channel': 'instagram', 'username': 'dev.shop', 'status': 'active'},
      ]);
      final result = await c.read(instagramConnectProvider).run(merchantId: 'm1');

      expect(result.outcome, InstagramConnectOutcome.connected);
      expect(c.read(devSignInProvider), isFalse);
      expect(server.request('/v1/me').headers['Authorization'], 'Bearer acc');
      expect(server.paths, containsAllInOrder(['POST /v1/auth/instagram/start', 'POST /v1/auth/token', 'GET /v1/me']));
    });

    test('an account that belongs to another shop says so', () async {
      final server = _FakeServer();
      final c = container(server, _Browser((_) => 'sellix://auth/callback?code=c'), dev: true);
      await c.read(authControllerProvider.future);
      server.me = _me('m2', 'Other Shop', [
        {'channel': 'instagram', 'username': 'other', 'status': 'active'},
      ]);
      final result = await c.read(instagramConnectProvider).run(merchantId: 'm1');
      expect(result.outcome, InstagramConnectOutcome.otherShop);
      expect(result.me!.merchant.name, 'Other Shop');
    });

    test('cancelling keeps the dev session', () async {
      final server = _FakeServer();
      final c = container(server, _Browser((_) => throw PlatformException(code: 'CANCELED')), dev: true);
      await c.read(authControllerProvider.future);
      final result = await c.read(instagramConnectProvider).run(merchantId: 'm1');
      expect(result.outcome, InstagramConnectOutcome.cancelled);
      expect(c.read(devSignInProvider), isTrue);
    });
  });
}
