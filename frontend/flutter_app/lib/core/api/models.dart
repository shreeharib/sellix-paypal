/// Types of the sellix /v1 API, field for field with the backend's JSON.
///
/// Sources: backend/app/api/v1/schemas.py plus the classes declared inside the routers
/// (stock.py, orders.py, stories.py, chats.py, simulator.py) and
/// backend/app/modules/shop_profile/schemas.py.
///
/// Conventions:
/// - ids are Strings (UUIDs on the wire).
/// - money is an int in minor units (`...Minor`) with a currency code; format it with
///   `core/format.dart`, never compute it with doubles.
/// - timestamps parse to UTC [DateTime]s; business dates ("2026-11-05") parse to local midnight.
/// - `fromJson` is tolerant: a nullable or defaulted backend field that's missing gets the
///   backend's default instead of throwing. A required field that's missing still throws, because
///   that's a contract break and it should surface in `test/api/live_contract_test.dart`.
library;

typedef _Json = Map<String, dynamic>;

DateTime? _dateOrNull(Object? value) => value is String ? DateTime.tryParse(value) : null;

DateTime _date(Object? value) => DateTime.parse(value! as String);

int _int(Object? value) => (value! as num).toInt();

int? _intOrNull(Object? value) => (value as num?)?.toInt();

/// A day on the wire: "2026-11-05", read from and written as the calendar date.
String _day(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

List<T> _list<T>(Object? value, T Function(_Json) parse) => [
  for (final item in (value as List<dynamic>?) ?? const <dynamic>[]) parse(item as _Json),
];

_Json _map(Object? value) => (value as _Json?) ?? const {};

String _label(String product, String? variant) =>
    variant == null || variant.isEmpty ? product : '$product ($variant)';

/// The short item id the assistant uses (backend agent/items.py): "i" and the first six hex digits
/// of the variant's UUID. `POST /v1/stories/{id}/confirm` and [Story.itemIds] use these, while every
/// other endpoint uses the variant's UUID.
String itemRefOf(String variantId) =>
    'i${variantId.replaceAll('-', '').substring(0, 6).toLowerCase()}';

// Auth -----------------------------------------------------------------------------------------

class InstagramLoginStart {
  const InstagramLoginStart({required this.codeChallenge, required this.redirectUri});

  final String codeChallenge;
  final String redirectUri;

  Map<String, dynamic> toJson() => {'code_challenge': codeChallenge, 'redirect_uri': redirectUri};
}

class InstagramLoginUrl {
  const InstagramLoginUrl({required this.authorizeUrl});

  factory InstagramLoginUrl.fromJson(Map<String, dynamic> json) =>
      InstagramLoginUrl(authorizeUrl: json['authorize_url'] as String);

  final String authorizeUrl;
}

class TokenRequest {
  const TokenRequest({required this.code, required this.codeVerifier});

  final String code;
  final String codeVerifier;

  Map<String, dynamic> toJson() => {'code': code, 'code_verifier': codeVerifier};
}

class RefreshRequest {
  const RefreshRequest({required this.refreshToken});

  final String refreshToken;

  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}

/// `Tokens` in schemas.py.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.tokenType = 'Bearer',
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresIn: _int(json['expires_in']),
    tokenType: json['token_type'] as String? ?? 'Bearer',
  );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String tokenType;
}

// Shop -----------------------------------------------------------------------------------------

class Channel {
  const Channel({
    required this.channel,
    required this.username,
    required this.status,
    this.tokenExpiresAt,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    channel: json['channel'] as String,
    username: json['username'] as String?,
    status: json['status'] as String,
    tokenExpiresAt: _dateOrNull(json['token_expires_at']),
  );

  final String channel;
  final String? username;
  final String status;
  final DateTime? tokenExpiresAt;
}

class Merchant {
  const Merchant({
    required this.id,
    required this.name,
    required this.timezone,
    required this.agentEnabled,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
    id: json['id'] as String,
    name: json['name'] as String,
    timezone: json['timezone'] as String,
    agentEnabled: json['agent_enabled'] as bool,
  );

  final String id;
  final String name;
  final String timezone;
  final bool agentEnabled;
}

class Me {
  const Me({
    required this.userId,
    required this.merchant,
    required this.role,
    required this.channels,
    required this.onboardingCompleted,
  });

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    userId: json['user_id'] as String,
    merchant: Merchant.fromJson(json['merchant'] as _Json),
    role: json['role'] as String,
    channels: _list(json['channels'], Channel.fromJson),
    onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
  );

  final String userId;
  final Merchant merchant;
  final String role;
  final List<Channel> channels;

  /// False until the merchant finishes the guided setup after their first sign-in.
  final bool onboardingCompleted;
}

/// Only the fields that are set are sent; the others stay as they are.
class MerchantUpdate {
  const MerchantUpdate({this.name, this.timezone, this.agentEnabled});

  final String? name;
  final String? timezone;
  final bool? agentEnabled;

  Map<String, dynamic> toJson() => {
    'name': ?name,
    'timezone': ?timezone,
    'agent_enabled': ?agentEnabled,
  };
}

class ShopProfile {
  const ShopProfile({required this.version, required this.contentMd, required this.createdAt});

  factory ShopProfile.fromJson(Map<String, dynamic> json) => ShopProfile(
    version: _int(json['version']),
    contentMd: json['content_md'] as String,
    createdAt: _date(json['created_at']),
  );

  final int version;
  final String contentMd;
  final DateTime createdAt;
}

class ShopProfileUpdate {
  const ShopProfileUpdate({required this.contentMd});

  final String contentMd;

  Map<String, dynamic> toJson() => {'content_md': contentMd};
}

// Onboarding -----------------------------------------------------------------------------------

/// Marks a [OnboardingAnswers.copyWith] argument as "keep the current value", so that passing null
/// can clear a field.
const Object _keep = Object();

/// The merchant's onboarding answers. Every field is optional: each step can be skipped.
///
/// Short fields allow 200 characters (category, area, city, hours, weeklyOff, intro,
/// addressCustomers, upiId); long ones 1500 (address, products, fulfilment, customOrders,
/// cancellations, neverPromise, faqs). A PUT replaces all the answers, so send the whole object.
class OnboardingAnswers {
  const OnboardingAnswers({
    this.category,
    this.area,
    this.city,
    this.address,
    this.hours,
    this.weeklyOff,
    this.products,
    this.intro,
    this.tone,
    this.emoji,
    this.addressCustomers,
    this.fulfilment,
    this.customOrders,
    this.cancellations,
    this.neverPromise,
    this.faqs,
    this.upiId,
  });

  factory OnboardingAnswers.fromJson(Map<String, dynamic> json) => OnboardingAnswers(
    category: json['category'] as String?,
    area: json['area'] as String?,
    city: json['city'] as String?,
    address: json['address'] as String?,
    hours: json['hours'] as String?,
    weeklyOff: json['weekly_off'] as String?,
    products: json['products'] as String?,
    intro: json['intro'] as String?,
    tone: json['tone'] as String?,
    emoji: json['emoji'] as bool?,
    addressCustomers: json['address_customers'] as String?,
    fulfilment: json['fulfilment'] as String?,
    customOrders: json['custom_orders'] as String?,
    cancellations: json['cancellations'] as String?,
    neverPromise: json['never_promise'] as String?,
    faqs: json['faqs'] as String?,
    upiId: json['upi_id'] as String?,
  );

  // Shop
  final String? category;
  final String? area;
  final String? city;
  final String? address;
  final String? hours;
  final String? weeklyOff;

  /// What the shop sells, in plain words (no prices or quantities).
  final String? products;

  // Agent persona
  final String? intro;

  /// "friendly" or "formal"; the backend refuses anything else.
  final String? tone;
  final bool? emoji;
  final String? addressCustomers;

  // Policies and FAQs
  final String? fulfilment;
  final String? customOrders;
  final String? cancellations;
  final String? neverPromise;
  final String? faqs;

  // Payments
  final String? upiId;

  /// Passing null clears a field; leaving an argument out keeps it.
  OnboardingAnswers copyWith({
    Object? category = _keep,
    Object? area = _keep,
    Object? city = _keep,
    Object? address = _keep,
    Object? hours = _keep,
    Object? weeklyOff = _keep,
    Object? products = _keep,
    Object? intro = _keep,
    Object? tone = _keep,
    Object? emoji = _keep,
    Object? addressCustomers = _keep,
    Object? fulfilment = _keep,
    Object? customOrders = _keep,
    Object? cancellations = _keep,
    Object? neverPromise = _keep,
    Object? faqs = _keep,
    Object? upiId = _keep,
  }) {
    T? pick<T>(Object? next, T? current) => identical(next, _keep) ? current : next as T?;
    return OnboardingAnswers(
      category: pick(category, this.category),
      area: pick(area, this.area),
      city: pick(city, this.city),
      address: pick(address, this.address),
      hours: pick(hours, this.hours),
      weeklyOff: pick(weeklyOff, this.weeklyOff),
      products: pick(products, this.products),
      intro: pick(intro, this.intro),
      tone: pick(tone, this.tone),
      emoji: pick(emoji, this.emoji),
      addressCustomers: pick(addressCustomers, this.addressCustomers),
      fulfilment: pick(fulfilment, this.fulfilment),
      customOrders: pick(customOrders, this.customOrders),
      cancellations: pick(cancellations, this.cancellations),
      neverPromise: pick(neverPromise, this.neverPromise),
      faqs: pick(faqs, this.faqs),
      upiId: pick(upiId, this.upiId),
    );
  }

  Map<String, dynamic> toJson() => {
    'category': ?category,
    'area': ?area,
    'city': ?city,
    'address': ?address,
    'hours': ?hours,
    'weekly_off': ?weeklyOff,
    'products': ?products,
    'intro': ?intro,
    'tone': ?tone,
    'emoji': ?emoji,
    'address_customers': ?addressCustomers,
    'fulfilment': ?fulfilment,
    'custom_orders': ?customOrders,
    'cancellations': ?cancellations,
    'never_promise': ?neverPromise,
    'faqs': ?faqs,
    'upi_id': ?upiId,
  };
}

class Onboarding {
  const Onboarding({
    required this.shopName,
    required this.answers,
    required this.completed,
    required this.channels,
    required this.paymentsReady,
  });

  factory Onboarding.fromJson(Map<String, dynamic> json) => Onboarding(
    shopName: json['shop_name'] as String,
    answers: OnboardingAnswers.fromJson(_map(json['answers'])),
    completed: json['completed'] as bool,
    channels: _list(json['channels'], Channel.fromJson),
    paymentsReady: json['payments_ready'] as bool,
  );

  final String shopName;
  final OnboardingAnswers answers;
  final bool completed;
  final List<Channel> channels;

  /// Online payment links (PayPal) can be sent. It says nothing about UPI: see [OnboardingAnswers.upiId].
  final bool paymentsReady;
}

class OnboardingUpdate {
  const OnboardingUpdate({required this.shopName, required this.answers, this.complete = false});

  final String shopName;
  final OnboardingAnswers answers;

  /// Finish the setup; skipped steps can be done later in Settings.
  final bool complete;

  Map<String, dynamic> toJson() => {
    'shop_name': shopName,
    'answers': answers.toJson(),
    'complete': complete,
  };
}

// Today ----------------------------------------------------------------------------------------

/// Values of `stock_mode`.
abstract final class StockMode {
  static const daily = 'daily';
  static const inventory = 'inventory';
  static const madeToOrder = 'made_to_order';
  static const unlimited = 'unlimited';
}

class StockRow {
  const StockRow({
    required this.variantId,
    required this.product,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.opening,
    required this.restocked,
    required this.held,
    required this.sold,
    required this.counterSales,
    required this.available,
    this.stockMode = StockMode.daily,
    this.shelfLifeDays,
  });

  factory StockRow.fromJson(Map<String, dynamic> json) => StockRow(
    variantId: json['variant_id'] as String,
    product: json['product'] as String,
    variant: json['variant'] as String?,
    priceMinor: _int(json['price_minor']),
    currency: json['currency'] as String,
    opening: _int(json['opening']),
    restocked: _intOrNull(json['restocked']) ?? 0,
    held: _intOrNull(json['held']) ?? 0,
    sold: _intOrNull(json['sold']) ?? 0,
    counterSales: _intOrNull(json['counter_sales']) ?? 0,
    available: _int(json['available']),
    stockMode: json['stock_mode'] as String? ?? StockMode.daily,
    shelfLifeDays: _intOrNull(json['shelf_life_days']),
  );

  final String variantId;
  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;

  /// The morning count: what the stock update sets.
  final int opening;
  final int restocked;
  final int held;

  /// Sold online (paid orders). See [counterSales] for the shop counter.
  final int sold;
  final int counterSales;
  final int available;
  final String stockMode;
  final int? shelfLifeDays;

  String get label => _label(product, variant);

  /// Everything made today: the morning count plus any restocks.
  int get made => opening + restocked;

  /// Sold online and at the counter.
  int get soldTotal => sold + counterSales;

  /// Counted in the stock ledger (made-to-order and unlimited items aren't).
  bool get isTracked => stockMode == StockMode.daily || stockMode == StockMode.inventory;

  /// Leftovers can carry to the next day: the same rule as `POST /v1/today/rollover`.
  bool get carries => stockMode == StockMode.inventory || (shelfLifeDays ?? 0) > 1;
}

class Today {
  const Today({
    required this.businessDate,
    required this.agentEnabled,
    required this.stock,
    required this.openQuestions,
    required this.ordersAwaitingPayment,
    required this.ordersPaid,
    required this.revenueMinorByCurrency,
  });

  factory Today.fromJson(Map<String, dynamic> json) => Today(
    businessDate: _date(json['business_date']),
    agentEnabled: json['agent_enabled'] as bool,
    stock: _list(json['stock'], StockRow.fromJson),
    openQuestions: _int(json['open_questions']),
    ordersAwaitingPayment: _int(json['orders_awaiting_payment']),
    ordersPaid: _int(json['orders_paid']),
    revenueMinorByCurrency: {
      for (final entry in _map(json['revenue_minor_by_currency']).entries)
        entry.key: _int(entry.value),
    },
  );

  /// The shop's current day, in the shop's timezone. Trust this over the phone's clock.
  final DateTime businessDate;
  final bool agentEnabled;
  final List<StockRow> stock;
  final int openQuestions;
  final int ordersAwaitingPayment;
  final int ordersPaid;
  final Map<String, int> revenueMinorByCurrency;
}

/// A stock line, sent to the morning update and to upcoming stock (`StockUpdateLine` in schemas.py),
/// and returned by parse-stock-text (`StockLine`, which has no [stockMode] or [shelfLifeDays]).
class StockLine {
  const StockLine({
    required this.product,
    this.variant,
    required this.priceMinor,
    this.currency = 'INR',
    required this.quantity,
    this.stockMode,
    this.shelfLifeDays,
  });

  factory StockLine.fromJson(Map<String, dynamic> json) => StockLine(
    product: json['product'] as String,
    variant: json['variant'] as String?,
    priceMinor: _int(json['price_minor']),
    currency: json['currency'] as String? ?? 'INR',
    quantity: _int(json['quantity']),
    stockMode: json['stock_mode'] as String?,
    shelfLifeDays: _intOrNull(json['shelf_life_days']),
  );

  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;

  /// 0 to 100000.
  final int quantity;

  /// Left out: the item keeps its current stock type.
  final String? stockMode;

  /// 1 to 3650. Over 1: leftovers can carry to the next day.
  final int? shelfLifeDays;

  String get label => _label(product, variant);

  Map<String, dynamic> toJson() => {
    'product': product,
    'variant': variant,
    'price_minor': priceMinor,
    'currency': currency,
    'quantity': quantity,
    'stock_mode': ?stockMode,
    'shelf_life_days': ?shelfLifeDays,
  };
}

/// What parse-stock-text returns.
class OpeningStock {
  const OpeningStock({required this.lines});

  factory OpeningStock.fromJson(Map<String, dynamic> json) =>
      OpeningStock(lines: _list(json['lines'], StockLine.fromJson));

  final List<StockLine> lines;
}

class StockUpdate {
  const StockUpdate({required this.lines});

  /// 1 to 200 lines.
  final List<StockLine> lines;

  Map<String, dynamic> toJson() => {
    'lines': [for (final line in lines) line.toJson()],
  };
}

class RestockRequest {
  const RestockRequest({required this.variantId, required this.quantity});

  final String variantId;
  final int quantity;

  Map<String, dynamic> toJson() => {'variant_id': variantId, 'quantity': quantity};
}

class SoldOutRequest {
  const SoldOutRequest({required this.variantId});

  final String variantId;

  Map<String, dynamic> toJson() => {'variant_id': variantId};
}

class CounterSaleRequest {
  const CounterSaleRequest({required this.variantId, required this.quantity});

  final String variantId;
  final int quantity;

  Map<String, dynamic> toJson() => {'variant_id': variantId, 'quantity': quantity};
}

class CounterSaleResponse {
  const CounterSaleResponse({
    required this.variantId,
    required this.businessDate,
    required this.quantitySold,
    required this.remainingAvailable,
    required this.today,
  });

  factory CounterSaleResponse.fromJson(Map<String, dynamic> json) => CounterSaleResponse(
    variantId: json['variant_id'] as String,
    businessDate: _date(json['business_date']),
    quantitySold: _int(json['quantity_sold']),
    remainingAvailable: _int(json['remaining_available']),
    today: Today.fromJson(json['today'] as _Json),
  );

  final String variantId;
  final DateTime businessDate;
  final int quantitySold;
  final int remainingAvailable;
  final Today today;
}

class ParseStockTextRequest {
  const ParseStockTextRequest({required this.text, this.defaultCurrency = 'INR'});

  final String text;
  final String defaultCurrency;

  Map<String, dynamic> toJson() => {'text': text, 'default_currency': defaultCurrency};
}

class YesterdayLeftoverItem {
  const YesterdayLeftoverItem({
    required this.variantId,
    required this.product,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.leftoverQuantity,
    required this.stockMode,
    required this.shelfLifeDays,
  });

  factory YesterdayLeftoverItem.fromJson(Map<String, dynamic> json) => YesterdayLeftoverItem(
    variantId: json['variant_id'] as String,
    product: json['product'] as String,
    variant: json['variant'] as String?,
    priceMinor: _int(json['price_minor']),
    currency: json['currency'] as String,
    leftoverQuantity: _int(json['leftover_quantity']),
    stockMode: json['stock_mode'] as String? ?? StockMode.daily,
    shelfLifeDays: _intOrNull(json['shelf_life_days']),
  );

  final String variantId;
  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;
  final int leftoverQuantity;
  final String stockMode;
  final int? shelfLifeDays;

  String get label => _label(product, variant);

  /// Whether this item is meant to last beyond the day it was made.
  bool get keeps => stockMode == StockMode.inventory || (shelfLifeDays ?? 0) > 1;
}

class YesterdayLeftoversResponse {
  const YesterdayLeftoversResponse({
    required this.businessDate,
    required this.yesterdayDate,
    required this.leftovers,
  });

  factory YesterdayLeftoversResponse.fromJson(Map<String, dynamic> json) =>
      YesterdayLeftoversResponse(
        businessDate: _date(json['business_date']),
        yesterdayDate: _date(json['yesterday_date']),
        leftovers: _list(json['leftovers'], YesterdayLeftoverItem.fromJson),
      );

  final DateTime businessDate;
  final DateTime yesterdayDate;
  final List<YesterdayLeftoverItem> leftovers;
}

class RolloverItem {
  const RolloverItem({required this.variantId, required this.rolloverQuantity});

  final String variantId;
  final int rolloverQuantity;

  Map<String, dynamic> toJson() => {'variant_id': variantId, 'rollover_quantity': rolloverQuantity};
}

class RolloverRequest {
  const RolloverRequest({required this.items});

  /// At least one item.
  final List<RolloverItem> items;

  Map<String, dynamic> toJson() => {
    'items': [for (final item in items) item.toJson()],
  };
}

class RolloverResponse {
  const RolloverResponse({required this.rolledCount, required this.today});

  factory RolloverResponse.fromJson(Map<String, dynamic> json) => RolloverResponse(
    rolledCount: _int(json['rolled_count']),
    today: Today.fromJson(json['today'] as _Json),
  );

  final int rolledCount;
  final Today today;
}

// Upcoming stock (stock.py) ----------------------------------------------------------------------

class UpcomingStock {
  const UpcomingStock({required this.fromDate, required this.toDate, required this.lines});

  final DateTime fromDate;
  final DateTime toDate;
  final List<StockLine> lines;

  Map<String, dynamic> toJson() => {
    'from_date': _day(fromDate),
    'to_date': _day(toDate),
    'lines': [for (final line in lines) line.toJson()],
  };
}

class UpcomingItem {
  const UpcomingItem({
    required this.product,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.available,
    required this.variantId,
    required this.opening,
    required this.stockMode,
    required this.shelfLifeDays,
  });

  factory UpcomingItem.fromJson(Map<String, dynamic> json) => UpcomingItem(
    product: json['product'] as String,
    variant: json['variant'] as String?,
    priceMinor: _int(json['price_minor']),
    currency: json['currency'] as String,
    available: _int(json['available']),
    variantId: json['variant_id'] as String?,
    opening: _int(json['opening']),
    stockMode: json['stock_mode'] as String? ?? StockMode.daily,
    shelfLifeDays: _intOrNull(json['shelf_life_days']),
  );

  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;
  final int available;
  final String? variantId;

  /// The quantity set for the day; [available] is less once orders hold some.
  final int opening;
  final String stockMode;
  final int? shelfLifeDays;

  String get label => _label(product, variant);

  /// Held by pre-orders.
  int get held => opening - available;
}

class UpcomingDay {
  const UpcomingDay({required this.date, required this.items});

  factory UpcomingDay.fromJson(Map<String, dynamic> json) =>
      UpcomingDay(date: _date(json['date']), items: _list(json['items'], UpcomingItem.fromJson));

  final DateTime date;
  final List<UpcomingItem> items;
}

// Orders ---------------------------------------------------------------------------------------

/// Values of `Order.status` the backend accepts, in filters and in `PATCH .../status`.
abstract final class OrderStatus {
  static const awaitingPayment = 'awaiting_payment';
  static const paid = 'paid';
  static const expired = 'expired';
  static const cancelled = 'cancelled';
  static const completed = 'completed';
  static const refunded = 'refunded';
  static const draft = 'draft';
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const ready = 'ready';
  static const delivered = 'delivered';
}

class OrderItem {
  const OrderItem({
    required this.product,
    required this.variant,
    required this.quantity,
    required this.unitPriceMinor,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    product: json['product'] as String,
    variant: json['variant'] as String?,
    quantity: _int(json['quantity']),
    unitPriceMinor: _int(json['unit_price_minor']),
  );

  final String product;
  final String? variant;
  final int quantity;
  final int unitPriceMinor;

  String get label => _label(product, variant);

  int get lineTotalMinor => unitPriceMinor * quantity;
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.status,
    required this.currency,
    required this.totalMinor,
    required this.conversationId,
    required this.createdAt,
    required this.paidAt,
    required this.holdExpiresAt,
    required this.items,
    this.paymentStatus = 'unpaid',
    this.fulfilmentStatus = 'unfulfilled',
    this.fulfilmentMethod = 'pickup',
    this.channel = 'instagram',
    this.deliveryAddress,
    this.customerNote,
    this.orderNumber,
    this.fulfilment,
    this.deliveryType,
    this.sourceChannel = 'instagram',
    this.totalAmountMinor = 0,
    this.neededBy,
    this.notes,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    number: _int(json['number']),
    status: json['status'] as String,
    currency: json['currency'] as String,
    totalMinor: _int(json['total_minor']),
    conversationId: json['conversation_id'] as String?,
    createdAt: _date(json['created_at']),
    paidAt: _dateOrNull(json['paid_at']),
    holdExpiresAt: _dateOrNull(json['hold_expires_at']),
    items: _list(json['items'], OrderItem.fromJson),
    paymentStatus: json['payment_status'] as String? ?? 'unpaid',
    fulfilmentStatus: json['fulfilment_status'] as String? ?? 'unfulfilled',
    fulfilmentMethod: json['fulfilment_method'] as String?,
    channel: json['channel'] as String? ?? 'instagram',
    deliveryAddress: json['delivery_address'] as String?,
    customerNote: json['customer_note'] as String?,
    orderNumber: json['order_number'] as String?,
    fulfilment: json['fulfilment'] as String?,
    deliveryType: json['delivery_type'] as String?,
    sourceChannel: json['source_channel'] as String? ?? 'instagram',
    totalAmountMinor: _intOrNull(json['total_amount_minor']) ?? 0,
    neededBy: json['needed_by'] as String?,
    notes: json['notes'] as String?,
  );

  final String id;
  final int number;
  final String status;
  final String currency;
  final int totalMinor;

  /// Join with [Conversation.id] for the customer: an order carries no customer name of its own.
  final String? conversationId;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? holdExpiresAt;
  final List<OrderItem> items;
  final String paymentStatus;
  final String fulfilmentStatus;
  final String? fulfilmentMethod;
  final String channel;
  final String? deliveryAddress;
  final String? customerNote;
  final String? orderNumber;

  // Backwards-compatibility aliases in the backend's JSON. Prefer the fields above:
  // fulfilment and deliveryType repeat fulfilmentMethod, sourceChannel repeats channel,
  // totalAmountMinor repeats totalMinor, notes repeats customerNote.
  final String? fulfilment;
  final String? deliveryType;
  final String sourceChannel;
  final int totalAmountMinor;

  /// Free text from the scheduled date and window, e.g. "2026-11-06 6 pm". Not a parseable date.
  final String? neededBy;
  final String? notes;

  /// Units across all the lines.
  int get quantity => items.fold(0, (sum, item) => sum + item.quantity);

}

class MarkPaidRequest {
  const MarkPaidRequest({this.method = 'upi', this.referenceId});

  /// "upi", "cash" or "card".
  final String method;
  final String? referenceId;

  Map<String, dynamic> toJson() => {'method': method, 'reference_id': ?referenceId};
}

class OrderTimelineEvent {
  const OrderTimelineEvent({
    required this.id,
    required this.orderId,
    required this.fromStatus,
    required this.toStatus,
    required this.triggeredBy,
    required this.comment,
    required this.createdAt,
  });

  factory OrderTimelineEvent.fromJson(Map<String, dynamic> json) => OrderTimelineEvent(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    fromStatus: json['from_status'] as String?,
    toStatus: json['to_status'] as String,
    triggeredBy: json['triggered_by'] as String,
    comment: json['comment'] as String?,
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String orderId;
  final String? fromStatus;
  final String toStatus;
  final String triggeredBy;
  final String? comment;
  final DateTime createdAt;
}

class UpdateOrderStatusRequest {
  const UpdateOrderStatusRequest({required this.status, this.comment});

  final String status;
  final String? comment;

  Map<String, dynamic> toJson() => {'status': status, 'comment': ?comment};
}

class CancelOrderRequest {
  const CancelOrderRequest({this.reason});

  /// Up to 500 characters.
  final String? reason;

  Map<String, dynamic> toJson() => {'reason': ?reason};
}

class PaymentLinkResponse {
  const PaymentLinkResponse({
    required this.orderId,
    required this.orderNumber,
    required this.paymentMethod,
    required this.paymentLink,
    required this.currency,
    required this.totalMinor,
  });

  factory PaymentLinkResponse.fromJson(Map<String, dynamic> json) => PaymentLinkResponse(
    orderId: json['order_id'] as String,
    orderNumber: _int(json['order_number']),
    paymentMethod: json['payment_method'] as String,
    paymentLink: json['payment_link'] as String,
    currency: json['currency'] as String,
    totalMinor: _int(json['total_minor']),
  );

  final String orderId;
  final int orderNumber;

  /// "upi" or "paypal".
  final String paymentMethod;
  final String paymentLink;
  final String currency;
  final int totalMinor;
}

class RefundRequest {
  const RefundRequest({this.reason, this.restock = true});

  final String? reason;
  final bool restock;

  Map<String, dynamic> toJson() => {'reason': ?reason, 'restock': restock};
}

class RefundResponse {
  const RefundResponse({
    required this.orderId,
    required this.refundId,
    required this.amountMinor,
    required this.currency,
    required this.status,
  });

  factory RefundResponse.fromJson(Map<String, dynamic> json) => RefundResponse(
    orderId: json['order_id'] as String,
    refundId: json['refund_id'] as String,
    amountMinor: _int(json['amount_minor']),
    currency: json['currency'] as String,
    status: json['status'] as String,
  );

  final String orderId;
  final String refundId;
  final int amountMinor;
  final String currency;

  /// "pending", "completed" or "failed".
  final String status;
}

class CreateInvoiceRequest {
  const CreateInvoiceRequest({this.customerName, this.customerEmail});

  final String? customerName;
  final String? customerEmail;

  Map<String, dynamic> toJson() => {'customer_name': ?customerName, 'customer_email': ?customerEmail};
}

class CreateInvoiceResponse {
  const CreateInvoiceResponse({
    required this.orderId,
    required this.invoiceId,
    required this.payerViewUrl,
  });

  factory CreateInvoiceResponse.fromJson(Map<String, dynamic> json) => CreateInvoiceResponse(
    orderId: json['order_id'] as String,
    invoiceId: json['invoice_id'] as String,
    payerViewUrl: json['payer_view_url'] as String,
  );

  final String orderId;
  final String invoiceId;
  final String payerViewUrl;
}

// Ask me ---------------------------------------------------------------------------------------

class Question {
  const Question({
    required this.id,
    required this.conversationId,
    required this.question,
    required this.status,
    required this.answer,
    required this.createdAt,
    required this.answeredAt,
    this.windowClosesAt,
    this.windowState,
    this.answerDelivery,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    question: json['question'] as String,
    status: json['status'] as String,
    answer: json['answer'] as String?,
    createdAt: _date(json['created_at']),
    answeredAt: _dateOrNull(json['answered_at']),
    windowClosesAt: _dateOrNull(json['window_closes_at']),
    windowState: json['window_state'] as String?,
    answerDelivery: json['answer_delivery'] as String?,
  );

  final String id;
  final String conversationId;
  final String question;

  /// "open", "answered" or "closed".
  final String status;
  final String? answer;
  final DateTime createdAt;
  final DateTime? answeredAt;

  /// Instagram's 24-hour window for this customer: the Ask me countdown.
  final DateTime? windowClosesAt;

  /// "open", "closing", "human_agent_only" or "closed".
  final String? windowState;

  /// How the answer reached the customer: "sent", "pending_window", "human_agent" or "expired".
  final String? answerDelivery;
}

class Answer {
  const Answer({required this.answer, this.always = false});

  /// 1 to 1000 characters.
  final String answer;

  /// "Always answer this way": the agent gives this answer to the same question from now on.
  final bool always;

  Map<String, dynamic> toJson() => {'answer': answer, 'always': always};
}

class MemoryFact {
  const MemoryFact({required this.key, required this.value, required this.updatedAt});

  factory MemoryFact.fromJson(Map<String, dynamic> json) => MemoryFact(
    key: json['key'] as String,
    value: json['value'],
    updatedAt: _date(json['updated_at']),
  );

  final String key;

  /// Any JSON value.
  final Object? value;
  final DateTime updatedAt;
}

// Chats ----------------------------------------------------------------------------------------

class Conversation {
  const Conversation({
    required this.id,
    required this.channel,
    required this.customerHandle,
    required this.agentActive,
    required this.agentPausedReason,
    required this.lastMessageSender,
    required this.lastMessageBody,
    required this.lastMessageAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    channel: json['channel'] as String,
    customerHandle: json['customer_handle'] as String,
    agentActive: json['agent_active'] as bool,
    agentPausedReason: json['agent_paused_reason'] as String?,
    lastMessageSender: json['last_message_sender'] as String?,
    lastMessageBody: json['last_message_body'] as String?,
    lastMessageAt: _dateOrNull(json['last_message_at']),
  );

  final String id;
  final String channel;

  /// The customer's name if known, otherwise their channel id.
  final String customerHandle;
  final bool agentActive;
  final String? agentPausedReason;
  final String? lastMessageSender;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.direction,
    required this.sender,
    required this.body,
    required this.status,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    direction: json['direction'] as String,
    sender: json['sender'] as String,
    body: json['body'] as String,
    status: json['status'] as String,
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String direction;

  /// "customer", "agent", "merchant" or "system".
  final String sender;
  final String body;
  final String status;
  final DateTime createdAt;

  bool get fromCustomer => sender == 'customer';
  bool get isDraft => status == 'draft';
}

class AgentSwitch {
  const AgentSwitch({required this.active});

  factory AgentSwitch.fromJson(Map<String, dynamic> json) =>
      AgentSwitch(active: json['active'] as bool);

  final bool active;

  Map<String, dynamic> toJson() => {'active': active};
}

class DraftApproval {
  const DraftApproval({this.text});

  /// The merchant's edit, up to 2000 characters. Left out: the draft goes as written.
  final String? text;

  Map<String, dynamic> toJson() => {'text': ?text};
}

// Catalog --------------------------------------------------------------------------------------

class ProductVariantDetail {
  const ProductVariantDetail({
    required this.id,
    required this.sku,
    required this.name,
    required this.priceMinor,
    this.compareAtPriceMinor,
    this.costPriceMinor,
    required this.currency,
    this.stockMode,
    this.shelfLifeDays,
    this.attributes = const {},
    required this.isActive,
  });

  factory ProductVariantDetail.fromJson(Map<String, dynamic> json) => ProductVariantDetail(
    id: json['id'] as String,
    sku: json['sku'] as String?,
    name: json['name'] as String?,
    priceMinor: _int(json['price_minor']),
    compareAtPriceMinor: _intOrNull(json['compare_at_price_minor']),
    costPriceMinor: _intOrNull(json['cost_price_minor']),
    currency: json['currency'] as String,
    stockMode: json['stock_mode'] as String?,
    shelfLifeDays: _intOrNull(json['shelf_life_days']),
    attributes: _map(json['attributes']),
    isActive: json['is_active'] as bool,
  );

  final String id;
  final String? sku;
  final String? name;
  final int priceMinor;
  final int? compareAtPriceMinor;
  final int? costPriceMinor;
  final String currency;
  final String? stockMode;
  final int? shelfLifeDays;
  final Map<String, dynamic> attributes;
  final bool isActive;
}

class ProductAliasDetail {
  const ProductAliasDetail({
    required this.id,
    required this.aliasText,
    required this.confidenceSource,
    required this.createdAt,
  });

  factory ProductAliasDetail.fromJson(Map<String, dynamic> json) => ProductAliasDetail(
    id: json['id'] as String,
    aliasText: json['alias_text'] as String,
    confidenceSource: json['confidence_source'] as String,
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String aliasText;
  final String confidenceSource;
  final DateTime createdAt;
}

class ProductDetail {
  const ProductDetail({
    required this.id,
    required this.name,
    this.title,
    this.description,
    this.category,
    this.baseImageUrl,
    required this.stockMode,
    this.shelfLifeDays,
    this.attributes = const {},
    required this.isActive,
    this.variants = const [],
    this.aliases = const [],
  });

  factory ProductDetail.fromJson(Map<String, dynamic> json) => ProductDetail(
    id: json['id'] as String,
    name: json['name'] as String,
    title: json['title'] as String?,
    description: json['description'] as String?,
    category: json['category'] as String?,
    baseImageUrl: json['base_image_url'] as String?,
    stockMode: json['stock_mode'] as String? ?? StockMode.daily,
    shelfLifeDays: _intOrNull(json['shelf_life_days']),
    attributes: _map(json['attributes']),
    isActive: json['is_active'] as bool,
    variants: _list(json['variants'], ProductVariantDetail.fromJson),
    aliases: _list(json['aliases'], ProductAliasDetail.fromJson),
  );

  final String id;
  final String name;
  final String? title;
  final String? description;
  final String? category;
  final String? baseImageUrl;
  final String stockMode;
  final int? shelfLifeDays;
  final Map<String, dynamic> attributes;
  final bool isActive;
  final List<ProductVariantDetail> variants;
  final List<ProductAliasDetail> aliases;
}

/// Only the fields that are set are sent; the others stay as they are.
class ProductUpdate {
  const ProductUpdate({
    this.name,
    this.title,
    this.description,
    this.category,
    this.baseImageUrl,
    this.attributes,
  });

  final String? name;
  final String? title;
  final String? description;
  final String? category;
  final String? baseImageUrl;
  final Map<String, dynamic>? attributes;

  Map<String, dynamic> toJson() => {
    'name': ?name,
    'title': ?title,
    'description': ?description,
    'category': ?category,
    'base_image_url': ?baseImageUrl,
    'attributes': ?attributes,
  };
}

class CreateAliasRequest {
  const CreateAliasRequest({required this.aliasText});

  /// 1 to 150 characters.
  final String aliasText;

  Map<String, dynamic> toJson() => {'alias_text': aliasText};
}

class CatalogSearchItem {
  const CatalogSearchItem({
    required this.productId,
    required this.productName,
    this.category,
    this.attributes = const {},
    this.matchedAlias,
    this.similarity = 0,
    this.variants = const [],
  });

  factory CatalogSearchItem.fromJson(Map<String, dynamic> json) => CatalogSearchItem(
    productId: json['product_id'] as String,
    productName: json['product_name'] as String,
    category: json['category'] as String?,
    attributes: _map(json['attributes']),
    matchedAlias: json['matched_alias'] as String?,
    similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
    variants: _list(json['variants'], ProductVariantDetail.fromJson),
  );

  final String productId;
  final String productName;
  final String? category;
  final Map<String, dynamic> attributes;
  final String? matchedAlias;
  final double similarity;
  final List<ProductVariantDetail> variants;
}

class CatalogSearchResponse {
  const CatalogSearchResponse({
    required this.query,
    required this.totalResults,
    required this.items,
  });

  factory CatalogSearchResponse.fromJson(Map<String, dynamic> json) => CatalogSearchResponse(
    query: json['query'] as String,
    totalResults: _int(json['total_results']),
    items: _list(json['items'], CatalogSearchItem.fromJson),
  );

  final String query;
  final int totalResults;
  final List<CatalogSearchItem> items;
}

// Stories (stories.py) ---------------------------------------------------------------------------

class Story {
  const Story({
    required this.storyId,
    required this.itemIds,
    required this.caption,
    required this.expiresAt,
  });

  factory Story.fromJson(Map<String, dynamic> json) => Story(
    storyId: json['story_id'] as String,
    itemIds: [for (final id in (json['item_ids'] as List<dynamic>?) ?? const []) id as String],
    caption: json['caption'] as String?,
    expiresAt: _date(json['expires_at']),
  );

  final String storyId;

  /// Short item refs, not UUIDs: compare with [itemRefOf] of a [StockRow.variantId].
  final List<String> itemIds;
  final String? caption;
  final DateTime expiresAt;
}

class StoryConfirmation {
  const StoryConfirmation({required this.itemIds});

  /// Short item refs ([itemRefOf]) of items in today's stock, up to 20.
  final List<String> itemIds;

  Map<String, dynamic> toJson() => {'item_ids': itemIds};
}

class PostLink {
  const PostLink({required this.igMediaId});

  final String igMediaId;

  Map<String, dynamic> toJson() => {'ig_media_id': igMediaId};
}

class MenuImage {
  const MenuImage({this.url});

  /// Null clears the menu photo.
  final String? url;

  Map<String, dynamic> toJson() => {'url': url};
}

// Simulator (simulator.py) -----------------------------------------------------------------------

class SimulatedMessage {
  const SimulatedMessage({this.text = '', this.quickReply, this.customer = 'tester'});

  final String text;

  /// A tapped button's payload.
  final String? quickReply;
  final String customer;

  Map<String, dynamic> toJson() => {
    'text': text,
    'quick_reply': ?quickReply,
    'customer': customer,
  };
}

class SimulatorButton {
  const SimulatorButton({required this.title, required this.payload});

  factory SimulatorButton.fromJson(Map<String, dynamic> json) =>
      SimulatorButton(title: json['title'] as String, payload: json['payload'] as String);

  final String title;
  final String payload;
}

/// `messages[]` of SimulatorChat. Unlike [ChatMessage] it has buttons and an `at`, no direction.
class SimulatorMessage {
  const SimulatorMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.status,
    this.buttons = const [],
    required this.at,
  });

  factory SimulatorMessage.fromJson(Map<String, dynamic> json) => SimulatorMessage(
    id: json['id'] as String,
    sender: json['sender'] as String,
    body: json['body'] as String,
    status: json['status'] as String,
    buttons: _list(json['buttons'], SimulatorButton.fromJson),
    at: _date(json['at']),
  );

  final String id;
  final String sender;
  final String body;
  final String status;
  final List<SimulatorButton> buttons;
  final DateTime at;

  bool get fromCustomer => sender == 'customer';
}

/// `turn` of SimulatorChat: the latest turn of the assistant.
class SimulatorTurn {
  const SimulatorTurn({
    required this.id,
    required this.status,
    this.stageBefore,
    this.stageAfter,
    this.playbook,
    this.tools = const [],
    this.modelCalls,
    this.costUsd,
    this.latencyMs,
  });

  factory SimulatorTurn.fromJson(Map<String, dynamic> json) => SimulatorTurn(
    id: json['id'] as String,
    status: json['status'] as String,
    stageBefore: json['stage_before'] as String?,
    stageAfter: json['stage_after'] as String?,
    playbook: json['playbook'] as String?,
    tools: [for (final tool in (json['tools'] as List<dynamic>?) ?? const []) tool as String],
    modelCalls: _intOrNull(json['model_calls']),
    costUsd: (json['cost_usd'] as num?)?.toDouble(),
    latencyMs: _intOrNull(json['latency_ms']),
  );

  final String id;
  final String status;
  final String? stageBefore;
  final String? stageAfter;
  final String? playbook;
  final List<String> tools;
  final int? modelCalls;

  /// An operator figure for debugging, not money the app should show as a price.
  final double? costUsd;
  final int? latencyMs;
}

class SimulatorChat {
  const SimulatorChat({this.messages = const [], this.turn});

  factory SimulatorChat.fromJson(Map<String, dynamic> json) => SimulatorChat(
    messages: _list(json['messages'], SimulatorMessage.fromJson),
    turn: json['turn'] == null ? null : SimulatorTurn.fromJson(json['turn'] as _Json),
  );

  final List<SimulatorMessage> messages;
  final SimulatorTurn? turn;
}
