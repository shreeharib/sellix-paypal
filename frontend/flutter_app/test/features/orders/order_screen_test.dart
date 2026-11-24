import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/orders/order_actions.dart';
import 'package:sellix_merchant/features/orders/order_screen.dart';

import '../../support/fake_sellix_api.dart';
import 'orders_test_support.dart';

FakeSellixApi _withOrder(Order order) {
  final api = FakeSellixApi();
  api.orderList = [order];
  api.timelines = {};
  return api;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Order actions'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows details and the real timeline', (tester) async {
    final api = FakeSellixApi();
    await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
    expect(find.text('Order #2'), findsOneWidget);
    expect(find.text('₹200'), findsWidgets);
    expect(find.text('Item A (Small)'), findsWidgets);
    expect(find.text('customer.one'), findsOneWidget);
    expect(find.text('Placed'), findsOneWidget);
    expect(find.text('Packed'), findsOneWidget);
    expect(find.text('Out for delivery'), findsNothing);
    expect(find.text('Shipped'), findsNothing);
    expect(api.calls, contains('orderTimeline'));
    expect(find.text('Test address'), findsOneWidget);
  });

  testWidgets('an order outside the window says so', (tester) async {
    await pumpScreen(tester, FakeSellixApi(), const OrderScreen('missing'));
    expect(find.text('Order not found'), findsOneWidget);
  });

  testWidgets('an error offers retry', (tester) async {
    final api = FakeSellixApi()..failure = const ApiException('Server is down');
    await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
    expect(find.text('Server is down'), findsOneWidget);
    api.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Order #2'), findsOneWidget);
  });

  testWidgets('mark paid asks first, then calls mark-paid with the chosen method', (tester) async {
    final api = FakeSellixApi();
    await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
    await tester.tap(sxButton('Mark as paid'));
    await tester.pumpAndSettle();
    expect(find.text('Did the ₹100 reach you?'), findsOneWidget);
    expect(find.textContaining('sellix tells customer.one'), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(api.calls, isNot(contains('markOrderPaid')));

    await tester.tap(sxButton('Mark as paid'));
    await tester.pumpAndSettle();
    await tester.tap(sxButton('Yes, I got it'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('markOrderPaid'));
    expect(find.textContaining('Payment confirmed'), findsOneWidget);
    expect(find.text('Accept order'), findsOneWidget);
    await finishSnack(tester);
  });

  testWidgets('a paid order never offers mark paid or the payment link', (tester) async {
    await pumpScreen(tester, FakeSellixApi(), const OrderScreen(FakeIds.orderPaid));
    expect(sxButton('Mark as paid'), findsNothing);
    expect(find.text('Get payment link'), findsNothing);
  });

  group('payment link', () {
    testWidgets('fetches the real link and never claims it was sent', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final api = FakeSellixApi()..answers = const OnboardingAnswers(upiId: 'shop@okbank');
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
      await tester.tap(find.text('Get payment link'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('paymentLink'));
      expect(find.textContaining('upi://pay'), findsOneWidget);
      expect(find.textContaining('does not send this'), findsOneWidget);
      await tester.tap(sxButton('Copy link'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Payment link copied.'), findsOneWidget);
      expect(copied, startsWith('upi://pay'));
      await finishSnack(tester);
    });

    testWidgets('a cooldown shows the server’s own words, and Try again works after it', (tester) async {
      final api = _LinkRefusedApi('Wait 40 seconds before a new payment link.')
        ..answers = const OnboardingAnswers(upiId: 'shop@okbank');
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
      await tester.tap(find.text('Get payment link'));
      await tester.pumpAndSettle();
      expect(find.text('Wait 40 seconds before a new payment link.'), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsNothing);
      expect(find.textContaining('upi://pay'), findsNothing);
      api.refusal = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Wait 40 seconds before a new payment link.'), findsNothing);
      expect(find.textContaining('upi://pay'), findsOneWidget);
    });

    testWidgets('running out of attempts is said as the server says it', (tester) async {
      final api = _LinkRefusedApi('This order has used all its payment attempts.');
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
      await tester.tap(find.text('Get payment link'));
      await tester.pumpAndSettle();
      expect(find.text('This order has used all its payment attempts.'), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsNothing);
    });

    testWidgets('hides a UPI link when the shop has no UPI ID', (tester) async {
      final api = FakeSellixApi()..answers = const OnboardingAnswers();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
      await tester.tap(find.text('Get payment link'));
      await tester.pumpAndSettle();
      expect(find.textContaining('upi://pay'), findsNothing);
      expect(find.textContaining('Add your UPI ID first'), findsOneWidget);
    });
  });

  group('cancel', () {
    testWidgets('unpaid: needs a reason, then calls cancel', (tester) async {
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
      await tester.tap(sxButton('Cancel order'));
      await tester.pumpAndSettle();
      expect(find.text('No money was taken.'), findsOneWidget);
      await tester.tap(sxButton('Cancel order').last);
      await tester.pumpAndSettle();
      expect(find.text('Pick a reason first. It stays on the order.'), findsOneWidget);
      expect(api.calls, isNot(contains('cancelOrder')));

      await tester.tap(find.text('Out of stock'));
      await tester.pumpAndSettle();
      await tester.tap(sxButton('Cancel order').last);
      await tester.pumpAndSettle();
      expect(api.calls, contains('cancelOrder'));
      await finishSnack(tester);
    });

    testWidgets('paid: warns plainly, and cancelling leaves the refund on the list', (tester) async {
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      await _openMenu(tester);
      expect(find.text('This does not refund the customer'), findsOneWidget);
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cancelling does not refund customer.one'), findsOneWidget);
      expect(find.textContaining('does not put it back on sale'), findsOneWidget);
      expect(sxButton('Cancel order'), findsNothing);

      await tester.tap(find.text('Customer changed mind'));
      await tester.pumpAndSettle();
      await tester.tap(sxButton('Cancel, no refund'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('cancelOrder'));
      expect(api.calls, isNot(contains('refundOrder')));
      expect(find.textContaining('was not refunded'), findsOneWidget);
      expect(find.textContaining('Refund due'), findsOneWidget);
      expect(find.text('Not refunded'), findsOneWidget);
      expect(find.text('Refund ₹200'), findsOneWidget);
      await finishSnack(tester);
    });

    testWidgets('paid: Refund instead makes no cancel call', (tester) async {
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      await _openMenu(tester);
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Refund instead'));
      await tester.pumpAndSettle();
      expect(find.text('Refund this order?'), findsOneWidget);
      expect(api.calls, isNot(contains('cancelOrder')));
    });

    testWidgets('finished orders do not offer cancel', (tester) async {
      final api = _withOrder(makeOrder(status: OrderStatus.delivered, method: 'courier'));
      await pumpScreen(tester, api, const OrderScreen('o1'));
      await _openMenu(tester);
      expect(find.text('Cancel order'), findsNothing);
      expect(find.text('Refund'), findsOneWidget);
    });
  });

  group('payment details', () {
    testWidgets('a Razorpay payment shows its method, id with copy, time and fee', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      expect(api.calls, containsAll(['order', 'orderPayments']));
      expect(find.text('UPI, on Razorpay'), findsOneWidget);
      expect(find.text('Razorpay payment ID'), findsOneWidget);
      expect(find.text('pay_TEST2'), findsOneWidget);
      expect(find.text('Razorpay fee'), findsOneWidget);
      expect(find.text('₹4.72'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Copy payment ID'));
      await tester.pumpAndSettle();
      expect(copied, ['pay_TEST2']);
      await finishSnack(tester);
    });

    testWidgets('a test-mode payment says so', (tester) async {
      final api = FakeSellixApi();
      final paid = api.paymentsByOrder[FakeIds.orderPaid]!.payments.single;
      api.paymentsByOrder[FakeIds.orderPaid] = OrderPayments(
        payments: [
          OrderPayment(
            id: paid.id,
            provider: 'razorpay',
            method: 'card',
            status: PaymentStatus.completed,
            amountMinor: paid.amountMinor,
            currency: 'INR',
            providerPaymentId: 'pay_T1',
            paidAt: paid.paidAt,
            createdAt: paid.createdAt,
            testMode: true,
          ),
        ],
        refundable: true,
        refundMode: RefundMode.razorpay,
      );
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      expect(find.textContaining('Test payment', findRichText: true), findsWidgets);
      expect(find.text('Test payment: no real money moved'), findsOneWidget);
    });

    testWidgets('a real payment has no test chip', (tester) async {
      await pumpScreen(tester, FakeSellixApi(), const OrderScreen(FakeIds.orderPaid));
      expect(find.textContaining('Test payment', findRichText: true), findsNothing);
    });

    testWidgets('an unpaid order shows its open link to copy or share', (tester) async {
      final shared = <String>[];
      shareTextOverride = (text) async => shared.add(text);
      addTearDown(() => shareTextOverride = null);
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderUnpaid));
      expect(find.text('https://rzp.io/l/test1'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Share payment link'));
      await tester.pumpAndSettle();
      expect(shared, ['https://rzp.io/l/test1']);
      expect(find.bySemanticsLabel('Copy payment link'), findsOneWidget);
    });

    testWidgets('an order outside the latest list still opens, by id', (tester) async {
      final api = FakeSellixApi();
      api.orderList = [...api.orderList, makeOrder(id: 'old', number: 3, createdAt: DateTime.utc(2025, 1, 1))];
      await pumpScreen(tester, _NotListed(api), const OrderScreen('old'));
      expect(find.text('Order #3'), findsOneWidget);
    });

    testWidgets('a pending refund is shown as pending', (tester) async {
      final api = FakeSellixApi();
      api.paymentsByOrder[FakeIds.orderPaid] = OrderPayments(
        payments: api.paymentsByOrder[FakeIds.orderPaid]!.payments,
        refund: OrderRefund(status: 'pending', amountMinor: 20000, reason: 'Out of stock', createdAt: FakeSellixApi.now),
        refundMode: RefundMode.razorpay,
      );
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      expect(find.textContaining('Refund of ₹200 started'), findsOneWidget);
      expect(find.text('Reason: Out of stock'), findsOneWidget);
      expect(sxButton('Refund ₹200'), findsNothing);
    });
  });

  group('refund', () {
    testWidgets('Razorpay: asks first, says Razorpay sends it, sends the reason, then shows pending', (tester) async {
      final api = _RecordingRefundApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      await tester.tap(sxButton('Refund ₹200'));
      await tester.pumpAndSettle();
      expect(find.text('Refund this order?'), findsOneWidget);
      expect(find.text('Razorpay sends ₹200 back to customer.one (usually 5–7 days).'), findsOneWidget);
      expect(find.textContaining('Part refund'), findsNothing);
      expect(api.calls, isNot(contains('refundOrder')));
      await tester.enterText(find.byType(TextField), 'Out of stock');
      await tester.tap(find.byType(SxToggle).last);
      await tester.pumpAndSettle();
      await tester.tap(sxButton('Refund'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('refundOrder'));
      expect(api.sent, [('Out of stock', false)]);
      expect(find.textContaining('Refund started. Razorpay is sending ₹200'), findsOneWidget);
      expect(find.textContaining('Refund of ₹200 started'), findsOneWidget);
      await finishSnack(tester);
    });

    testWidgets('UPI paid by hand: the merchant returns it and sellix records it', (tester) async {
      final api = _withOrder(makeOrder());
      await pumpScreen(tester, api, const OrderScreen('o1'));
      expect(find.text('By you, by hand'), findsOneWidget);
      await _openMenu(tester);
      expect(find.text('You send it back; sellix records it'), findsOneWidget);
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      expect(find.text('Record a refund?'), findsOneWidget);
      expect(find.text('You return the money to customer.one yourself; sellix records the refund.'), findsOneWidget);
      await tester.tap(sxButton('Record refund'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refund of ₹500 recorded'), findsOneWidget);
      expect(api.orderList.single.status, OrderStatus.refunded);
      await finishSnack(tester);
    });

    testWidgets('a refused refund keeps the sheet open and says no money moved', (tester) async {
      final api = _FailingRefundApi()..orderList = [makeOrder()];
      await pumpScreen(tester, api, const OrderScreen('o1'));
      await _openMenu(tester);
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      await tester.tap(sxButton('Record refund'));
      await tester.pumpAndSettle();
      expect(find.text('Record a refund?'), findsOneWidget);
      expect(find.text('Razorpay refused: not enough balance in your Razorpay account. No money moved.'), findsOneWidget);
    });

    testWidgets('stock choice is hidden where the server would ignore it', (tester) async {
      final api = _withOrder(makeOrder(status: OrderStatus.ready));
      await pumpScreen(tester, api, const OrderScreen('o1'));
      await _openMenu(tester);
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      expect(find.text('Put items back in stock'), findsNothing);
      expect(find.textContaining('Stock does not go back'), findsOneWidget);
    });
  });

  testWidgets('complete goes through the checked endpoint, and Undo restores', (tester) async {
    final api = _withOrder(makeOrder(status: OrderStatus.ready));
    await pumpScreen(tester, api, const OrderScreen('o1'));
    await tester.tap(find.text('Mark as picked up'));
    await tester.pumpAndSettle();
    await tester.tap(sxButton('Mark as picked up').last);
    await tester.pumpAndSettle();
    expect(api.calls, contains('completeOrder'));
    expect(api.calls, isNot(contains('updateOrderStatus')));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('updateOrderStatus'));
    expect(api.orderList.single.status, OrderStatus.ready);
    expect(find.textContaining('Undone'), findsOneWidget);
    await finishSnack(tester);
  });

  testWidgets('accepting offers no Undo, and go back is not in the menu', (tester) async {
    final api = _withOrder(makeOrder());
    await pumpScreen(tester, api, const OrderScreen('o1'));
    await _openMenu(tester);
    expect(find.text('Go back one stage'), findsNothing);
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept order'));
    await tester.pumpAndSettle();
    await tester.tap(sxButton('Accept order').last);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    await finishSnack(tester);
  });

  testWidgets('a status failure stays in the sheet and reports nothing as done', (tester) async {
    final api = _withOrder(makeOrder());
    await pumpScreen(tester, api, const OrderScreen('o1'));
    await tester.tap(find.text('Accept order'));
    await tester.pumpAndSettle();
    api.failure = const ApiException('Could not save');
    await tester.tap(sxButton('Accept order').last);
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.textContaining('Order accepted'), findsNothing);
    expect(api.orderList.single.status, OrderStatus.paid);
  });

  test('refund errors never show server ids, and a 400 says no money moved', () {
    final text = refundErrorText(
      const ApiException('Refund failed for order 123e4567-e89b-12d3', statusCode: 400),
    );
    expect(text, 'The refund didn’t go through. No money moved.');
    expect(refundErrorText(const ApiException('Order is not paid', statusCode: 400)), 'Order is not paid. No money moved.');
    expect(
      refundErrorText(const ApiException("Can't reach sellix. Check your connection.")),
      "Can't reach sellix. Check your connection.",
    );
  });

  test('refund wording follows the refund mode', () {
    expect(refundWords(RefundMode.razorpay, '₹180', 'Asha'), 'Razorpay sends ₹180 back to Asha (usually 5–7 days).');
    expect(refundWords(RefundMode.manual, '₹180', 'Asha'), 'You return the money to Asha yourself; sellix records the refund.');
  });
}

/// The payment link route answering 409 with a reason, as the backend does for a cooldown.
class _LinkRefusedApi extends FakeSellixApi {
  _LinkRefusedApi(this.refusal);

  String? refusal;

  @override
  Future<PaymentLinkResponse> paymentLink(String orderId) {
    final reason = refusal;
    if (reason != null) {
      calls.add('paymentLink');
      throw ApiException(reason, statusCode: 409);
    }
    return super.paymentLink(orderId);
  }
}

class _FailingRefundApi extends FakeSellixApi {
  @override
  Future<RefundResponse> refundOrder(String orderId, {String? reason, bool restock = true}) async {
    calls.add('refundOrder');
    throw const ApiException('Razorpay refused: not enough balance in your Razorpay account', statusCode: 400);
  }
}

/// Keeps the reason and restock choice each refund was sent with.
class _RecordingRefundApi extends FakeSellixApi {
  final sent = <(String?, bool)>[];

  @override
  Future<RefundResponse> refundOrder(String orderId, {String? reason, bool restock = true}) {
    sent.add((reason, restock));
    return super.refundOrder(orderId, reason: reason, restock: restock);
  }
}

/// The latest-orders list leaves this order out, as for an old order.
class _NotListed extends FakeSellixApi {
  _NotListed(FakeSellixApi from) {
    orderList = from.orderList;
  }

  @override
  Future<List<Order>> orders({List<String>? status, List<String>? paymentStatus, int? limit, DateTime? before}) async {
    final all = await super.orders(status: status, paymentStatus: paymentStatus, limit: limit, before: before);
    return all.where((o) => o.id != 'old').toList();
  }
}
