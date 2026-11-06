import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/features/orders/customers_logic.dart';
import 'package:sellix_merchant/features/orders/order_logic.dart';

import '../../support/fake_sellix_api.dart';
import 'orders_test_support.dart';

void main() {
  group('sensible next steps', () {
    test('nothing moves before payment, whatever the status says', () {
      for (final status in [
        OrderStatus.awaitingPayment,
        OrderStatus.draft,
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.ready,
      ]) {
        final order = makeOrder(status: status, paymentStatus: 'unpaid');
        expect(nextStepOf(order), isNull, reason: status);
      }
    });

    test('closed orders have no next step', () {
      for (final status in [OrderStatus.cancelled, OrderStatus.expired, OrderStatus.refunded]) {
        expect(nextStepOf(makeOrder(status: status)), isNull, reason: status);
      }
    });

    test('pickup path: paid, confirmed, ready, then the checked complete call', () {
      expect(nextStepOf(makeOrder())!.targetStatus, OrderStatus.confirmed);
      expect(
        nextStepOf(makeOrder(status: OrderStatus.confirmed))!.targetStatus,
        OrderStatus.ready,
      );
      final last = nextStepOf(makeOrder(status: OrderStatus.ready))!;
      expect(last.targetStatus, OrderStatus.completed);
      expect(last.usesComplete, isTrue);
      expect(nextStepOf(makeOrder(status: OrderStatus.completed)), isNull);
    });

    test('delivery path ends at delivered, with no fake out-for-delivery stage', () {
      final ready = makeOrder(status: OrderStatus.ready, method: 'local_delivery');
      expect(nextStepOf(ready)!.targetStatus, OrderStatus.delivered);
      expect(nextStepOf(ready)!.usesComplete, isFalse);
      expect(stagesOf(OrderMethod.localDelivery).map((s) => s.label), [
        'Placed',
        'Accepted',
        'Packed',
        'Delivered',
      ]);
      expect(nextStepOf(makeOrder(status: OrderStatus.delivered, method: 'courier')), isNull);
    });

    test('mark paid only while waiting for money, never after a stage moved', () {
      expect(canMarkPaid(makeOrder(status: OrderStatus.awaitingPayment, paymentStatus: 'unpaid')), isTrue);
      expect(canMarkPaid(makeOrder()), isFalse);
      expect(canMarkPaid(makeOrder(status: OrderStatus.confirmed, paymentStatus: 'unpaid')), isFalse);
      expect(canMarkPaid(makeOrder(status: OrderStatus.expired, paymentStatus: 'unpaid')), isFalse);
      expect(canMarkPaid(makeOrder(status: OrderStatus.cancelled, paymentStatus: 'unpaid')), isFalse);
    });

    test('cancel is not offered once finished or closed, though the server allows delivered', () {
      expect(canCancel(makeOrder()), isTrue);
      expect(canCancel(makeOrder(status: OrderStatus.delivered)), isFalse);
      expect(canCancel(makeOrder(status: OrderStatus.completed)), isFalse);
      expect(canCancel(makeOrder(status: OrderStatus.expired, paymentStatus: 'unpaid')), isFalse);
    });

    test('going back never lands on paid, which re-counts customer totals', () {
      expect(previousStatusOf(makeOrder()), isNull);
      expect(previousStatusOf(makeOrder(status: OrderStatus.confirmed)), isNull);
      expect(nextStepOf(makeOrder())!.undoStatus, isNull);
      expect(previousStatusOf(makeOrder(status: OrderStatus.ready)), OrderStatus.confirmed);
    });

    test('a finished order goes back only shortly after', () {
      final now = DateTime.utc(2026, 1, 15, 12);
      final done = makeOrder(status: OrderStatus.delivered, method: 'courier');
      expect(
        previousStatusOf(done, lastChange: now.subtract(const Duration(minutes: 5)), now: now),
        OrderStatus.ready,
      );
      expect(
        previousStatusOf(done, lastChange: now.subtract(const Duration(hours: 1)), now: now),
        isNull,
      );
      expect(previousStatusOf(done, now: now), isNull);
    });

    test('refund needs a paid order, and restock only where the server does it', () {
      expect(canRefund(makeOrder(status: OrderStatus.awaitingPayment, paymentStatus: 'unpaid')), isFalse);
      expect(canRefund(makeOrder(status: OrderStatus.refunded, paymentStatus: 'refunded')), isFalse);
      expect(refundCanRestock(makeOrder(status: OrderStatus.ready)), isFalse);
      expect(refundCanRestock(makeOrder(status: OrderStatus.cancelled)), isFalse);
      expect(refundCanRestock(makeOrder(status: OrderStatus.confirmed)), isTrue);
    });
  });

  group('tabs', () {
    test('every order is in exactly one tab', () {
      final orders = [
        for (final (i, (status, pay)) in const [
          (OrderStatus.awaitingPayment, 'unpaid'),
          (OrderStatus.paid, 'paid'),
          (OrderStatus.confirmed, 'paid'),
          (OrderStatus.ready, 'paid'),
          (OrderStatus.delivered, 'paid'),
          (OrderStatus.completed, 'paid'),
          (OrderStatus.cancelled, 'unpaid'),
          (OrderStatus.cancelled, 'paid'),
          (OrderStatus.expired, 'unpaid'),
          (OrderStatus.refunded, 'refunded'),
        ].indexed)
          makeOrder(id: 'o$i', number: i, status: status, paymentStatus: pay),
      ];
      final counted = [OrderTab.todo, OrderTab.moving, OrderTab.waiting, OrderTab.done]
          .map((tab) => ordersInTab(tab, orders).length)
          .reduce((a, b) => a + b);
      expect(counted, orders.length);
    });

    test('a pickup that is ready waits on the customer; a delivery that is ready does not', () {
      expect(tabOf(makeOrder(status: OrderStatus.ready)), OrderTab.moving);
      expect(tabOf(makeOrder(status: OrderStatus.ready, method: 'courier')), OrderTab.todo);
    });

    test('a cancelled order that still holds the money is on the to-do list, first', () {
      final due = makeOrder(id: 'due', status: OrderStatus.cancelled);
      expect(isRefundDue(due), isTrue);
      final list = ordersToAct([makeOrder(id: 'new'), due]);
      expect(list.first.id, 'due');
    });
  });

  test('sales leave out cancelled and refunded money and never add currencies', () {
    final day = FakeSellixApi.businessDate;
    final at = DateTime(2026, 1, 15, 10);
    final sales = salesFor(
      [
        makeOrder(id: 'a', totalMinor: 1000, paidAt: at),
        makeOrder(id: 'b', totalMinor: 700, currency: 'USD', paidAt: at),
        makeOrder(id: 'c', totalMinor: 9000, status: OrderStatus.cancelled, paidAt: at),
        makeOrder(id: 'd', totalMinor: 9000, status: OrderStatus.refunded, paymentStatus: 'refunded', paidAt: at),
      ],
      SalesPeriod.day,
      day,
    );
    expect(sales.count, 2);
    expect(sales.mainCurrency, 'INR');
    expect(sales.mainMinor, 1000);
    expect(sales.others, ['US\$7.00']);
  });

  group('customers', () {
    Conversation conversation(String id, String handle) => Conversation(
      id: id,
      channel: 'instagram',
      customerHandle: handle,
      agentActive: true,
      agentPausedReason: null,
      lastMessageSender: null,
      lastMessageBody: null,
      lastMessageAt: null,
    );

    test('join on conversation id, count only money kept, keep currencies apart', () {
      final list = customersFrom(
        [conversation('a', 'alpha'), conversation('b', 'beta')],
        [
          makeOrder(id: '1', conversationId: 'a', totalMinor: 1000),
          makeOrder(id: '2', conversationId: 'a', totalMinor: 700, currency: 'USD'),
          makeOrder(id: '3', conversationId: 'a', totalMinor: 5000, status: OrderStatus.cancelled),
          makeOrder(id: '4', conversationId: 'b', totalMinor: 3000),
          makeOrder(id: '5', conversationId: null, totalMinor: 99999),
        ],
      );
      expect(list.map((c) => c.handle), ['beta', 'alpha']);
      final alpha = list.last;
      expect(alpha.orders, hasLength(3));
      expect(alpha.paidCount, 2);
      expect(alpha.spentText, '₹10 + US\$7.00');
    });

    test('stats round whole numbers and only average one currency', () {
      final list = customersFrom(
        [conversation('a', 'alpha'), conversation('b', 'beta'), conversation('c', 'gamma')],
        [
          makeOrder(id: '1', conversationId: 'a', totalMinor: 1000),
          makeOrder(id: '2', conversationId: 'a', totalMinor: 2000),
          makeOrder(id: '3', conversationId: 'b', totalMinor: 3000),
          makeOrder(id: '4', conversationId: 'b', totalMinor: 700, currency: 'USD'),
        ],
      );
      final stats = customerStatsOf(list);
      expect(stats.buyers, 2);
      expect(stats.backPercent, 100);
      expect(stats.perOrder, '₹20');
    });

    test('filters and search', () {
      final one = customersFrom([conversation('a', 'Alpha')], [makeOrder(conversationId: 'a')]).first;
      expect(matchesCustomer(one, CustomerFilter.fresh, ''), isTrue);
      expect(matchesCustomer(one, CustomerFilter.repeat, ''), isFalse);
      expect(matchesCustomer(one, CustomerFilter.all, 'alp'), isTrue);
      expect(matchesCustomer(one, CustomerFilter.all, 'zzz'), isFalse);
    });
  });
}
