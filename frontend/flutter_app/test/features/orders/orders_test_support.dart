import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/orders/customer_screen.dart';
import 'package:sellix_merchant/features/orders/order_screen.dart';

import '../../support/fake_sellix_api.dart';

/// An order with sensible defaults, so a test only states what it's about.
Order makeOrder({
  String id = 'o1',
  int number = 7,
  String status = OrderStatus.paid,
  String paymentStatus = 'paid',
  String method = 'pickup',
  String currency = 'INR',
  int totalMinor = 50000,
  String? conversationId = FakeIds.conversationA,
  DateTime? createdAt,
  DateTime? paidAt,
  DateTime? holdExpiresAt,
  String? address,
}) => Order(
  id: id,
  number: number,
  status: status,
  currency: currency,
  totalMinor: totalMinor,
  conversationId: conversationId,
  createdAt: createdAt ?? FakeSellixApi.now,
  paidAt: paidAt,
  holdExpiresAt: holdExpiresAt,
  items: const [OrderItem(product: 'Item A', variant: null, quantity: 1, unitPriceMinor: 50000)],
  paymentStatus: paymentStatus,
  fulfilmentMethod: method,
  deliveryAddress: address,
);

/// [screen] under the app's theme, with the routes it pushes to.
Future<void> pumpScreen(
  WidgetTester tester,
  FakeSellixApi api,
  Widget screen, {
  bool settle = true,
  double width = 520,
  ThemeData? theme,
}) async {
  // Wider than a phone: the test font draws every letter square, far wider than Satoshi.
  tester.view.physicalSize = Size(width * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/order/:id', builder: (_, s) => OrderScreen(s.pathParameters['id']!)),
      GoRoute(path: '/customer/:id', builder: (_, s) => CustomerScreen(s.pathParameters['id']!)),
      GoRoute(path: '/chat/:id', builder: (_, s) => Text('chat ${s.pathParameters['id']}')),
      GoRoute(path: Routes.payments, builder: (_, _) => const Text('payments')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [sellixApiProvider.overrideWithValue(api)],
      child: MaterialApp.router(theme: theme ?? sellixLight, routerConfig: router),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// An [SxButton] by label. Its text holds an inline icon, so `find.text` doesn't match it.
Finder sxButton(String label) =>
    find.byWidgetPredicate((widget) => widget is SxButton && widget.label == label);

/// Lets a snackbar's timer run out, so no timer is left when the test ends.
Future<void> finishSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}
