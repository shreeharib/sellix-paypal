import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
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

  group('refund', () {
    testWidgets('asks first, then calls refund with the restock choice', (tester) async {
      final api = FakeSellixApi();
      await pumpScreen(tester, api, const OrderScreen(FakeIds.orderPaid));
      await _openMenu(tester);
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      expect(find.text('Refund this order?'), findsOneWidget);
      expect(find.textContaining('Not available yet'), findsOneWidget);
      expect(api.calls, isNot(contains('refundOrder')));
      await tester.tap(sxButton('Refund'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('refundOrder'));
      expect(find.textContaining('₹200 refund sent'), findsOneWidget);
      await finishSnack(tester);
    });

    testWidgets('a UPI order: the sheet stays open and says no money moved', (tester) async {
      final api = _FailingRefundApi()..orderList = [makeOrder()];
      await pumpScreen(tester, api, const OrderScreen('o1'));
      await _openMenu(tester);
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      await tester.tap(sxButton('Refund'));
      await tester.pumpAndSettle();
      expect(find.text('Refund this order?'), findsOneWidget);
      expect(find.textContaining('No money moved'), findsOneWidget);
      expect(find.textContaining('00000000'), findsNothing);
    });

    testWidgets('a pending PayPal answer is not reported as sent', (tester) async {
      final api = _PendingRefundApi()..orderList = [makeOrder()];
      await pumpScreen(tester, api, const OrderScreen('o1'));
      await _openMenu(tester);
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      await tester.tap(sxButton('Refund'));
      await tester.pumpAndSettle();
      expect(find.textContaining('has not confirmed'), findsOneWidget);
      await finishSnack(tester);
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

  test('refund errors never show server ids', () {
    final text = refundErrorText(
      const ApiException(
        'No completed PayPal payment capture found for order 123e4567',
        statusCode: 400,
      ),
    );
    expect(text, contains('No money moved'));
    expect(text, isNot(contains('123e4567')));
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
    throw const ApiException(
      'No completed PayPal payment capture found for order 00000000-0000',
      statusCode: 400,
    );
  }
}

class _PendingRefundApi extends FakeSellixApi {
  @override
  Future<RefundResponse> refundOrder(String orderId, {String? reason, bool restock = true}) async {
    calls.add('refundOrder');
    return RefundResponse(
      orderId: orderId,
      refundId: '',
      amountMinor: 50000,
      currency: 'INR',
      status: 'PENDING',
    );
  }
}
