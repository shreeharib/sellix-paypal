import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/design/widgets/sx_snack.dart' show SxSnackNavigatorObserver;
import 'package:sellix_merchant/features/signin/auth_screen.dart';
import 'package:sellix_merchant/features/signin/autherror_screen.dart';
import 'package:sellix_merchant/features/signin/connected_screen.dart';
import 'package:sellix_merchant/features/signin/connecting_screen.dart';
import 'package:sellix_merchant/features/signin/iglogin_screen.dart';
import 'package:sellix_merchant/features/signin/prebrief_screen.dart';
import 'package:sellix_merchant/features/signin/sign_in_flow.dart';
import 'package:sellix_merchant/features/signin/splash_screen.dart';
import 'package:sellix_merchant/features/signin/welcome_screen.dart';

import '../../support/fake_sellix_api.dart';

/// Stands in for the browser login: [signInWithInstagram] does what [result] says.
class _FakeAuth extends AuthController {
  _FakeAuth(this.start, this.result);

  final AuthStatus start;
  final Object? result;
  int started = 0;

  @override
  Future<AuthStatus> build() async => start;

  @override
  Future<void> signInWithInstagram() async {
    started++;
    final r = result;
    if (r != null) throw r;
    state = const AsyncData(AuthStatus.signedIn);
  }
}

class _Harness {
  _Harness(this.fake, this.auth, this.router);

  final FakeSellixApi fake;
  final _FakeAuth auth;
  final GoRouter router;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget screen, {
  FakeSellixApi? api,
  AuthStatus start = AuthStatus.signedOut,
  Object? result,
  bool requested = false,
  String? error,
  bool completed = false,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final fake = api ?? FakeSellixApi.empty();
  final auth = _FakeAuth(start, result);
  final router = GoRouter(
    initialLocation: '/start',
    navigatorKey: rootNavigatorKey,
    observers: [SxSnackNavigatorObserver()],
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      for (final r in [Routes.auth, Routes.welcome, Routes.iglogin, Routes.connecting, Routes.connected, Routes.autherror, Routes.obShop, Routes.home])
        GoRoute(path: r, builder: (_, _) => Scaffold(body: Text('at $r'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sellixApiProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(() => auth),
        onboardingCompletedProvider.overrideWith((ref) async {
          await ref.read(sellixApiProvider).onboarding();
          return completed;
        }),
        signInFlowProvider.overrideWith(() => _SeededFlow(SignInFlowState(requested: requested, error: error))),
      ],
      child: MaterialApp.router(routerConfig: router, theme: theme ?? sellixLight),
    ),
  );
  return _Harness(fake, auth, router);
}

class _SeededFlow extends SignInFlow {
  _SeededFlow(this.initial);

  final SignInFlowState initial;

  @override
  SignInFlowState build() => initial;
}

/// A label as drawn, also when an icon sits inside the same rich text.
Finder _label(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().replaceAll('\uFFFC', '').trim() == text,
);

Future<void> _settle(WidgetTester tester, [int steps = 14]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('splash shows the brand and does not navigate by itself', (tester) async {
    final h = await _pump(tester, const SplashScreen());
    await _settle(tester);
    expect(find.text('Your DMs, run like a business.'), findsOneWidget);
    expect(h.router.state.matchedLocation, '/start');
  });

  group('auth', () {
    testWidgets('Instagram is the working way in; the others say they are not available', (tester) async {
      final h = await _pump(tester, const AuthScreen());
      await _settle(tester);
      expect(find.text('Sign up with Google'), findsOneWidget);
      expect(find.textContaining('not available yet'), findsOneWidget);
      await tester.tap(find.text('Sign up with Google'));
      await _settle(tester);
      expect(h.router.state.matchedLocation, '/start');

      await tester.tap(find.text('Sign up with Instagram'));
      await _settle(tester);
      expect(find.text('at ${Routes.welcome}'), findsOneWidget);
    });

    testWidgets('signing back in goes straight to Instagram', (tester) async {
      await _pump(tester, const AuthScreen());
      await _settle(tester);
      await tester.tap(find.text('Sign in'));
      await _settle(tester);
      await tester.tap(find.text('Sign in with Instagram'));
      await _settle(tester);
      expect(find.text('at ${Routes.iglogin}'), findsOneWidget);
    });

    testWidgets('lays out in dark, on a small phone', (tester) async {
      await _pump(tester, const AuthScreen(), theme: sellixDark);
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('welcome and pre-brief', () {
    testWidgets('no demo chat; the language toggle swaps the copy', (tester) async {
      await _pump(tester, const WelcomeScreen());
      await _settle(tester);
      expect(find.text('Now connect your shop’s Instagram.'), findsOneWidget);
      expect(find.textContaining('meena'), findsNothing);
      await tester.tap(find.text('தமிழ்'));
      await _settle(tester);
      expect(find.text('Instagram மூலம் தொடரவும்'), findsOneWidget);
    });

    testWidgets('the sheet states the permissions, and its button starts the real login', (tester) async {
      await _pump(tester, const PrebriefScreen());
      await _settle(tester);
      expect(find.text('Post on your account'), findsOneWidget);
      await tester.ensureVisible(_label('Continue to Instagram'));
      await tester.pump();
      await tester.tap(_label('Continue to Instagram'));
      await _settle(tester);
      expect(find.text('at ${Routes.connecting}'), findsOneWidget);
    });
  });

  testWidgets('iglogin draws no fake Instagram page, and Continue hands over', (tester) async {
    await _pump(tester, const IgLoginScreen());
    await _settle(tester);
    expect(find.text('Allow'), findsNothing);
    expect(find.text('instagram.com'), findsNothing);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('at ${Routes.connecting}'), findsOneWidget);
  });

  group('connecting', () {
    testWidgets('opened with no sign-in under way, it starts nothing', (tester) async {
      final h = await _pump(tester, const ConnectingScreen());
      await _settle(tester);
      expect(h.auth.started, 0);
      expect(find.text('Instagram is not connected yet'), findsOneWidget);
    });

    testWidgets('a new shop signs in once and goes to connected', (tester) async {
      final h = await _pump(tester, const ConnectingScreen(), requested: true);
      await _settle(tester);
      expect(h.auth.started, 1);
      expect(h.fake.calls, contains('me'));
      expect(find.text('at ${Routes.connected}'), findsOneWidget);
    });

    testWidgets('a finished shop goes home with a welcome back', (tester) async {
      final h = await _pump(tester, const ConnectingScreen(), requested: true, completed: true);
      await _settle(tester);
      expect(find.text('at ${Routes.home}'), findsOneWidget);
      expect(h.auth.started, 1);
      expect(_label('Welcome back, Test Shop.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('cancelling returns to welcome', (tester) async {
      await _pump(tester, const ConnectingScreen(), requested: true, result: const SignInCancelled());
      await _settle(tester);
      expect(find.text('at ${Routes.welcome}'), findsOneWidget);
    });

    testWidgets('a refused account goes to the error screen with the server’s reason', (tester) async {
      await _pump(tester, const ConnectingScreen(), requested: true, result: const ApiException('Nope'));
      await _settle(tester);
      expect(find.text('at ${Routes.autherror}'), findsOneWidget);
    });

    testWidgets('after sign-in, a network failure retries in place', (tester) async {
      final fake = FakeSellixApi.empty()..failure = const ApiException('No network');
      await _pump(tester, const ConnectingScreen(), api: fake, start: AuthStatus.signedIn);
      await _settle(tester);
      expect(find.text('No network'), findsOneWidget);
      fake.failure = null;
      await tester.ensureVisible(find.text('Try again'));
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('at ${Routes.connected}'), findsOneWidget);
    });
  });

  group('connected', () {
    testWidgets('names the real shop and account, then starts setup', (tester) async {
      final fake = FakeSellixApi.empty()
        ..channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'active')];
      await _pump(tester, const ConnectedScreen(), api: fake);
      await _settle(tester);
      expect(find.text('sellix × Test Shop'), findsOneWidget);
      expect(find.text('@test.shop'), findsOneWidget);
      expect(_label('Receiving messages'), findsOneWidget);
      await tester.tap(find.text('Set up my shop'));
      await _settle(tester);
      expect(find.text('at ${Routes.obShop}'), findsOneWidget);
    });

    testWidgets('does not claim messages arrive when no channel is active', (tester) async {
      await _pump(tester, const ConnectedScreen());
      await _settle(tester);
      expect(_label('Receiving messages'), findsNothing);
    });

    testWidgets('a signed-in shop with no Instagram connects it in place, with the real login', (tester) async {
      final fake = FakeSellixApi.empty();
      final h = await _pump(tester, const ConnectedScreen(), api: fake, start: AuthStatus.signedIn);
      await _settle(tester);
      expect(_label('Receiving messages'), findsNothing);
      fake.channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'active')];
      await tester.ensureVisible(_label('Connect Instagram'));
      await tester.pump();
      await tester.tap(_label('Connect Instagram'));
      await _settle(tester);
      expect(h.auth.started, 1);
      expect(_label('Receiving messages'), findsOneWidget);
      expect(find.text('@test.shop'), findsOneWidget);
      expect(_label('Instagram is connected.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a cancelled connect says Instagram is still not connected', (tester) async {
      final h = await _pump(tester, const ConnectedScreen(), start: AuthStatus.signedIn, result: const SignInCancelled());
      await _settle(tester);
      await tester.ensureVisible(_label('Connect Instagram'));
      await tester.pump();
      await tester.tap(_label('Connect Instagram'));
      await _settle(tester);
      expect(h.auth.started, 1);
      expect(_label('Cancelled. Instagram is still not connected.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('error has a retry', (tester) async {
      final fake = FakeSellixApi.empty()..failure = const ApiException('No me');
      await _pump(tester, const ConnectedScreen(), api: fake);
      await _settle(tester);
      expect(find.text('No me'), findsOneWidget);
      fake.failure = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Integrated with sellix'), findsOneWidget);
    });
  });

  group('sign-in error', () {
    testWidgets('a personal account gets the switch steps and the server’s words', (tester) async {
      const reason = 'Instagram didn\'t allow this account. Use your shop\'s professional account.';
      await _pump(tester, const AuthErrorScreen(), error: reason);
      await _settle(tester);
      expect(find.text('Instagram did not allow this account'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(find.text('Switch in one minute'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('at ${Routes.iglogin}'), findsOneWidget);
    });

    testWidgets('other failures do not show the steps', (tester) async {
      await _pump(tester, const AuthErrorScreen(), error: "Instagram wasn't connected. Please try again.");
      await _settle(tester);
      expect(find.text('Instagram was not connected'), findsOneWidget);
      expect(find.text('Switch in one minute'), findsNothing);
    });
  });
}
