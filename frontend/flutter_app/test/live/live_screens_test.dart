// Opens every real screen against a running backend, to catch JSON the fake API hides.
//   LIVE_API_URL=http://localhost:8000 LIVE_TOKEN=<token> flutter test test/live/live_screens_test.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/app.dart';
import 'package:sellix_merchant/core/api/sellix_api.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  @override
  Future<AuthStatus> build() async => AuthStatus.signedIn;
}

void main() {
  final url = Platform.environment['LIVE_API_URL'] ?? '';
  final token = Platform.environment['LIVE_TOKEN'] ?? '';
  final ids = (Platform.environment['LIVE_IDS'] ?? '').split(',');

  testWidgets('every screen loads real data without an error state', (tester) async {
    HttpOverrides.global = null;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: url, headers: {'Authorization': 'Bearer $token'}));
    final api = HttpSellixApi(dio);

    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sellixApiProvider.overrideWithValue(api),
        authControllerProvider.overrideWith(_SignedIn.new),
        onboardingCompletedProvider.overrideWith((ref) async => true),
      ],
      child: const SellixApp(),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final router =
        ProviderScope.containerOf(tester.element(find.byType(SellixApp))).read(routerProvider);
    final problems = <String>[];
    final routes = [
      Routes.home, Routes.chats, Routes.stock, Routes.orders, Routes.profile, Routes.notifications,
      Routes.needs, Routes.insights, Routes.morning, Routes.customers, Routes.automations, Routes.rules,
      Routes.channels, Routes.payments, Routes.shopprofile, Routes.hours, Routes.addproduct,
      Routes.obShop, Routes.obHours, Routes.obPay, Routes.obRules, Routes.obTalk, Routes.obStock,
      ...ids.where((e) => e.isNotEmpty).map((e) {
        final p = e.split(':');
        return switch (p[0]) {
          'chat' => Routes.chat(p[1]),
          'order' => Routes.order(p[1]),
          'customer' => Routes.customer(p[1]),
          'product' => Routes.product(p[1]),
          _ => throw p[0],
        };
      }),
    ];
    for (final route in routes) {
      final errors = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
      router.go(route);
      await settle();
      FlutterError.onError = old;
      final retry = find.textContaining(RegExp(r'Try again|Retry|Something went wrong|TypeError'));
      final skeleton = find.byType(SxSkeleton);
      final bad = [
        if (retry.evaluate().isNotEmpty) 'error state: ${retry.evaluate().first.widget}',
        if (skeleton.evaluate().isNotEmpty) 'still loading',
        ...errors.take(2),
        if (tester.takeException() case final e?) 'exception: $e',
      ];
      // ignore: avoid_print
      print('${bad.isEmpty ? 'ok  ' : 'FAIL'} $route ${bad.join(' | ')}');
      if (bad.isNotEmpty) problems.add(route);
    }
    expect(problems, isEmpty);
    // Let the HTTP client's idle timers run out before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  }, skip: url.isEmpty || token.isEmpty);
}
