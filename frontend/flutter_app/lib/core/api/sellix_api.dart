import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'models.dart';

/// The merchant API used by every screen (backend/app/api/v1). Sign-in lives in `auth/auth_api.dart`.
///
/// Every method throws [ApiException] on failure; show its `message` to the merchant.
abstract interface class SellixApi {
  // Shop
  Future<Me> me();
  Future<Merchant> updateMerchant({String? name, String? timezone, bool? agentEnabled});

  /// Null until the shop has a profile.
  Future<ShopProfile?> shopProfile();
  Future<ShopProfile> saveShopProfile(String contentMd);

  // Onboarding
  Future<Onboarding> onboarding();

  /// Saves the answers (also after each step) and regenerates the shop profile.
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  });

  // Today
  Future<Today> today();

  /// The morning stock update; a later update the same day replaces the opening counts.
  Future<Today> setOpeningStock(List<StockLine> lines);
  Future<Today> restock(String variantId, int quantity);
  Future<Today> markSoldOut(String variantId);
  Future<CounterSaleResponse> recordCounterSale(String variantId, int quantity);

  /// Free text to stock lines, one per line, either `quantity product price` or
  /// `product: quantity @ price`. Saves nothing. Unreadable text fails with a 422 whose message
  /// says which line.
  Future<List<StockLine>> parseStockText(String text, {String defaultCurrency = 'INR'});
  Future<YesterdayLeftoversResponse> leftovers();
  Future<RolloverResponse> applyRollover(List<RolloverItem> items);
  Future<RolloverResponse> autoRollover();

  // Upcoming stock
  Future<List<UpcomingDay>> upcomingStock();

  /// The same quantity each day from [from] to [to], up to 30 days ahead; a later call replaces it.
  ///
  /// [oneDayOnly] (a single day): items this call creates are sold on that day alone and stay off
  /// every other day's stock, today's too. [lastOrderDate] is the last day to order them.
  Future<List<UpcomingDay>> setUpcomingStock(
    DateTime from,
    DateTime to,
    List<StockLine> lines, {
    bool oneDayOnly = false,
    DateTime? lastOrderDate,
  });

  // Catalog
  Future<CatalogSearchResponse> searchCatalog(String query, {int? limit});
  Future<List<ProductDetail>> products({String? category});
  Future<ProductDetail> product(String productId);
  Future<ProductDetail> updateProduct(String productId, ProductUpdate update);
  Future<ProductAliasDetail> addProductAlias(String productId, String aliasText);
  Future<void> deleteProductAlias(String productId, String aliasId);

  // Orders
  /// Filters are ORed within a list. [paymentStatus] accepts "pending", "paid",
  /// "partially_refunded", "refunded" and "failed" only: the backend refuses "unpaid", so filter
  /// unpaid orders with `status: ['awaiting_payment']`. [limit] is 1 to 200 (backend default 50).
  Future<List<Order>> orders({List<String>? status, List<String>? paymentStatus, int? limit});

  /// PayPal payments only; anything else fails with a message.
  Future<RefundResponse> refundOrder(String orderId, {String? reason, bool restock = true});
  Future<CreateInvoiceResponse> createInvoice(
    String orderId, {
    String? customerName,
    String? customerEmail,
  });

  /// [method] is "upi", "cash" or "card".
  Future<Order> markOrderPaid(String orderId, {String method = 'upi', String? referenceId});
  Future<Order> completeOrder(String orderId);
  Future<Order> cancelOrder(String orderId, {String? reason});
  Future<PaymentLinkResponse> paymentLink(String orderId);

  /// [status] is one of [OrderStatus]. The backend doesn't check the transition, so offer only
  /// sensible next steps.
  Future<Order> updateOrderStatus(String orderId, String status, {String? comment});
  Future<List<OrderTimelineEvent>> orderTimeline(String orderId);

  // Ask me
  /// [status] is "open", "answered" or "closed". The backend has no "all": leaving it out means open.
  Future<List<Question>> questions({String status = 'open'});

  /// [always] makes the agent give this answer to the same question from now on.
  Future<Question> answerQuestion(String questionId, String answer, {bool always = false});
  Future<Question> closeQuestion(String questionId);

  // Chats
  Future<List<Conversation>> conversations();

  /// [limit] is 1 to 500 (backend default 100).
  Future<List<ChatMessage>> messages(String conversationId, {int? limit});
  Future<AgentSwitch> switchAgent(String conversationId, {required bool active});
  Future<List<MemoryFact>> customerMemory(String conversationId);
  Future<void> forgetCustomerFact(String conversationId, String key);
  Future<List<ChatMessage>> drafts(String conversationId);

  /// Sends the draft to the customer, as edited when [text] is given.
  Future<void> approveDraft(String conversationId, String messageId, {String? text});
  Future<void> discardDraft(String conversationId, String messageId);

  // Stories
  Future<List<Story>> unconfirmedStories();

  /// [itemIds] are short item refs: see [itemRefOf].
  Future<void> confirmStory(String storyId, List<String> itemIds);
  Future<void> linkPost(String productId, String igMediaId);

  /// Null clears the menu photo.
  Future<void> setMenuImage(String? url);

  // Simulator
  /// Writes to the shop as a customer; the assistant has answered when this returns (slow: it runs
  /// the model). Nothing leaves sellix.
  Future<SimulatorChat> simulatorSend({
    String text = '',
    String? quickReply,
    String customer = 'tester',
  });
  Future<SimulatorChat> simulatorChat({String customer = 'tester'});

  // Session
  Future<void> logout();
}

class HttpSellixApi implements SellixApi {
  HttpSellixApi(this._dio);

  final Dio _dio;

  // Shop

  @override
  Future<Me> me() async => Me.fromJson(await _object('GET', '/v1/me'));

  @override
  Future<Merchant> updateMerchant({String? name, String? timezone, bool? agentEnabled}) async =>
      Merchant.fromJson(
        await _object(
          'PATCH',
          '/v1/merchant',
          body: MerchantUpdate(
            name: name,
            timezone: timezone,
            agentEnabled: agentEnabled,
          ).toJson(),
        ),
      );

  @override
  Future<ShopProfile?> shopProfile() async {
    final data = await _request<Map<String, dynamic>>('GET', '/v1/shop-profile');
    return data == null ? null : ShopProfile.fromJson(data);
  }

  @override
  Future<ShopProfile> saveShopProfile(String contentMd) async => ShopProfile.fromJson(
    await _object(
      'PUT',
      '/v1/shop-profile',
      body: ShopProfileUpdate(contentMd: contentMd).toJson(),
    ),
  );

  // Onboarding

  @override
  Future<Onboarding> onboarding() async => Onboarding.fromJson(await _object('GET', '/v1/onboarding'));

  @override
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  }) async => Onboarding.fromJson(
    await _object(
      'PUT',
      '/v1/onboarding',
      body: OnboardingUpdate(shopName: shopName, answers: answers, complete: complete).toJson(),
    ),
  );

  // Today

  @override
  Future<Today> today() async => Today.fromJson(await _object('GET', '/v1/today'));

  @override
  Future<Today> setOpeningStock(List<StockLine> lines) async => Today.fromJson(
    await _object('PUT', '/v1/today/stock', body: StockUpdate(lines: lines).toJson()),
  );

  @override
  Future<Today> restock(String variantId, int quantity) async => Today.fromJson(
    await _object(
      'POST',
      '/v1/today/restock',
      body: RestockRequest(variantId: variantId, quantity: quantity).toJson(),
    ),
  );

  @override
  Future<Today> markSoldOut(String variantId) async => Today.fromJson(
    await _object('POST', '/v1/today/sold-out', body: SoldOutRequest(variantId: variantId).toJson()),
  );

  @override
  Future<CounterSaleResponse> recordCounterSale(String variantId, int quantity) async =>
      CounterSaleResponse.fromJson(
        await _object(
          'POST',
          '/v1/today/counter-sale',
          body: CounterSaleRequest(variantId: variantId, quantity: quantity).toJson(),
        ),
      );

  @override
  Future<List<StockLine>> parseStockText(String text, {String defaultCurrency = 'INR'}) async {
    final parsed = OpeningStock.fromJson(
      await _object(
        'POST',
        '/v1/today/parse-stock-text',
        body: ParseStockTextRequest(text: text, defaultCurrency: defaultCurrency).toJson(),
      ),
    );
    return parsed.lines;
  }

  @override
  Future<YesterdayLeftoversResponse> leftovers() async =>
      YesterdayLeftoversResponse.fromJson(await _object('GET', '/v1/today/leftovers'));

  @override
  Future<RolloverResponse> applyRollover(List<RolloverItem> items) async =>
      RolloverResponse.fromJson(
        await _object('POST', '/v1/today/rollover', body: RolloverRequest(items: items).toJson()),
      );

  @override
  Future<RolloverResponse> autoRollover() async =>
      RolloverResponse.fromJson(await _object('POST', '/v1/today/rollover/auto'));

  // Upcoming stock

  @override
  Future<List<UpcomingDay>> upcomingStock() async =>
      _parseList(await _array('GET', '/v1/stock/upcoming'), UpcomingDay.fromJson);

  @override
  Future<List<UpcomingDay>> setUpcomingStock(
    DateTime from,
    DateTime to,
    List<StockLine> lines, {
    bool oneDayOnly = false,
    DateTime? lastOrderDate,
  }) async => _parseList(
    await _array(
      'PUT',
      '/v1/stock/upcoming',
      body: UpcomingStock(
        fromDate: from,
        toDate: to,
        lines: lines,
        oneDayOnly: oneDayOnly,
        lastOrderDate: lastOrderDate,
      ).toJson(),
    ),
    UpcomingDay.fromJson,
  );

  // Catalog

  @override
  Future<CatalogSearchResponse> searchCatalog(String query, {int? limit}) async =>
      CatalogSearchResponse.fromJson(
        await _object('GET', '/v1/products/search', query: {'q': query, 'limit': ?limit}),
      );

  @override
  Future<List<ProductDetail>> products({String? category}) async => _parseList(
    await _array('GET', '/v1/products', query: {'category': ?category}),
    ProductDetail.fromJson,
  );

  @override
  Future<ProductDetail> product(String productId) async =>
      ProductDetail.fromJson(await _object('GET', '/v1/products/$productId'));

  @override
  Future<ProductDetail> updateProduct(String productId, ProductUpdate update) async =>
      ProductDetail.fromJson(
        await _object('PATCH', '/v1/products/$productId', body: update.toJson()),
      );

  @override
  Future<ProductAliasDetail> addProductAlias(String productId, String aliasText) async =>
      ProductAliasDetail.fromJson(
        await _object(
          'POST',
          '/v1/products/$productId/aliases',
          body: CreateAliasRequest(aliasText: aliasText).toJson(),
        ),
      );

  @override
  Future<void> deleteProductAlias(String productId, String aliasId) async {
    await _request<Object?>('DELETE', '/v1/products/$productId/aliases/$aliasId');
  }

  // Orders

  @override
  Future<List<Order>> orders({
    List<String>? status,
    List<String>? paymentStatus,
    int? limit,
  }) async => _parseList(
    await _array(
      'GET',
      '/v1/orders',
      // Lists go out as repeated keys (?status=a&status=b), Dio's default and what FastAPI reads.
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (paymentStatus != null && paymentStatus.isNotEmpty) 'payment_status': paymentStatus,
        'limit': ?limit,
      },
    ),
    Order.fromJson,
  );

  @override
  Future<RefundResponse> refundOrder(
    String orderId, {
    String? reason,
    bool restock = true,
  }) async => RefundResponse.fromJson(
    await _object(
      'POST',
      '/v1/orders/$orderId/refund',
      body: RefundRequest(reason: reason, restock: restock).toJson(),
    ),
  );

  @override
  Future<CreateInvoiceResponse> createInvoice(
    String orderId, {
    String? customerName,
    String? customerEmail,
  }) async => CreateInvoiceResponse.fromJson(
    await _object(
      'POST',
      '/v1/orders/$orderId/invoice',
      body: CreateInvoiceRequest(customerName: customerName, customerEmail: customerEmail).toJson(),
    ),
  );

  @override
  Future<Order> markOrderPaid(
    String orderId, {
    String method = 'upi',
    String? referenceId,
  }) async => Order.fromJson(
    await _object(
      'POST',
      '/v1/orders/$orderId/mark-paid',
      body: MarkPaidRequest(method: method, referenceId: referenceId).toJson(),
    ),
  );

  @override
  Future<Order> completeOrder(String orderId) async =>
      Order.fromJson(await _object('POST', '/v1/orders/$orderId/complete'));

  @override
  Future<Order> cancelOrder(String orderId, {String? reason}) async => Order.fromJson(
    await _object(
      'POST',
      '/v1/orders/$orderId/cancel',
      body: CancelOrderRequest(reason: reason).toJson(),
    ),
  );

  @override
  Future<PaymentLinkResponse> paymentLink(String orderId) async =>
      PaymentLinkResponse.fromJson(await _object('GET', '/v1/orders/$orderId/payment-link'));

  @override
  Future<Order> updateOrderStatus(String orderId, String status, {String? comment}) async =>
      Order.fromJson(
        await _object(
          'PATCH',
          '/v1/orders/$orderId/status',
          body: UpdateOrderStatusRequest(status: status, comment: comment).toJson(),
        ),
      );

  @override
  Future<List<OrderTimelineEvent>> orderTimeline(String orderId) async => _parseList(
    await _array('GET', '/v1/orders/$orderId/timeline'),
    OrderTimelineEvent.fromJson,
  );

  // Ask me

  @override
  Future<List<Question>> questions({String status = 'open'}) async => _parseList(
    await _array('GET', '/v1/questions', query: {'status': status}),
    Question.fromJson,
  );

  @override
  Future<Question> answerQuestion(
    String questionId,
    String answer, {
    bool always = false,
  }) async => Question.fromJson(
    await _object(
      'POST',
      '/v1/questions/$questionId/answer',
      body: Answer(answer: answer, always: always).toJson(),
    ),
  );

  @override
  Future<Question> closeQuestion(String questionId) async =>
      Question.fromJson(await _object('POST', '/v1/questions/$questionId/close'));

  // Chats

  @override
  Future<List<Conversation>> conversations() async =>
      _parseList(await _array('GET', '/v1/conversations'), Conversation.fromJson);

  @override
  Future<List<ChatMessage>> messages(String conversationId, {int? limit}) async => _parseList(
    await _array('GET', '/v1/conversations/$conversationId/messages', query: {'limit': ?limit}),
    ChatMessage.fromJson,
  );

  @override
  Future<AgentSwitch> switchAgent(String conversationId, {required bool active}) async =>
      AgentSwitch.fromJson(
        await _object(
          'PUT',
          '/v1/conversations/$conversationId/agent',
          body: AgentSwitch(active: active).toJson(),
        ),
      );

  @override
  Future<List<MemoryFact>> customerMemory(String conversationId) async => _parseList(
    await _array('GET', '/v1/conversations/$conversationId/memory'),
    MemoryFact.fromJson,
  );

  @override
  Future<void> forgetCustomerFact(String conversationId, String key) async {
    await _request<Object?>(
      'DELETE',
      '/v1/conversations/$conversationId/memory/${Uri.encodeComponent(key)}',
    );
  }

  @override
  Future<List<ChatMessage>> drafts(String conversationId) async => _parseList(
    await _array('GET', '/v1/conversations/$conversationId/drafts'),
    ChatMessage.fromJson,
  );

  @override
  Future<void> approveDraft(String conversationId, String messageId, {String? text}) async {
    await _request<Object?>(
      'POST',
      '/v1/conversations/$conversationId/drafts/$messageId/approve',
      body: DraftApproval(text: text).toJson(),
    );
  }

  @override
  Future<void> discardDraft(String conversationId, String messageId) async {
    await _request<Object?>(
      'POST',
      '/v1/conversations/$conversationId/drafts/$messageId/discard',
    );
  }

  // Stories

  @override
  Future<List<Story>> unconfirmedStories() async =>
      _parseList(await _array('GET', '/v1/stories/unconfirmed'), Story.fromJson);

  @override
  Future<void> confirmStory(String storyId, List<String> itemIds) async {
    await _request<Object?>(
      'POST',
      '/v1/stories/${Uri.encodeComponent(storyId)}/confirm',
      body: StoryConfirmation(itemIds: itemIds).toJson(),
    );
  }

  @override
  Future<void> linkPost(String productId, String igMediaId) async {
    await _request<Object?>(
      'PUT',
      '/v1/stories/posts/$productId',
      body: PostLink(igMediaId: igMediaId).toJson(),
    );
  }

  @override
  Future<void> setMenuImage(String? url) async {
    await _request<Object?>('PUT', '/v1/stories/menu-image', body: MenuImage(url: url).toJson());
  }

  // Simulator

  @override
  Future<SimulatorChat> simulatorSend({
    String text = '',
    String? quickReply,
    String customer = 'tester',
  }) async => SimulatorChat.fromJson(
    await _object(
      'POST',
      '/v1/simulator/messages',
      body: SimulatedMessage(text: text, quickReply: quickReply, customer: customer).toJson(),
      // The assistant answers before this returns, and a model call can take a while.
      receiveTimeout: const Duration(minutes: 2),
    ),
  );

  @override
  Future<SimulatorChat> simulatorChat({String customer = 'tester'}) async =>
      SimulatorChat.fromJson(
        await _object('GET', '/v1/simulator/messages', query: {'customer': customer}),
      );

  // Session

  @override
  Future<void> logout() async {
    await _request<Object?>('POST', '/v1/auth/logout');
  }

  // Plumbing

  List<T> _parseList<T>(List<dynamic> items, T Function(Map<String, dynamic>) parse) => [
    for (final item in items) parse(item as Map<String, dynamic>),
  ];

  Future<Map<String, dynamic>> _object(
    String method,
    String path, {
    Object? body,
    Map<String, Object>? query,
    Duration? receiveTimeout,
  }) async =>
      await _request<Map<String, dynamic>>(
        method,
        path,
        body: body,
        query: query,
        receiveTimeout: receiveTimeout,
      ) ??
      const {};

  Future<List<dynamic>> _array(
    String method,
    String path, {
    Object? body,
    Map<String, Object>? query,
  }) async => await _request<List<dynamic>>(method, path, body: body, query: query) ?? const [];

  Future<T?> _request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, Object>? query,
    Duration? receiveTimeout,
  }) async {
    try {
      final response = await _dio.request<T>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, receiveTimeout: receiveTimeout),
      );
      return response.data;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
