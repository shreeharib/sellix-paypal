import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/orders/customer_screen.dart';
import 'package:sellix_merchant/features/orders/customers_screen.dart';
import 'package:sellix_merchant/features/orders/order_screen.dart';
import 'package:sellix_merchant/features/orders/orders_screen.dart';

import '../../support/fake_sellix_api.dart';
import 'orders_test_support.dart';

/// Every state at phone width, in both themes, with a long raw channel id as the customer.
FakeSellixApi _busyShop() {
  final api = FakeSellixApi();
  api.conversationList = [
    Conversation(
      id: FakeIds.conversationA,
      channel: 'instagram',
      customerHandle: '17841400000000000123456789',
      agentActive: true,
      agentPausedReason: null,
      lastMessageSender: null,
      lastMessageBody: null,
      lastMessageAt: null,
    ),
  ];
  api.orderList = [
    for (final (i, (status, pay, method)) in const [
      (OrderStatus.awaitingPayment, 'unpaid', 'pickup'),
      (OrderStatus.paid, 'paid', 'courier'),
      (OrderStatus.confirmed, 'paid', 'local_delivery'),
      (OrderStatus.ready, 'paid', 'pickup'),
      (OrderStatus.delivered, 'paid', 'courier'),
      (OrderStatus.completed, 'paid', 'digital'),
      (OrderStatus.cancelled, 'paid', 'pickup'),
      (OrderStatus.expired, 'unpaid', 'pickup'),
      (OrderStatus.refunded, 'refunded', 'pickup'),
    ].indexed)
      makeOrder(
        id: 'o$i',
        number: 100000 + i,
        status: status,
        paymentStatus: pay,
        method: method,
        totalMinor: 123456789,
        address: 'Plot 12, Long Street Name, Long Area Name, Chennai 600001',
      ),
  ];
  return api;
}

void main() {
  for (final (name, theme) in [('light', sellixLight), ('dark', sellixDark)]) {
    testWidgets('lists lay out at phone width: $name', (tester) async {
      final api = _busyShop();
      await pumpScreen(tester, api, const OrdersScreen(), width: 390, theme: theme);
      expect(tester.takeException(), isNull);
      for (final label in ['In progress', 'Waiting payment', 'Done', 'All']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      // The list's staggered entrance runs on timers.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('customers lay out at phone width: $name', (tester) async {
      await pumpScreen(tester, _busyShop(), const CustomersScreen(), width: 390, theme: theme);
      expect(tester.takeException(), isNull);
    });

    testWidgets('customer lays out at phone width: $name', (tester) async {
      await pumpScreen(
        tester,
        _busyShop(),
        const CustomerScreen(FakeIds.conversationA),
        width: 390,
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    });

    for (var i = 0; i < 9; i++) {
      testWidgets('order in state $i lays out at phone width: $name', (tester) async {
        await pumpScreen(tester, _busyShop(), OrderScreen('o$i'), width: 390, theme: theme);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
