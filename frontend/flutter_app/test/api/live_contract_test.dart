/// Calls a real API and checks that the app can parse every answer.
///
///     cd backend && just cli issue-token --merchant-id <id>
///     LIVE_API_URL=http://localhost:8000 LIVE_TOKEN=<token> flutter test test/api/live_contract_test.dart
///
/// Skipped unless both are set. It only reads, plus writes that leave the shop as it was:
/// renaming the shop to its own name, setting a chat's agent switch to its current value, adding
/// and removing a throwaway alias, an empty product patch, and parse-stock-text (which saves
/// nothing). It sends nothing to customers and doesn't touch stock, orders, questions or
/// onboarding. Don't point it at production anyway.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/api/sellix_api.dart';

void main() {
  final url = Platform.environment['LIVE_API_URL'] ?? '';
  final token = Platform.environment['LIVE_TOKEN'] ?? '';
  final skip = url.isEmpty || token.isEmpty ? 'Set LIVE_API_URL and LIVE_TOKEN to run' : false;

  late SellixApi api;

  setUpAll(() {
    if (skip != false) return;
    HttpOverrides.global = null; // flutter_test blocks real HTTP otherwise.
    api = HttpSellixApi(
      Dio(
        BaseOptions(
          baseUrl: url,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 60),
          contentType: Headers.jsonContentType,
          headers: {'Authorization': 'Bearer $token'},
        ),
      ),
    );
  });

  group('reads', () {
    test('me', () async {
      final me = await api.me();
      expect(me.userId, isNotEmpty);
      expect(me.merchant.id, isNotEmpty);
    }, skip: skip);

    test('shop profile', () async {
      await api.shopProfile();
    }, skip: skip);

    test('onboarding', () async {
      final onboarding = await api.onboarding();
      expect(onboarding.shopName, isNotEmpty);
    }, skip: skip);

    test('today', () async {
      final today = await api.today();
      for (final row in today.stock) {
        expect(row.currency, hasLength(3));
      }
    }, skip: skip);

    test('leftovers', () async {
      final found = await api.leftovers();
      expect(found.yesterdayDate.isBefore(found.businessDate), isTrue);
    }, skip: skip);

    test('upcoming stock', () async {
      await api.upcomingStock();
    }, skip: skip);

    test('catalog: list, get, search', () async {
      final products = await api.products();
      if (products.isEmpty) return;
      final first = products.first;
      expect((await api.product(first.id)).id, first.id);
      await api.products(category: first.category ?? 'none');
      await api.searchCatalog(first.name.substring(0, 1), limit: 5);
    }, skip: skip);

    test('orders: list, every status filter, timeline, payment link', () async {
      final orders = await api.orders(limit: 200);
      await api.orders(status: [OrderStatus.awaitingPayment, OrderStatus.paid], limit: 5);
      await api.orders(paymentStatus: ['paid', 'refunded'], limit: 5);
      for (final order in orders.take(5)) {
        await api.orderTimeline(order.id);
      }
      for (final order in orders.where((o) => o.status == OrderStatus.awaitingPayment).take(1)) {
        try {
          await api.paymentLink(order.id);
        } on ApiException catch (error) {
          // Payments may not be configured here; the error is still a well-formed answer.
          expect(error.statusCode, 400);
        }
      }
    }, skip: skip);

    test('questions, each status', () async {
      for (final status in ['open', 'answered', 'closed']) {
        await api.questions(status: status);
      }
    }, skip: skip);

    test('conversations: list, messages, memory, drafts', () async {
      for (final chat in (await api.conversations()).take(5)) {
        await api.messages(chat.id, limit: 20);
        await api.customerMemory(chat.id);
        await api.drafts(chat.id);
      }
    }, skip: skip);

    test('unconfirmed stories', () async {
      await api.unconfirmedStories();
    }, skip: skip);

    test('simulator chat', () async {
      await api.simulatorChat();
    }, skip: skip);
  });

  group('safe writes', () {
    test('rename the shop to its own name', () async {
      final before = (await api.me()).merchant;
      final after = await api.updateMerchant(name: before.name);
      expect(after.name, before.name);
    }, skip: skip);

    test('parse-stock-text saves nothing', () async {
      final lines = await api.parseStockText('Test item: 2 @ 100');
      expect(lines.single.quantity, 2);
      expect(lines.single.priceMinor, 10000);
    }, skip: skip);

    test('set the agent switch to its current value', () async {
      final chats = await api.conversations();
      if (chats.isEmpty) return;
      final chat = chats.first;
      expect((await api.switchAgent(chat.id, active: chat.agentActive)).active, chat.agentActive);
    }, skip: skip);

    test('an empty product patch, and an alias added and removed', () async {
      final products = await api.products();
      if (products.isEmpty) return;
      final product = products.first;
      final patched = await api.updateProduct(product.id, const ProductUpdate());
      expect(patched.name, product.name);

      final alias = await api.addProductAlias(product.id, 'contract-test-alias');
      try {
        expect(alias.aliasText, 'contract-test-alias');
      } finally {
        await api.deleteProductAlias(product.id, alias.id);
      }
    }, skip: skip);

    test('an error comes back as an ApiException with a status', () async {
      await expectLater(
        api.product('00000000-0000-4000-8000-000000000000'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      await expectLater(
        api.restock('not-a-uuid', 1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422)),
      );
    }, skip: skip);
  });
}
