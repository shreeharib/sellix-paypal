import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/api/sellix_api.dart';

/// Records each request and answers with whatever the test queued.
class _Adapter implements HttpClientAdapter {
  RequestOptions? last;
  int statusCode = 200;
  String responseBody = '{}';

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? _) async {
    last = options;
    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late HttpSellixApi api;

  setUp(() {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test', contentType: Headers.jsonContentType))
      ..httpClientAdapter = adapter;
    api = HttpSellixApi(dio);
  });

  /// Every SellixApi method against its route: "METHOD path". The parsers run on `{}` or `[]`, so
  /// they may throw on missing fields; only the request matters here.
  final routes = <String, Future<Object?> Function(SellixApi)>{
    'GET /v1/me': (a) => a.me(),
    'PATCH /v1/merchant': (a) => a.updateMerchant(name: 'x'),
    'GET /v1/shop-profile': (a) => a.shopProfile(),
    'PUT /v1/shop-profile': (a) => a.saveShopProfile('x'),
    'GET /v1/onboarding': (a) => a.onboarding(),
    'PUT /v1/onboarding': (a) =>
        a.saveOnboarding(shopName: 'x', answers: const OnboardingAnswers()),
    'GET /v1/today': (a) => a.today(),
    'PUT /v1/today/stock': (a) => a.setOpeningStock(const []),
    'POST /v1/today/restock': (a) => a.restock('v', 1),
    'POST /v1/today/sold-out': (a) => a.markSoldOut('v'),
    'POST /v1/today/counter-sale': (a) => a.recordCounterSale('v', 1),
    'POST /v1/today/parse-stock-text': (a) => a.parseStockText('x'),
    'GET /v1/today/leftovers': (a) => a.leftovers(),
    'POST /v1/today/rollover': (a) => a.applyRollover(const []),
    'POST /v1/today/rollover/auto': (a) => a.autoRollover(),
    'GET /v1/stock/upcoming': (a) => a.upcomingStock(),
    'PUT /v1/stock/upcoming': (a) => a.setUpcomingStock(DateTime(2026), DateTime(2026), const []),
    'GET /v1/products/search': (a) => a.searchCatalog('x'),
    'GET /v1/products': (a) => a.products(),
    'GET /v1/products/p1': (a) => a.product('p1'),
    'PATCH /v1/products/p1': (a) => a.updateProduct('p1', const ProductUpdate(name: 'x')),
    'POST /v1/products/p1/aliases': (a) => a.addProductAlias('p1', 'x'),
    'DELETE /v1/products/p1/aliases/a1': (a) => a.deleteProductAlias('p1', 'a1'),
    'GET /v1/product-schema': (a) => a.productSchema(),
    'GET /v1/shop-types': (a) => a.shopTypes(),
    'GET /v1/orders': (a) => a.orders(),
    'POST /v1/orders/o1/refund': (a) => a.refundOrder('o1'),
    'POST /v1/orders/o1/invoice': (a) => a.createInvoice('o1'),
    'POST /v1/orders/o1/mark-paid': (a) => a.markOrderPaid('o1'),
    'POST /v1/orders/o1/complete': (a) => a.completeOrder('o1'),
    'POST /v1/orders/o1/cancel': (a) => a.cancelOrder('o1'),
    'GET /v1/orders/o1/payment-link': (a) => a.paymentLink('o1'),
    'PATCH /v1/orders/o1/status': (a) => a.updateOrderStatus('o1', 'ready'),
    'GET /v1/orders/o1/timeline': (a) => a.orderTimeline('o1'),
    'GET /v1/questions': (a) => a.questions(),
    'POST /v1/questions/q1/answer': (a) => a.answerQuestion('q1', 'x'),
    'POST /v1/questions/q1/close': (a) => a.closeQuestion('q1'),
    'GET /v1/conversations': (a) => a.conversations(),
    'GET /v1/conversations/c1/messages': (a) => a.messages('c1'),
    'PUT /v1/conversations/c1/agent': (a) => a.switchAgent('c1', active: true),
    'GET /v1/conversations/c1/memory': (a) => a.customerMemory('c1'),
    'DELETE /v1/conversations/c1/memory/k1': (a) => a.forgetCustomerFact('c1', 'k1'),
    'GET /v1/conversations/c1/drafts': (a) => a.drafts('c1'),
    'POST /v1/conversations/c1/drafts/m1/approve': (a) => a.approveDraft('c1', 'm1'),
    'POST /v1/conversations/c1/drafts/m1/discard': (a) => a.discardDraft('c1', 'm1'),
    'GET /v1/stories/unconfirmed': (a) => a.unconfirmedStories(),
    'POST /v1/stories/s1/confirm': (a) => a.confirmStory('s1', const []),
    'PUT /v1/stories/posts/p1': (a) => a.linkPost('p1', 'x'),
    'PUT /v1/stories/menu-image': (a) => a.setMenuImage(null),
    'POST /v1/simulator/messages': (a) => a.simulatorSend(text: 'x'),
    'GET /v1/simulator/messages': (a) => a.simulatorChat(),
    'POST /v1/auth/logout': (a) => a.logout(),
  };

  test('every method calls its route', () async {
    for (final MapEntry(key: route, value: call) in routes.entries) {
      adapter.last = null;
      // Only array-returning routes care; an object body for those would fail the Dio cast.
      adapter.responseBody = _returnsList(route) ? '[]' : 'null';
      try {
        await call(api);
      } on TypeError {
        // Parsing an empty body: expected here, and covered by parsing_test.dart.
      }
      final request = adapter.last;
      expect(request, isNotNull, reason: route);
      expect('${request!.method} ${request.uri.path}', route);
    }
  });

  test('orders sends repeated query keys, as FastAPI expects', () async {
    adapter.responseBody = '[]';
    await api.orders(status: ['paid', 'ready'], paymentStatus: ['paid'], limit: 20);
    expect(adapter.last!.uri.query, 'status=paid&status=ready&payment_status=paid&limit=20');
  });

  test('a 409 on the payment link keeps the server’s detail as the message', () async {
    adapter
      ..statusCode = 409
      ..responseBody = '{"detail": "Wait 40 seconds before a new payment link."}';
    await expectLater(
      api.paymentLink('o1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', 'Wait 40 seconds before a new payment link.')
            .having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
    adapter.responseBody = '{"detail": "This order has used all its payment attempts."}';
    await expectLater(
      api.paymentLink('o1'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'This order has used all its payment attempts.')),
    );
  });

  test('orders leaves out empty filters', () async {
    adapter.responseBody = '[]';
    await api.orders(status: const []);
    expect(adapter.last!.uri.query, isEmpty);
  });

  test('bodies use the backend field names', () async {
    adapter.responseBody = '{}';
    Future<void> ignoreParse(Future<Object?> call) async {
      try {
        await call;
      } on TypeError {
        // See above.
      }
    }

    await ignoreParse(api.answerQuestion('q', 'Yes', always: true));
    expect(adapter.last!.data, {'answer': 'Yes', 'always': true});

    await ignoreParse(api.markOrderPaid('o', method: 'cash', referenceId: 'R1'));
    expect(adapter.last!.data, {'method': 'cash', 'reference_id': 'R1'});

    adapter.responseBody = '[]';
    await ignoreParse(
      api.setUpcomingStock(DateTime(2026, 11, 6), DateTime(2026, 11, 7), const [
        StockLine(product: 'Cake', priceMinor: 100, quantity: 2, stockMode: 'daily'),
      ]),
    );
    expect(adapter.last!.data, {
      'from_date': '2026-11-06',
      'to_date': '2026-11-07',
      'lines': [
        {
          'product': 'Cake',
          'variant': null,
          'price_minor': 100,
          'currency': 'INR',
          'quantity': 2,
          'stock_mode': 'daily',
        },
      ],
    });
  });

  test('a memory key is escaped in the path', () async {
    adapter.responseBody = 'null';
    await api.forgetCustomerFact('c', 'likes/cake');
    expect(adapter.last!.uri.path, '/v1/conversations/c/memory/likes%2Fcake');
  });

  test('a null shop profile is null, not an error', () async {
    adapter.responseBody = 'null';
    expect(await api.shopProfile(), isNull);
  });

  group('errors', () {
    Future<ApiException> failure() async {
      try {
        await api.today();
      } on ApiException catch (error) {
        return error;
      }
      fail('Expected an ApiException');
    }

    test('a router error shows its detail', () async {
      adapter
        ..statusCode = 409
        ..responseBody = jsonEncode({'detail': 'Only 2 left'});
      final error = await failure();
      expect(error.message, 'Only 2 left');
      expect(error.statusCode, 409);
    });

    test('a request validation error names the field', () async {
      adapter
        ..statusCode = 422
        ..responseBody = jsonEncode({
          'detail': [
            {
              'type': 'greater_than',
              'loc': ['body', 'quantity'],
              'msg': 'Input should be greater than 0',
              'input': 0,
            },
          ],
        });
      final error = await failure();
      expect(error.message, 'Please check quantity: Input should be greater than 0');
      expect(error.statusCode, 422);
    });

    test('an unexpected body falls back to a safe message', () async {
      adapter
        ..statusCode = 500
        ..responseBody = '"Internal Server Error"';
      final error = await failure();
      expect(error.message, 'Something went wrong. Please try again.');
      expect(error.statusCode, 500);
    });

    test('401 is flagged', () async {
      adapter
        ..statusCode = 401
        ..responseBody = jsonEncode({'detail': 'Sign in required'});
      expect((await failure()).isUnauthorized, isTrue);
    });
  });
}

bool _returnsList(String route) => const {
  'GET /v1/stock/upcoming',
  'PUT /v1/stock/upcoming',
  'GET /v1/products',
  'GET /v1/shop-types',
  'GET /v1/orders',
  'GET /v1/orders/o1/timeline',
  'GET /v1/questions',
  'GET /v1/conversations',
  'GET /v1/conversations/c1/messages',
  'GET /v1/conversations/c1/memory',
  'GET /v1/conversations/c1/drafts',
  'GET /v1/stories/unconfirmed',
}.contains(route);
