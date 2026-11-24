import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/orders/orders_screen.dart';

import '../../support/fake_sellix_api.dart';
import 'orders_test_support.dart';

void main() {
  group('paging', pagingTests);

  testWidgets('shows a skeleton while loading', (tester) async {
    final api = FakeSellixApi()..delay = const Duration(seconds: 1);
    await pumpScreen(tester, api, const OrdersScreen(), settle: false);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(SxSkeletonList), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SxSkeletonList), findsNothing);
  });

  testWidgets('shows orders with the customer joined from the conversation', (tester) async {
    final api = FakeSellixApi();
    await pumpScreen(tester, api, const OrdersScreen());
    expect(find.text('Do this next'), findsOneWidget);
    expect(find.text('Accept customer.one’s order'), findsOneWidget);
    expect(find.text('customer.one'), findsOneWidget);
    expect(find.text('Accept order'), findsOneWidget);
    expect(find.textContaining('Lakshmi'), findsNothing);
  });

  testWidgets('tabs split the orders', (tester) async {
    final api = FakeSellixApi();
    await pumpScreen(tester, api, const OrdersScreen());
    await tester.tap(find.text('Waiting payment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('#1 ·'), findsOneWidget);
    expect(find.textContaining('#2 ·'), findsNothing);
  });

  testWidgets('a new shop sees empty states, not sample data', (tester) async {
    final api = FakeSellixApi.empty();
    await pumpScreen(tester, api, const OrdersScreen());
    expect(find.text('You are up to date'), findsOneWidget);
    expect(find.text('Nothing to do now'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
  });

  testWidgets('an error offers retry, which recovers', (tester) async {
    final api = FakeSellixApi()..failure = const ApiException('Server is down');
    await pumpScreen(tester, api, const OrdersScreen());
    expect(find.text('Server is down'), findsOneWidget);
    api.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Do this next'), findsOneWidget);
  });

  testWidgets('the row action asks first, then calls the status endpoint', (tester) async {
    final api = FakeSellixApi();
    await pumpScreen(tester, api, const OrdersScreen());
    await tester.tap(find.text('Accept order'));
    await tester.pumpAndSettle();
    expect(find.text('Accept this order?'), findsOneWidget);
    expect(api.calls, isNot(contains('updateOrderStatus')));

    await tester.tap(sxButton('Accept order').last);
    await tester.pumpAndSettle();
    expect(api.calls, contains('updateOrderStatus'));
    expect(api.orderList.firstWhere((o) => o.id == FakeIds.orderPaid).status, OrderStatus.confirmed);
    expect(find.textContaining('No message sent'), findsOneWidget);
    await finishSnack(tester);
  });

  testWidgets('search finds by customer and by number', (tester) async {
    final api = FakeSellixApi();
    await pumpScreen(tester, api, const OrdersScreen());
    await tester.tap(find.bySemanticsLabel('Search orders'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '#2');
    await tester.pumpAndSettle();
    expect(find.text('1 order found'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No orders match'), findsOneWidget);
  });
}

/// Records the `before` of each orders call, as the paging sends it.
class _PagingApi extends FakeSellixApi {
  final befores = <DateTime?>[];

  @override
  Future<List<Order>> orders({List<String>? status, List<String>? paymentStatus, int? limit, DateTime? before}) {
    befores.add(before);
    return super.orders(status: status, paymentStatus: paymentStatus, limit: limit, before: before);
  }
}

Finder _labelled(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().replaceAll('\uFFFC', '').trim() == text,
  skipOffstage: false,
);

void pagingTests() {
  testWidgets('a full first page offers older orders, a page at a time', (tester) async {
    final api = _PagingApi()
      ..orderList = [
        for (var i = 0; i < 230; i++)
          makeOrder(
            id: 'o$i',
            number: 1000 - i,
            status: OrderStatus.completed,
            createdAt: FakeSellixApi.now.subtract(Duration(minutes: i)),
          ),
      ];
    await pumpScreen(tester, api, const OrdersScreen());
    expect(api.befores, [null]);
    final more = _labelled('Load older orders');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    // The page starts before the oldest order shown, which is the 200th.
    expect(api.befores.last, FakeSellixApi.now.subtract(const Duration(minutes: 199)));
    // 30 more came back: fewer than a page, so there is nothing older.
    expect(_labelled('Load older orders'), findsNothing);
  });

  testWidgets('a short first page offers nothing more', (tester) async {
    await pumpScreen(tester, FakeSellixApi(), const OrdersScreen());
    expect(_labelled('Load older orders'), findsNothing);
  });
}
