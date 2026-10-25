/// Response types of the sellix /v1 API (see backend/app/api/v1/schemas.py).
library;

DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken, required this.expiresIn});

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: json['expires_in'] as int,
      );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
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

class ConnectedChannel {
  const ConnectedChannel({required this.channel, required this.username, required this.status});

  factory ConnectedChannel.fromJson(Map<String, dynamic> json) => ConnectedChannel(
        channel: json['channel'] as String,
        username: json['username'] as String?,
        status: json['status'] as String,
      );

  final String channel;
  final String? username;
  final String status;
}

class Me {
  const Me({
    required this.userId,
    required this.merchant,
    required this.role,
    required this.channels,
    this.onboardingCompleted = true,
  });

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        userId: json['user_id'] as String,
        merchant: Merchant.fromJson(json['merchant'] as Map<String, dynamic>),
        role: json['role'] as String,
        channels: [
          for (final channel in json['channels'] as List<dynamic>)
            ConnectedChannel.fromJson(channel as Map<String, dynamic>),
        ],
        onboardingCompleted: json['onboarding_completed'] as bool? ?? true,
      );

  final String userId;
  final Merchant merchant;
  final String role;
  final List<ConnectedChannel> channels;

  /// False until the merchant finishes (or skips) the guided setup after their first sign-in.
  final bool onboardingCompleted;
}

class StockRow {
  const StockRow({
    required this.variantId,
    required this.product,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.opening,
    required this.held,
    required this.sold,
    required this.available,
  });

  factory StockRow.fromJson(Map<String, dynamic> json) => StockRow(
        variantId: json['variant_id'] as String,
        product: json['product'] as String,
        variant: json['variant'] as String?,
        priceMinor: json['price_minor'] as int,
        currency: json['currency'] as String,
        opening: (json['opening'] as int) + (json['restocked'] as int),
        held: json['held'] as int,
        sold: (json['sold'] as int) + (json['counter_sales'] as int),
        available: json['available'] as int,
      );

  final String variantId;
  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;
  final int opening;
  final int held;
  final int sold;
  final int available;

  String get label => variant == null ? product : '$product ($variant)';
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
        businessDate: DateTime.parse(json['business_date'] as String),
        agentEnabled: json['agent_enabled'] as bool,
        stock: [
          for (final row in json['stock'] as List<dynamic>) StockRow.fromJson(row as Map<String, dynamic>),
        ],
        openQuestions: json['open_questions'] as int,
        ordersAwaitingPayment: json['orders_awaiting_payment'] as int,
        ordersPaid: json['orders_paid'] as int,
        revenueMinorByCurrency: (json['revenue_minor_by_currency'] as Map<String, dynamic>)
            .map((currency, amount) => MapEntry(currency, amount as int)),
      );

  final DateTime businessDate;
  final bool agentEnabled;
  final List<StockRow> stock;
  final int openQuestions;
  final int ordersAwaitingPayment;
  final int ordersPaid;
  final Map<String, int> revenueMinorByCurrency;
}

/// One line of the morning stock update.
class StockLine {
  const StockLine({
    required this.product,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.quantity,
  });

  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'product': product,
        'variant': variant,
        'price_minor': priceMinor,
        'currency': currency,
        'quantity': quantity,
      };
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
        quantity: json['quantity'] as int,
        unitPriceMinor: json['unit_price_minor'] as int,
      );

  final String product;
  final String? variant;
  final int quantity;
  final int unitPriceMinor;

  String get label => variant == null ? product : '$product ($variant)';
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.status,
    required this.currency,
    required this.totalMinor,
    required this.fulfilment,
    required this.deliveryAddress,
    required this.neededBy,
    required this.notes,
    required this.createdAt,
    required this.holdExpiresAt,
    required this.items,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        number: json['number'] as int,
        status: json['status'] as String,
        currency: json['currency'] as String,
        totalMinor: json['total_minor'] as int,
        fulfilment: json['fulfilment'] as String?,
        deliveryAddress: json['delivery_address'] as String?,
        neededBy: json['needed_by'] as String?,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        holdExpiresAt: _date(json['hold_expires_at']),
        items: [
          for (final item in json['items'] as List<dynamic>) OrderItem.fromJson(item as Map<String, dynamic>),
        ],
      );

  final String id;
  final int number;
  final String status;
  final String currency;
  final int totalMinor;
  final String? fulfilment;
  final String? deliveryAddress;
  final String? neededBy;
  final String? notes;
  final DateTime createdAt;
  final DateTime? holdExpiresAt;
  final List<OrderItem> items;
}

class Question {
  const Question({
    required this.id,
    required this.conversationId,
    required this.question,
    required this.status,
    required this.answer,
    required this.createdAt,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        question: json['question'] as String,
        status: json['status'] as String,
        answer: json['answer'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String conversationId;
  final String question;
  final String status;
  final String? answer;
  final DateTime createdAt;
}

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
        lastMessageAt: _date(json['last_message_at']),
      );

  final String id;
  final String channel;
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
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String direction;
  final String sender;
  final String body;
  final String status;
  final DateTime createdAt;

  bool get fromCustomer => sender == 'customer';
}

class ShopProfile {
  const ShopProfile({required this.version, required this.contentMd});

  factory ShopProfile.fromJson(Map<String, dynamic> json) =>
      ShopProfile(version: json['version'] as int, contentMd: json['content_md'] as String);

  final int version;
  final String contentMd;
}

/// The merchant's onboarding answers. Every field is optional: each step can be skipped.
class OnboardingAnswers {
  const OnboardingAnswers(this.values);

  factory OnboardingAnswers.fromJson(Map<String, dynamic> json) =>
      OnboardingAnswers({for (final entry in json.entries) if (entry.value != null) entry.key: entry.value as Object});

  /// Keys as in backend/app/modules/shop_profile/schemas.py: text answers are strings,
  /// `tone` is "friendly" or "formal", `emoji` is a bool.
  final Map<String, Object> values;

  String text(String key) => values[key] is String ? values[key]! as String : '';

  Map<String, dynamic> toJson() => values;
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
        answers: OnboardingAnswers.fromJson(json['answers'] as Map<String, dynamic>),
        completed: json['completed'] as bool,
        channels: [
          for (final channel in json['channels'] as List<dynamic>)
            ConnectedChannel.fromJson(channel as Map<String, dynamic>),
        ],
        paymentsReady: json['payments_ready'] as bool,
      );

  final String shopName;
  final OnboardingAnswers answers;
  final bool completed;
  final List<ConnectedChannel> channels;
  final bool paymentsReady;
}
