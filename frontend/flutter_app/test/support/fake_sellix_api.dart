import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/api/sellix_api.dart';

/// An in-memory [SellixApi] for widget tests, with small neutral data.
///
/// ```dart
/// final fake = FakeSellixApi();
/// ProviderScope(overrides: [sellixApiProvider.overrideWithValue(fake)], child: ...);
/// ```
///
/// - Writes change the state, so a screen that refetches sees the result.
/// - [FakeSellixApi.empty] is a new shop, for empty states.
/// - Set [failure] for error states; clear it to test retry.
/// - Set [delay] for loading states.
/// - [calls] lists the methods called, in order, e.g. `['today', 'restock']`.
class FakeSellixApi implements SellixApi {
  FakeSellixApi() {
    _seed();
  }

  /// A new shop: signed in, onboarding not done, nothing in stock, no orders or chats.
  FakeSellixApi.empty() {
    merchant = const Merchant(
      id: FakeIds.merchant,
      name: 'Test Shop',
      timezone: 'Asia/Kolkata',
      agentEnabled: true,
    );
    onboardingCompleted = false;
  }

  /// Fixed so that tests are repeatable. Pass `now:` to the helpers in `core/format.dart`.
  static final now = DateTime.utc(2026, 1, 15, 10);
  static final businessDate = DateTime(2026, 1, 15);

  // State. Tests can read it, or replace it to set up a case.
  Merchant merchant = const Merchant(
    id: FakeIds.merchant,
    name: 'Test Shop',
    timezone: 'Asia/Kolkata',
    agentEnabled: true,
  );
  bool onboardingCompleted = true;
  OnboardingAnswers answers = const OnboardingAnswers();
  bool paymentsReady = false;
  ShopProfile? profile;
  List<Channel> channels = [];
  List<StockRow> stock = [];
  List<YesterdayLeftoverItem> leftoverItems = [];
  List<UpcomingDay> upcoming = [];

  /// The last `setUpcomingStock` call, for tests.
  ({DateTime from, DateTime to, List<StockLine> lines, bool oneDayOnly, DateTime? lastOrderDate})? lastUpcoming;
  List<ProductDetail> catalog = [];
  List<Order> orderList = [];
  Map<String, List<OrderTimelineEvent>> timelines = {};
  List<Question> questionList = [];
  List<Conversation> conversationList = [];
  Map<String, List<ChatMessage>> messagesByConversation = {};
  Map<String, List<ChatMessage>> draftsByConversation = {};
  Map<String, List<MemoryFact>> memoryByConversation = {};
  List<Story> stories = [];
  String? menuImageUrl;
  Map<String, String> linkedPosts = {};
  List<SimulatorMessage> simulatorMessages = [];
  bool loggedOut = false;

  /// Thrown by every call while set.
  ApiException? failure;

  /// How long every call takes.
  Duration delay = Duration.zero;

  final List<String> calls = [];

  void _seed() {
    onboardingCompleted = true;
    answers = const OnboardingAnswers(
      category: 'Test category',
      city: 'Test City',
      hours: '9 am to 8 pm',
      tone: 'friendly',
      emoji: true,
    );
    profile = ShopProfile(version: 1, contentMd: '# Test Shop', createdAt: now);
    channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'active')];
    stock = const [
      StockRow(
        variantId: FakeIds.variantA,
        product: 'Item A',
        variant: 'Small',
        priceMinor: 10000,
        currency: 'INR',
        opening: 10,
        restocked: 0,
        held: 1,
        sold: 2,
        counterSales: 1,
        available: 6,
      ),
      StockRow(
        variantId: FakeIds.variantB,
        product: 'Item B',
        variant: null,
        priceMinor: 25050,
        currency: 'INR',
        opening: 5,
        restocked: 0,
        held: 0,
        sold: 0,
        counterSales: 0,
        available: 5,
        stockMode: StockMode.inventory,
      ),
    ];
    leftoverItems = const [
      YesterdayLeftoverItem(
        variantId: FakeIds.variantB,
        product: 'Item B',
        variant: null,
        priceMinor: 25050,
        currency: 'INR',
        leftoverQuantity: 2,
        stockMode: StockMode.inventory,
        shelfLifeDays: null,
      ),
    ];
    upcoming = [
      UpcomingDay(
        date: DateTime(2026, 1, 16),
        items: const [
          UpcomingItem(
            product: 'Item A',
            variant: 'Small',
            priceMinor: 10000,
            currency: 'INR',
            available: 3,
            variantId: FakeIds.variantA,
            opening: 4,
            stockMode: StockMode.daily,
            shelfLifeDays: null,
          ),
        ],
      ),
    ];
    catalog = [
      ProductDetail(
        id: FakeIds.productA,
        name: 'Item A',
        category: 'Test category',
        stockMode: StockMode.daily,
        isActive: true,
        variants: const [
          ProductVariantDetail(
            id: FakeIds.variantA,
            sku: null,
            name: 'Small',
            priceMinor: 10000,
            currency: 'INR',
            isActive: true,
          ),
        ],
        aliases: [
          ProductAliasDetail(
            id: FakeIds.aliasA,
            aliasText: 'item a',
            confidenceSource: 'merchant_confirmed',
            createdAt: now,
          ),
        ],
      ),
    ];
    orderList = [
      Order(
        id: FakeIds.orderUnpaid,
        number: 1,
        status: OrderStatus.awaitingPayment,
        currency: 'INR',
        totalMinor: 10000,
        conversationId: FakeIds.conversationA,
        createdAt: now,
        paidAt: null,
        holdExpiresAt: now.add(const Duration(minutes: 15)),
        items: const [
          OrderItem(product: 'Item A', variant: 'Small', quantity: 1, unitPriceMinor: 10000),
        ],
      ),
      Order(
        id: FakeIds.orderPaid,
        number: 2,
        status: OrderStatus.paid,
        currency: 'INR',
        totalMinor: 20000,
        conversationId: FakeIds.conversationA,
        createdAt: now.subtract(const Duration(hours: 1)),
        paidAt: now.subtract(const Duration(minutes: 50)),
        holdExpiresAt: null,
        items: const [
          OrderItem(product: 'Item A', variant: 'Small', quantity: 2, unitPriceMinor: 10000),
        ],
        paymentStatus: 'paid',
        fulfilmentMethod: 'delivery',
        deliveryAddress: 'Test address',
      ),
    ];
    timelines = {
      FakeIds.orderPaid: [
        OrderTimelineEvent(
          id: FakeIds.eventA,
          orderId: FakeIds.orderPaid,
          fromStatus: OrderStatus.awaitingPayment,
          toStatus: OrderStatus.paid,
          triggeredBy: 'merchant',
          comment: null,
          createdAt: now.subtract(const Duration(minutes: 50)),
        ),
      ],
    };
    questionList = [
      Question(
        id: FakeIds.questionA,
        conversationId: FakeIds.conversationA,
        question: 'Can this be delivered tomorrow?',
        status: 'open',
        answer: null,
        createdAt: now.subtract(const Duration(minutes: 5)),
        answeredAt: null,
        windowClosesAt: now.add(const Duration(hours: 20)),
        windowState: 'open',
      ),
    ];
    conversationList = [
      Conversation(
        id: FakeIds.conversationA,
        channel: 'instagram',
        customerHandle: 'customer.one',
        agentActive: true,
        agentPausedReason: null,
        lastMessageSender: 'customer',
        lastMessageBody: 'Hello',
        lastMessageAt: now.subtract(const Duration(minutes: 5)),
      ),
    ];
    messagesByConversation = {
      FakeIds.conversationA: [
        ChatMessage(
          id: FakeIds.messageA,
          direction: 'inbound',
          sender: 'customer',
          body: 'Hello',
          status: 'received',
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
    };
    draftsByConversation = {
      FakeIds.conversationA: [
        ChatMessage(
          id: FakeIds.draftA,
          direction: 'outbound',
          sender: 'agent',
          body: 'Hello, how can I help?',
          status: 'draft',
          createdAt: now,
        ),
      ],
    };
    memoryByConversation = {
      FakeIds.conversationA: [MemoryFact(key: 'prefers', value: 'pickup', updatedAt: now)],
    };
    stories = [
      Story(
        storyId: 'story-1',
        itemIds: [itemRefOf(FakeIds.variantA)],
        caption: 'New stock',
        expiresAt: now.add(const Duration(hours: 12)),
      ),
    ];
  }

  Future<void> _call(String name) async {
    calls.add(name);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = failure;
    if (error != null) throw error;
  }

  Never _notFound(String what) => throw ApiException('$what not found', statusCode: 404);

  Today _today() {
    final revenue = <String, int>{};
    for (final order in orderList.where((o) => o.paymentStatus == 'paid')) {
      revenue[order.currency] = (revenue[order.currency] ?? 0) + order.totalMinor;
    }
    return Today(
      businessDate: businessDate,
      agentEnabled: merchant.agentEnabled,
      stock: List.unmodifiable(stock),
      openQuestions: questionList.where((q) => q.status == 'open').length,
      ordersAwaitingPayment: orderList
          .where((o) => o.status == OrderStatus.awaitingPayment)
          .length,
      ordersPaid: orderList.where((o) => o.paymentStatus == 'paid').length,
      revenueMinorByCurrency: revenue,
    );
  }

  StockRow _row(String variantId) => stock.firstWhere(
    (row) => row.variantId == variantId,
    orElse: () => _notFound('Stock item'),
  );

  void _replaceRow(StockRow next) {
    stock = [
      for (final row in stock)
        if (row.variantId == next.variantId) next else row,
    ];
  }

  StockRow _copyRow(
    StockRow row, {
    int? opening,
    int? restocked,
    int? counterSales,
    int? available,
  }) => StockRow(
    variantId: row.variantId,
    product: row.product,
    variant: row.variant,
    priceMinor: row.priceMinor,
    currency: row.currency,
    opening: opening ?? row.opening,
    restocked: restocked ?? row.restocked,
    held: row.held,
    sold: row.sold,
    counterSales: counterSales ?? row.counterSales,
    available: available ?? row.available,
    stockMode: row.stockMode,
    shelfLifeDays: row.shelfLifeDays,
  );

  Order _order(String id) =>
      orderList.firstWhere((order) => order.id == id, orElse: () => _notFound('Order'));

  Order _updateOrder(
    String id, {
    String? status,
    String? paymentStatus,
    String? fulfilmentStatus,
    DateTime? paidAt,
    String? comment,
  }) {
    final order = _order(id);
    final next = Order(
      id: order.id,
      number: order.number,
      status: status ?? order.status,
      currency: order.currency,
      totalMinor: order.totalMinor,
      conversationId: order.conversationId,
      createdAt: order.createdAt,
      paidAt: paidAt ?? order.paidAt,
      holdExpiresAt: status == null ? order.holdExpiresAt : null,
      items: order.items,
      paymentStatus: paymentStatus ?? order.paymentStatus,
      fulfilmentStatus: fulfilmentStatus ?? order.fulfilmentStatus,
      fulfilmentMethod: order.fulfilmentMethod,
      channel: order.channel,
      deliveryAddress: order.deliveryAddress,
      customerNote: order.customerNote,
      orderNumber: order.orderNumber,
      neededBy: order.neededBy,
    );
    orderList = [
      for (final current in orderList)
        if (current.id == id) next else current,
    ];
    if (status != null) {
      timelines[id] = [
        ...?timelines[id],
        OrderTimelineEvent(
          id: 'event-${(timelines[id]?.length ?? 0) + 1}-$id',
          orderId: id,
          fromStatus: order.status,
          toStatus: status,
          triggeredBy: 'merchant',
          comment: comment,
          createdAt: now,
        ),
      ];
    }
    return next;
  }

  Question _settleQuestion(String id, {required String status, String? answer}) {
    final current = questionList.firstWhere(
      (question) => question.id == id,
      orElse: () => _notFound('Question'),
    );
    final next = Question(
      id: current.id,
      conversationId: current.conversationId,
      question: current.question,
      status: status,
      answer: answer ?? current.answer,
      createdAt: current.createdAt,
      answeredAt: answer == null ? current.answeredAt : now,
      windowClosesAt: current.windowClosesAt,
      windowState: current.windowState,
      answerDelivery: answer == null ? current.answerDelivery : 'sent',
    );
    questionList = [
      for (final question in questionList)
        if (question.id == id) next else question,
    ];
    return next;
  }

  ProductDetail _product(String id) =>
      catalog.firstWhere((product) => product.id == id, orElse: () => _notFound('Product'));

  ProductDetail _replaceProduct(
    ProductDetail product, {
    ProductUpdate update = const ProductUpdate(),
    List<ProductAliasDetail>? aliases,
  }) {
    final next = ProductDetail(
      id: product.id,
      name: update.name ?? product.name,
      title: update.title ?? product.title,
      description: update.description ?? product.description,
      category: update.category ?? product.category,
      baseImageUrl: update.baseImageUrl ?? product.baseImageUrl,
      stockMode: product.stockMode,
      shelfLifeDays: product.shelfLifeDays,
      attributes: update.attributes ?? product.attributes,
      isActive: product.isActive,
      variants: product.variants,
      aliases: aliases ?? product.aliases,
    );
    catalog = [
      for (final current in catalog)
        if (current.id == product.id) next else current,
    ];
    return next;
  }

  // Shop

  @override
  Future<Me> me() async {
    await _call('me');
    return Me(
      userId: FakeIds.user,
      merchant: merchant,
      role: 'owner',
      channels: channels,
      onboardingCompleted: onboardingCompleted,
    );
  }

  @override
  Future<Merchant> updateMerchant({String? name, String? timezone, bool? agentEnabled}) async {
    await _call('updateMerchant');
    return merchant = Merchant(
      id: merchant.id,
      name: name ?? merchant.name,
      timezone: timezone ?? merchant.timezone,
      agentEnabled: agentEnabled ?? merchant.agentEnabled,
    );
  }

  @override
  Future<ShopProfile?> shopProfile() async {
    await _call('shopProfile');
    return profile;
  }

  @override
  Future<ShopProfile> saveShopProfile(String contentMd) async {
    await _call('saveShopProfile');
    final saved = ShopProfile(
      version: (profile?.version ?? 0) + 1,
      contentMd: contentMd,
      createdAt: now,
    );
    profile = saved;
    return saved;
  }

  // Onboarding

  Onboarding _onboarding() => Onboarding(
    shopName: merchant.name,
    answers: answers,
    completed: onboardingCompleted,
    channels: channels,
    paymentsReady: paymentsReady,
  );

  @override
  Future<Onboarding> onboarding() async {
    await _call('onboarding');
    return _onboarding();
  }

  @override
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  }) async {
    await _call('saveOnboarding');
    merchant = Merchant(
      id: merchant.id,
      name: shopName,
      timezone: merchant.timezone,
      agentEnabled: merchant.agentEnabled,
    );
    this.answers = answers;
    onboardingCompleted = onboardingCompleted || complete;
    return _onboarding();
  }

  // Today

  @override
  Future<Today> today() async {
    await _call('today');
    return _today();
  }

  @override
  Future<Today> setOpeningStock(List<StockLine> lines) async {
    await _call('setOpeningStock');
    stock = [
      for (final (index, line) in lines.indexed)
        StockRow(
          variantId: stock
              .where((row) => row.product == line.product && row.variant == line.variant)
              .map((row) => row.variantId)
              .firstOrNull ??
              'variant-new-$index',
          product: line.product,
          variant: line.variant,
          priceMinor: line.priceMinor,
          currency: line.currency,
          opening: line.quantity,
          restocked: 0,
          held: 0,
          sold: 0,
          counterSales: 0,
          available: line.quantity,
          stockMode: line.stockMode ?? StockMode.daily,
          shelfLifeDays: line.shelfLifeDays,
        ),
    ];
    return _today();
  }

  @override
  Future<Today> restock(String variantId, int quantity) async {
    await _call('restock');
    final row = _row(variantId);
    _replaceRow(
      _copyRow(row, restocked: row.restocked + quantity, available: row.available + quantity),
    );
    return _today();
  }

  @override
  Future<Today> markSoldOut(String variantId) async {
    await _call('markSoldOut');
    final row = _row(variantId);
    _replaceRow(_copyRow(row, counterSales: row.counterSales + row.available, available: 0));
    return _today();
  }

  @override
  Future<CounterSaleResponse> recordCounterSale(String variantId, int quantity) async {
    await _call('recordCounterSale');
    final row = _row(variantId);
    if (quantity > row.available) {
      throw ApiException('Only ${row.available} left', statusCode: 409);
    }
    final remaining = row.available - quantity;
    _replaceRow(_copyRow(row, counterSales: row.counterSales + quantity, available: remaining));
    return CounterSaleResponse(
      variantId: variantId,
      businessDate: businessDate,
      quantitySold: quantity,
      remainingAvailable: remaining,
      today: _today(),
    );
  }

  @override
  Future<List<StockLine>> parseStockText(String text, {String defaultCurrency = 'INR'}) async {
    await _call('parseStockText');
    return [
      StockLine(product: text.trim(), priceMinor: 0, currency: defaultCurrency, quantity: 1),
    ];
  }

  @override
  Future<YesterdayLeftoversResponse> leftovers() async {
    await _call('leftovers');
    return YesterdayLeftoversResponse(
      businessDate: businessDate,
      yesterdayDate: DateTime(2026, 1, 14),
      leftovers: leftoverItems,
    );
  }

  RolloverResponse _rollover(Map<String, int> quantities) {
    var rolled = 0;
    for (final MapEntry(key: variantId, value: quantity) in quantities.entries) {
      if (quantity <= 0) continue;
      final found = stock.where((row) => row.variantId == variantId);
      if (found.isNotEmpty) {
        final row = found.first;
        _replaceRow(
          _copyRow(row, opening: row.opening + quantity, available: row.available + quantity),
        );
      }
      rolled++;
    }
    leftoverItems = leftoverItems.where((item) => !quantities.containsKey(item.variantId)).toList();
    return RolloverResponse(rolledCount: rolled, today: _today());
  }

  @override
  Future<RolloverResponse> applyRollover(List<RolloverItem> items) async {
    await _call('applyRollover');
    return _rollover({for (final item in items) item.variantId: item.rolloverQuantity});
  }

  @override
  Future<RolloverResponse> autoRollover() async {
    await _call('autoRollover');
    return _rollover({
      for (final item in leftoverItems.where((item) => item.keeps))
        item.variantId: item.leftoverQuantity,
    });
  }

  // Upcoming stock

  @override
  Future<List<UpcomingDay>> upcomingStock() async {
    await _call('upcomingStock');
    return upcoming;
  }

  @override
  Future<List<UpcomingDay>> setUpcomingStock(
    DateTime from,
    DateTime to,
    List<StockLine> lines, {
    bool oneDayOnly = false,
    DateTime? lastOrderDate,
  }) async {
    await _call('setUpcomingStock');
    lastUpcoming = (from: from, to: to, lines: lines, oneDayOnly: oneDayOnly, lastOrderDate: lastOrderDate);
    final items = [
      for (final line in lines)
        UpcomingItem(
          product: line.product,
          variant: line.variant,
          priceMinor: line.priceMinor,
          currency: line.currency,
          available: line.quantity,
          variantId: null,
          opening: line.quantity,
          stockMode: line.stockMode ?? StockMode.daily,
          shelfLifeDays: line.shelfLifeDays,
        ),
    ];
    return upcoming = [
      for (var day = DateTime(from.year, from.month, from.day);
          !day.isAfter(to);
          day = DateTime(day.year, day.month, day.day + 1))
        UpcomingDay(date: day, items: items),
    ];
  }

  // Catalog

  @override
  Future<CatalogSearchResponse> searchCatalog(String query, {int? limit}) async {
    await _call('searchCatalog');
    final wanted = query.toLowerCase();
    final items = [
      for (final product in catalog)
        if (product.name.toLowerCase().contains(wanted))
          CatalogSearchItem(
            productId: product.id,
            productName: product.name,
            category: product.category,
            attributes: product.attributes,
            similarity: 1,
            variants: product.variants,
          ),
    ];
    return CatalogSearchResponse(query: query, totalResults: items.length, items: items);
  }

  @override
  Future<List<ProductDetail>> products({String? category}) async {
    await _call('products');
    return [
      for (final product in catalog)
        if (category == null || product.category == category) product,
    ];
  }

  @override
  Future<ProductDetail> product(String productId) async {
    await _call('product');
    return _product(productId);
  }

  @override
  Future<ProductDetail> updateProduct(String productId, ProductUpdate update) async {
    await _call('updateProduct');
    return _replaceProduct(_product(productId), update: update);
  }

  @override
  Future<ProductAliasDetail> addProductAlias(String productId, String aliasText) async {
    await _call('addProductAlias');
    final product = _product(productId);
    final alias = ProductAliasDetail(
      id: 'alias-${product.aliases.length + 1}',
      aliasText: aliasText,
      confidenceSource: 'merchant_confirmed',
      createdAt: now,
    );
    _replaceProduct(product, aliases: [...product.aliases, alias]);
    return alias;
  }

  @override
  Future<void> deleteProductAlias(String productId, String aliasId) async {
    await _call('deleteProductAlias');
    final product = _product(productId);
    if (!product.aliases.any((alias) => alias.id == aliasId)) _notFound('Alias');
    _replaceProduct(
      product,
      aliases: [
        for (final alias in product.aliases)
          if (alias.id != aliasId) alias,
      ],
    );
  }

  // Orders

  @override
  Future<List<Order>> orders({
    List<String>? status,
    List<String>? paymentStatus,
    int? limit,
  }) async {
    await _call('orders');
    final found = [
      for (final order in orderList)
        if ((status == null || status.isEmpty || status.contains(order.status)) &&
            (paymentStatus == null ||
                paymentStatus.isEmpty ||
                paymentStatus.contains(order.paymentStatus)))
          order,
    ];
    return found.take(limit ?? 50).toList();
  }

  @override
  Future<RefundResponse> refundOrder(String orderId, {String? reason, bool restock = true}) async {
    await _call('refundOrder');
    final order = _updateOrder(
      orderId,
      status: OrderStatus.refunded,
      paymentStatus: 'refunded',
      comment: reason,
    );
    return RefundResponse(
      orderId: order.id,
      refundId: 'refund-${order.number}',
      amountMinor: order.totalMinor,
      currency: order.currency,
      status: 'completed',
    );
  }

  @override
  Future<CreateInvoiceResponse> createInvoice(
    String orderId, {
    String? customerName,
    String? customerEmail,
  }) async {
    await _call('createInvoice');
    final order = _order(orderId);
    return CreateInvoiceResponse(
      orderId: order.id,
      invoiceId: 'invoice-${order.number}',
      payerViewUrl: 'https://example.com/invoice/${order.number}',
    );
  }

  @override
  Future<Order> markOrderPaid(String orderId, {String method = 'upi', String? referenceId}) async {
    await _call('markOrderPaid');
    return _updateOrder(
      orderId,
      status: OrderStatus.paid,
      paymentStatus: 'paid',
      paidAt: now,
    );
  }

  @override
  Future<Order> completeOrder(String orderId) async {
    await _call('completeOrder');
    return _updateOrder(orderId, status: OrderStatus.completed, fulfilmentStatus: 'fulfilled');
  }

  @override
  Future<Order> cancelOrder(String orderId, {String? reason}) async {
    await _call('cancelOrder');
    return _updateOrder(orderId, status: OrderStatus.cancelled, comment: reason);
  }

  @override
  Future<PaymentLinkResponse> paymentLink(String orderId) async {
    await _call('paymentLink');
    final order = _order(orderId);
    return PaymentLinkResponse(
      orderId: order.id,
      orderNumber: order.number,
      paymentMethod: 'upi',
      paymentLink: 'upi://pay?pa=test@upi&tn=${order.number}',
      currency: order.currency,
      totalMinor: order.totalMinor,
    );
  }

  @override
  Future<Order> updateOrderStatus(String orderId, String status, {String? comment}) async {
    await _call('updateOrderStatus');
    return _updateOrder(orderId, status: status, comment: comment);
  }

  @override
  Future<List<OrderTimelineEvent>> orderTimeline(String orderId) async {
    await _call('orderTimeline');
    _order(orderId);
    return timelines[orderId] ?? const [];
  }

  // Ask me

  @override
  Future<List<Question>> questions({String status = 'open'}) async {
    await _call('questions');
    return [
      for (final question in questionList)
        if (question.status == status) question,
    ];
  }

  @override
  Future<Question> answerQuestion(String questionId, String answer, {bool always = false}) async {
    await _call('answerQuestion');
    return _settleQuestion(questionId, status: 'answered', answer: answer);
  }

  @override
  Future<Question> closeQuestion(String questionId) async {
    await _call('closeQuestion');
    return _settleQuestion(questionId, status: 'closed');
  }

  // Chats

  Conversation _conversation(String id) => conversationList.firstWhere(
    (conversation) => conversation.id == id,
    orElse: () => _notFound('Conversation'),
  );

  @override
  Future<List<Conversation>> conversations() async {
    await _call('conversations');
    return conversationList;
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId, {int? limit}) async {
    await _call('messages');
    _conversation(conversationId);
    return messagesByConversation[conversationId] ?? const [];
  }

  @override
  Future<AgentSwitch> switchAgent(String conversationId, {required bool active}) async {
    await _call('switchAgent');
    final current = _conversation(conversationId);
    final next = Conversation(
      id: current.id,
      channel: current.channel,
      customerHandle: current.customerHandle,
      agentActive: active,
      agentPausedReason: active ? null : 'merchant',
      lastMessageSender: current.lastMessageSender,
      lastMessageBody: current.lastMessageBody,
      lastMessageAt: current.lastMessageAt,
    );
    conversationList = [
      for (final conversation in conversationList)
        if (conversation.id == conversationId) next else conversation,
    ];
    return AgentSwitch(active: active);
  }

  @override
  Future<List<MemoryFact>> customerMemory(String conversationId) async {
    await _call('customerMemory');
    _conversation(conversationId);
    return memoryByConversation[conversationId] ?? const [];
  }

  @override
  Future<void> forgetCustomerFact(String conversationId, String key) async {
    await _call('forgetCustomerFact');
    final facts = memoryByConversation[conversationId] ?? const <MemoryFact>[];
    if (!facts.any((fact) => fact.key == key)) _notFound('Fact');
    memoryByConversation[conversationId] = [
      for (final fact in facts)
        if (fact.key != key) fact,
    ];
  }

  @override
  Future<List<ChatMessage>> drafts(String conversationId) async {
    await _call('drafts');
    _conversation(conversationId);
    return draftsByConversation[conversationId] ?? const [];
  }

  ChatMessage _takeDraft(String conversationId, String messageId) {
    final waiting = draftsByConversation[conversationId] ?? const <ChatMessage>[];
    final draft = waiting.firstWhere(
      (message) => message.id == messageId,
      orElse: () => _notFound('Draft'),
    );
    draftsByConversation[conversationId] = [
      for (final message in waiting)
        if (message.id != messageId) message,
    ];
    return draft;
  }

  @override
  Future<void> approveDraft(String conversationId, String messageId, {String? text}) async {
    await _call('approveDraft');
    final draft = _takeDraft(conversationId, messageId);
    messagesByConversation[conversationId] = [
      ...?messagesByConversation[conversationId],
      ChatMessage(
        id: draft.id,
        direction: draft.direction,
        sender: draft.sender,
        body: text ?? draft.body,
        status: 'sent',
        createdAt: now,
      ),
    ];
  }

  @override
  Future<void> discardDraft(String conversationId, String messageId) async {
    await _call('discardDraft');
    _takeDraft(conversationId, messageId);
  }

  // Stories

  @override
  Future<List<Story>> unconfirmedStories() async {
    await _call('unconfirmedStories');
    return stories;
  }

  @override
  Future<void> confirmStory(String storyId, List<String> itemIds) async {
    await _call('confirmStory');
    if (!stories.any((story) => story.storyId == storyId)) _notFound('Story');
    stories = [
      for (final story in stories)
        if (story.storyId != storyId) story,
    ];
  }

  @override
  Future<void> linkPost(String productId, String igMediaId) async {
    await _call('linkPost');
    linkedPosts[productId] = igMediaId;
  }

  @override
  Future<void> setMenuImage(String? url) async {
    await _call('setMenuImage');
    menuImageUrl = url;
  }

  // Simulator

  @override
  Future<SimulatorChat> simulatorSend({
    String text = '',
    String? quickReply,
    String customer = 'tester',
  }) async {
    await _call('simulatorSend');
    final next = simulatorMessages.length;
    simulatorMessages = [
      ...simulatorMessages,
      SimulatorMessage(
        id: 'sim-$next',
        sender: 'customer',
        body: quickReply ?? text,
        status: 'received',
        at: now,
      ),
      SimulatorMessage(
        id: 'sim-${next + 1}',
        sender: 'agent',
        body: 'Test reply',
        status: 'sent',
        at: now,
      ),
    ];
    return SimulatorChat(
      messages: simulatorMessages,
      turn: const SimulatorTurn(id: 'turn-1', status: 'completed'),
    );
  }

  @override
  Future<SimulatorChat> simulatorChat({String customer = 'tester'}) async {
    await _call('simulatorChat');
    return SimulatorChat(messages: simulatorMessages);
  }

  // Session

  @override
  Future<void> logout() async {
    await _call('logout');
    loggedOut = true;
  }
}

/// The ids in [FakeSellixApi]'s data.
abstract final class FakeIds {
  static const user = '00000000-0000-4000-8000-000000000001';
  static const merchant = '00000000-0000-4000-8000-000000000002';
  static const variantA = 'aaaaaa00-0000-4000-8000-000000000001';
  static const variantB = 'bbbbbb00-0000-4000-8000-000000000002';
  static const productA = '00000000-0000-4000-8000-000000000011';
  static const aliasA = '00000000-0000-4000-8000-000000000012';
  static const orderUnpaid = '00000000-0000-4000-8000-000000000021';
  static const orderPaid = '00000000-0000-4000-8000-000000000022';
  static const eventA = '00000000-0000-4000-8000-000000000023';
  static const questionA = '00000000-0000-4000-8000-000000000031';
  static const conversationA = '00000000-0000-4000-8000-000000000041';
  static const messageA = '00000000-0000-4000-8000-000000000042';
  static const draftA = '00000000-0000-4000-8000-000000000043';
}
