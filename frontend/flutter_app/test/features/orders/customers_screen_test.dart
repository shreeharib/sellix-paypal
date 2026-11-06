import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/orders/customer_screen.dart';
import 'package:sellix_merchant/features/orders/customers_screen.dart';

import '../../support/fake_sellix_api.dart';
import 'orders_test_support.dart';

void main() {
  group('customers', () {
    testWidgets('shows a skeleton while loading', (tester) async {
      final api = FakeSellixApi()..delay = const Duration(seconds: 1);
      await pumpScreen(tester, api, const CustomersScreen(), settle: false);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byType(SxSkeletonList), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SxSkeletonList), findsNothing);
    });

    testWidgets('joins conversations to orders and counts only paid', (tester) async {
      await pumpScreen(tester, FakeSellixApi(), const CustomersScreen());
      expect(find.text('customer.one'), findsOneWidget);
      expect(find.text('1 paid order'), findsOneWidget);
      expect(find.text('₹200'), findsWidgets);
      expect(find.text('1 of 1 people bought from you'), findsOneWidget);
    });

    testWidgets('empty shop', (tester) async {
      await pumpScreen(tester, FakeSellixApi.empty(), const CustomersScreen());
      expect(find.text('No customers yet'), findsOneWidget);
    });

    testWidgets('an error offers retry', (tester) async {
      final api = FakeSellixApi()..failure = const ApiException('Server is down');
      await pumpScreen(tester, api, const CustomersScreen());
      expect(find.text('Server is down'), findsOneWidget);
      api.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('customer.one'), findsOneWidget);
    });

    testWidgets('search and filters narrow the list', (tester) async {
      await pumpScreen(tester, FakeSellixApi(), const CustomersScreen());
      await tester.tap(find.text('Repeat'));
      await tester.pumpAndSettle();
      expect(find.text('No customers match'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'customer');
      await tester.pumpAndSettle();
      expect(find.text('customer.one'), findsOneWidget);
    });

    testWidgets('Abroad says plainly it is not available', (tester) async {
      await pumpScreen(tester, FakeSellixApi(), const CustomersScreen());
      await tester.tap(find.text('Abroad'));
      await tester.pump();
      expect(find.textContaining('country isn’t available'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('customer', () {
    testWidgets('shows real stats and orders, and invents no phone', (tester) async {
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const CustomerScreen(FakeIds.conversationA));
      expect(find.text('customer.one'), findsWidgets);
      expect(find.text('Paid orders'), findsOneWidget);
      expect(find.text('No phone number'), findsOneWidget);
      expect(find.text('All orders'), findsOneWidget);
      expect(find.textContaining('#1 ·'), findsOneWidget);
      expect(find.textContaining('#2 ·'), findsOneWidget);
      expect(find.text('Test address'), findsOneWidget);
      expect(find.textContaining('prefers: pickup'), findsOneWidget);
    });

    testWidgets('Open chat goes to their conversation', (tester) async {
      await pumpScreen(tester, FakeSellixApi(), const CustomerScreen(FakeIds.conversationA));
      await tester.tap(find.text('Open chat'));
      await tester.pumpAndSettle();
      expect(find.text('chat ${FakeIds.conversationA}'), findsOneWidget);
    });

    testWidgets('an unknown id says so', (tester) async {
      await pumpScreen(tester, FakeSellixApi(), const CustomerScreen('nobody'));
      expect(find.text('Customer not found'), findsOneWidget);
    });

    testWidgets('order row opens the order', (tester) async {
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const CustomerScreen(FakeIds.conversationA));
      await tester.tap(find.textContaining('#2 ·'));
      await tester.pumpAndSettle();
      expect(find.text('Order #2'), findsOneWidget);
      expect(api.orderList.first.status, OrderStatus.awaitingPayment);
    });
  });
}
