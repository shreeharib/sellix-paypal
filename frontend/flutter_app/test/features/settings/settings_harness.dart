import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_sellix_api.dart';

/// Signs out and reconnects without a browser.
class FakeAuth extends AuthController {
  FakeAuth({this.onSignIn});

  /// Runs in place of Instagram's login.
  final Future<void> Function()? onSignIn;
  int signIns = 0;
  int signOuts = 0;

  @override
  Future<AuthStatus> build() async => AuthStatus.signedIn;

  @override
  Future<void> signInWithInstagram() async {
    signIns++;
    await onSignIn?.call();
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    state = const AsyncData(AuthStatus.signedOut);
  }
}

/// Pumps [screen] as a router's first page, on a tall phone so whole screens are built. Every other
/// route shows "route:" and its path, so navigation can be asserted.
Future<SharedPreferences> pumpScreen(
  WidgetTester tester,
  Widget screen,
  FakeSellixApi fake, {
  FakeAuth? auth,
  Map<String, Object> prefs = const {},
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = const Size(420, 3200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, _) => screen),
      for (final path in [
        Routes.profile,
        Routes.automations,
        Routes.newauto,
        Routes.rules,
        Routes.channels,
        Routes.payments,
        Routes.shopprofile,
        Routes.hours,
        Routes.morning,
        Routes.needs,
        Routes.orders,
        '/automation/:id',
      ])
        GoRoute(path: path, builder: (_, state) => Text('route:${state.uri.path}')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sellixApiProvider.overrideWithValue(fake),
        sharedPreferencesProvider.overrideWithValue(preferences),
        authControllerProvider.overrideWith(() => auth ?? FakeAuth()),
      ],
      child: MaterialApp.router(
        theme: dark ? sellixDark : sellixLight,
        routerConfig: router,
      ),
    ),
  );
  return preferences;
}

/// pumpAndSettle would never return: live pills and skeletons animate forever.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets snackbar timers finish, so a test ends with none pending.
Future<void> drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await settle(tester);
}
