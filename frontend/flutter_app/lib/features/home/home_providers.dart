/// Data behind Home, Needs you and Notifications. Everything is derived from real endpoints.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/nav_badges.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme_mode.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import '../orders/orders_providers.dart';
import '../stock/stock_providers.dart';

final homeMeProvider = FutureProvider.autoDispose<Me>((ref) => ref.watch(sellixApiProvider).me());

final closedQuestionsProvider = FutureProvider.autoDispose<List<Question>>(
  (ref) => ref.watch(sellixApiProvider).questions(status: 'closed'),
);

bool _isPaid(Order order) => order.paymentStatus == 'paid' || order.paymentStatus == 'partially_refunded';

bool _isClosed(Order order) =>
    order.status == OrderStatus.cancelled ||
    order.status == OrderStatus.expired ||
    order.status == OrderStatus.refunded;

/// Cancelled, yet the money is still with the shop.
bool orderRefundDue(Order order) => _isClosed(order) && order.paymentStatus == 'paid';

/// Whether the merchant must do something next on this order. Mirrors `tabOf(...) == todo` in
/// `features/orders/order_logic.dart`, so Home and the Orders tab show the same list and count.
// BACKEND GAP: no "customer says they paid" state, so the prototype's "Confirm payment" orders
// can't be told apart from other unpaid orders; those stay in "Waiting payment".
// BACKEND GAP: `needed_by` is free text, so pre-orders can't be left out of this list.
bool orderIsToAct(Order order) {
  if (orderRefundDue(order)) return true;
  if (_isClosed(order) || !_isPaid(order)) return false;
  return switch (order.status) {
    OrderStatus.paid || OrderStatus.confirmed => true,
    OrderStatus.ready => !_isPickup(order),
    _ => false,
  };
}

bool _isPickup(Order order) => switch (order.fulfilmentMethod) {
  'delivery' || 'local_delivery' || 'courier' || 'digital' => false,
  _ => true,
};

/// A paid order nobody has accepted yet, in the prototype's "New order" state.
bool orderIsNew(Order order) => _isPaid(order) && order.status == OrderStatus.paid;

/// How an order's state reads on a row: the prototype's `ORDER_STATE`, from the API's statuses.
class OrderStateLabel {
  const OrderStateLabel(this.label, this.icon, [this.tone = SxChipTone.neutral]);

  final String label;
  final IconData icon;
  final SxChipTone tone;
}

OrderStateLabel orderStateOf(Order order) {
  if (orderRefundDue(order)) {
    return const OrderStateLabel('Refund due', TablerIcons.arrow_back_up, SxChipTone.attention);
  }
  switch (order.status) {
    case OrderStatus.expired:
      return const OrderStateLabel('Expired', TablerIcons.clock_x);
    case OrderStatus.cancelled:
      return const OrderStateLabel('Cancelled', TablerIcons.ban);
    case OrderStatus.refunded:
      return const OrderStateLabel('Refunded', TablerIcons.arrow_back_up);
  }
  if (!_isPaid(order)) return const OrderStateLabel('Waiting payment', TablerIcons.clock);
  return switch (order.status) {
    OrderStatus.completed => const OrderStateLabel('Completed', TablerIcons.check, SxChipTone.positive),
    OrderStatus.delivered => const OrderStateLabel('Delivered', TablerIcons.check, SxChipTone.positive),
    OrderStatus.confirmed => const OrderStateLabel('Accepted', TablerIcons.check),
    OrderStatus.ready => OrderStateLabel(
      _isPickup(order)
          ? 'Ready for pickup'
          : order.fulfilmentMethod == 'digital'
          ? 'Accepted'
          : 'Packed',
      TablerIcons.package,
    ),
    _ => const OrderStateLabel('New order', TablerIcons.bell_ringing, SxChipTone.attention),
  };
}

/// `2 × Item A + 1 more`.
String itemsLine(Order order) {
  if (order.items.isEmpty) return 'No items';
  final first = order.items.first;
  final more = order.items.length > 1 ? ' + ${order.items.length - 1} more' : '';
  return '${first.quantity > 1 ? '${first.quantity} × ' : ''}${first.label}$more';
}

SxBrand? brandOfChannel(String channel) => switch (channel) {
  'instagram' => SxBrand.instagram,
  'whatsapp' => SxBrand.whatsapp,
  'messenger' => SxBrand.messenger,
  'facebook' => SxBrand.facebook,
  _ => null,
};

String channelName(String channel) => switch (channel) {
  'instagram' => 'Instagram',
  'whatsapp' => 'WhatsApp',
  'messenger' => 'Messenger',
  'facebook' => 'Facebook',
  _ => channel.isEmpty ? channel : '${channel[0].toUpperCase()}${channel.substring(1)}',
};

/// The currency a screen leads with: INR when there is some, otherwise the largest.
String leadCurrency(Map<String, int> totals, String fallback) {
  if (totals.containsKey('INR')) return 'INR';
  if (totals.isEmpty) return fallback;
  return totals.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Everything Home reads, loaded together so it stays in step and has one retry.
class HomeData {
  HomeData({
    required this.me,
    required this.today,
    required this.openQuestions,
    required this.orders,
    required this.conversations,
  }) : _byId = {for (final chat in conversations) chat.id: chat};

  final Me me;
  final Today today;
  final List<Question> openQuestions;
  final List<Order> orders;
  final List<Conversation> conversations;
  final Map<String, Conversation> _byId;

  Conversation? chatOf(String? conversationId) => _byId[conversationId];

  /// The join the brief asks for: an order carries no customer of its own.
  String customerOf(String? conversationId) => chatOf(conversationId)?.customerHandle ?? 'Customer';

  bool get stockSet => today.stock.any((row) => row.made > 0 || !row.isTracked);

  /// Nothing has happened yet: the prototype's `newShop()`.
  bool get newShop => !stockSet && orders.isEmpty && conversations.isEmpty && openQuestions.isEmpty;

  SxAgentState get agentState {
    if (!today.agentEnabled) return SxAgentState.paused;
    return stockSet ? SxAgentState.live : SxAgentState.waiting;
  }

  bool get whatsappConnected => me.channels.any((c) => c.channel == 'whatsapp' && c.status == 'active');

  bool onToday(DateTime time) => isOnBusinessDate(time, today.businessDate);

  /// Most urgent first: money owed back, new orders, then the rest, oldest first. Same order as the
  /// Orders tab.
  List<Order> get ordersToAct {
    int rank(Order order) => orderRefundDue(order) ? 0 : (order.status == OrderStatus.paid ? 1 : 2);
    return orders.where(orderIsToAct).toList()..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.createdAt.compareTo(b.createdAt);
    });
  }

  /// What the Chats tab shows: chats with an open question. Same count as the chat list.
  int get chatsNeedYou => {for (final q in openQuestions) q.conversationId}.length;

  /// sellix is working a chat, including waiting for payment. Same rule as the chat list.
  bool get sellixOnAChat => conversations.any((chat) {
    final state = chatStateOf(chat, openQuestions, orders);
    return state == ChatState.sellix || state == ChatState.waitingPayment;
  });

  /// Chats sellix is on right now: active today, not waiting on the merchant, not taken over.
  // BACKEND GAP: no per-conversation order stage, so the prototype's "Taking order" isn't shown.
  List<Conversation> get liveChats {
    final asking = {for (final q in openQuestions) q.conversationId};
    return [
      for (final chat in conversations)
        if (chat.agentActive &&
            !asking.contains(chat.id) &&
            chat.lastMessageAt != null &&
            onToday(chat.lastMessageAt!))
          chat,
    ];
  }

  /// Latest order of a chat, if it is still waiting for money.
  bool chatAwaitsPayment(String conversationId) {
    Order? latest;
    for (final order in orders) {
      if (order.conversationId != conversationId) continue;
      if (latest == null || order.createdAt.isAfter(latest.createdAt)) latest = order;
    }
    return latest?.status == OrderStatus.awaitingPayment;
  }

  // BACKEND GAP: no daily chat count; this counts chats whose latest message is today.
  int get chatsToday => conversations.where((c) => c.lastMessageAt != null && onToday(c.lastMessageAt!)).length;

  List<StockRow> get soldOutRows => [
    for (final row in today.stock)
      if (row.isTracked && row.made > 0 && row.available == 0) row,
  ];

  int get stockLeft => today.stock.where((r) => r.isTracked).fold(0, (sum, r) => sum + r.available);
}

final homeDataProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final me = ref.watch(homeMeProvider.future);
  final today = ref.watch(todayProvider.future);
  final open = ref.watch(openQuestionsProvider.future);
  final orders = ref.watch(ordersProvider.future);
  final chats = ref.watch(conversationsProvider.future);
  final loaded = await Future.wait<Object>([me, today, open, orders, chats]);
  return HomeData(
    me: loaded[0] as Me,
    today: loaded[1] as Today,
    openQuestions: loaded[2] as List<Question>,
    orders: loaded[3] as List<Order>,
    conversations: loaded[4] as List<Conversation>,
  );
});

/// Reloads what Home is made of, including anything that failed. Use for retry and pull to refresh.
Future<void> refreshHome(ProviderContainer container) async {
  invalidateHomeSources(container);
  try {
    await container.read(homeDataProvider.future);
  } on Object {
    // SxAsyncView reports a failed reload.
  }
}

void invalidateHomeSources(ProviderContainer container) {
  container
    ..invalidate(homeMeProvider)
    ..invalidate(todayProvider)
    ..invalidate(openQuestionsProvider)
    ..invalidate(ordersProvider)
    ..invalidate(conversationsProvider);
}

/// Feeds the floating nav with real counts. Safe to call from build: it waits for the frame and
/// only writes when something changed.
void pushNavBadges(BuildContext context, WidgetRef ref, HomeData data) {
  final chatsNeedYou = data.chatsNeedYou;
  final chatsLive = data.sellixOnAChat;
  final ordersToAct = data.ordersToAct.length;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final now = ref.read(navBadgesProvider);
    if (now.chatsNeedYou == chatsNeedYou && now.chatsLive == chatsLive && now.ordersToAct == ordersToAct) {
      return;
    }
    ref
        .read(navBadgesProvider.notifier)
        .update(chatsNeedYou: chatsNeedYou, chatsLive: chatsLive, ordersToAct: ordersToAct);
  });
}

/// Notification rows the merchant has read.
// BACKEND GAP: no notifications endpoint, so "read" is kept on this phone only.
class NotificationReadController extends Notifier<Set<String>> {
  static const _key = 'home_notifications_read';

  @override
  Set<String> build() => (ref.read(sharedPreferencesProvider).getStringList(_key) ?? const []).toSet();

  void markRead(Iterable<String> keys) {
    final next = {...state, ...keys};
    if (next.length == state.length) return;
    state = next;
    ref.read(sharedPreferencesProvider).setStringList(_key, next.toList());
  }
}

final notificationReadProvider = NotifierProvider<NotificationReadController, Set<String>>(
  NotificationReadController.new,
);

/// The business day the "sellix noticed" card was turned down, so it stays away until tomorrow.
class NoticeOffController extends Notifier<String?> {
  static const _key = 'home_notice_off';

  @override
  String? build() => ref.read(sharedPreferencesProvider).getString(_key);

  void turnOff(DateTime businessDate) {
    final day = businessDateString(businessDate);
    state = day;
    ref.read(sharedPreferencesProvider).setString(_key, day);
  }
}

final noticeOffProvider = NotifierProvider<NoticeOffController, String?>(NoticeOffController.new);

enum NotificationTone { neutral, attention, positive }

class NotificationRow {
  const NotificationRow({
    required this.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.route,
    this.tone = NotificationTone.neutral,
    this.time,
    this.unread = false,
    this.isTab = false,
  });

  final String key;
  final IconData icon;
  final NotificationTone tone;
  final String title;
  final String body;

  /// Null when the row isn't tied to a moment we know.
  final DateTime? time;
  final String route;

  /// Opens with `go` rather than `push`.
  final bool isTab;
  final bool unread;

  NotificationRow read() => NotificationRow(
    key: key,
    icon: icon,
    tone: tone,
    title: title,
    body: body,
    time: time,
    route: route,
    isTab: isTab,
  );
}

/// One list of what sellix would tell the merchant today, from open questions, orders and stock.
// BACKEND GAP: no notifications endpoint; this is rebuilt from live data on each load.
List<NotificationRow> buildNotifications(HomeData data, Set<String> read) {
  final timed = <NotificationRow>[
    for (final q in data.openQuestions)
      NotificationRow(
        key: 'q:${q.id}',
        icon: TablerIcons.hand_stop,
        tone: NotificationTone.attention,
        title: '${data.customerOf(q.conversationId)} needs you',
        body: q.question,
        time: q.createdAt,
        route: Routes.chat(q.conversationId),
        unread: true,
      ),
    for (final order in data.orders)
      if (orderIsToAct(order) || data.onToday(order.createdAt)) _orderRow(order, data),
  ]..sort((a, b) => b.time!.compareTo(a.time!));

  final soldOut = [
    for (final row in data.soldOutRows)
      NotificationRow(
        key: 'soldout:${businessDateString(data.today.businessDate)}:${row.variantId}',
        icon: TablerIcons.package_off,
        title: '${row.label} sold out',
        body: 'Nothing left for today.',
        route: Routes.stock,
        isTab: true,
      ),
  ];

  // BACKEND GAP: Today has no "stock set at" time.
  final tracked = data.today.stock.where((r) => r.isTracked).fold<int>(0, (sum, r) => sum + r.made);
  return [
    ...timed,
    ...soldOut,
    if (data.stockSet && tracked > 0)
      NotificationRow(
        key: 'stock:${businessDateString(data.today.businessDate)}',
        icon: TablerIcons.sun,
        title: 'Stock is live',
        body: 'You set $tracked ${tracked == 1 ? 'item' : 'items'} for today.',
        route: Routes.stock,
        isTab: true,
      ),
  ].map((row) => read.contains(row.key) ? row.read() : row).toList();
}

NotificationRow _orderRow(Order order, HomeData data) {
  final customer = data.customerOf(order.conversationId);
  final amount = money(order.totalMinor, order.currency);
  final count = order.quantity;
  final summary = '$customer, $count ${count == 1 ? 'item' : 'items'}, $amount.';
  final time = order.paidAt ?? order.createdAt;
  NotificationRow row(
    IconData icon,
    String title,
    String body, {
    NotificationTone tone = NotificationTone.neutral,
    bool unread = false,
  }) => NotificationRow(
    key: 'o:${order.id}:${order.status}',
    icon: icon,
    tone: tone,
    title: title,
    body: body,
    time: time,
    route: Routes.order(order.id),
    unread: unread,
  );

  final no = order.number;
  if (orderRefundDue(order)) {
    return row(
      TablerIcons.arrow_back_up,
      'Refund due: #$no',
      summary,
      tone: NotificationTone.attention,
      unread: true,
    );
  }
  return switch (order.status) {
    OrderStatus.expired => row(TablerIcons.clock_x, 'Expired: #$no', 'Nothing left to confirm.'),
    OrderStatus.cancelled => row(TablerIcons.ban, 'Cancelled: #$no', 'Nothing left to confirm.'),
    OrderStatus.refunded => row(TablerIcons.arrow_back_up, 'Refunded: #$no', summary),
    _ when orderIsNew(order) => row(
      TablerIcons.bell_ringing,
      'New order: #$no',
      '$summary Paid.',
      tone: NotificationTone.attention,
      unread: true,
    ),
    _ when !_isPaid(order) => row(
      TablerIcons.bell_ringing,
      'New order: #$no',
      '$summary Waiting payment.',
      unread: true,
    ),
    _ => row(
      TablerIcons.circle_check,
      'Paid: order #$no',
      summary,
      tone: NotificationTone.positive,
    ),
  };
}
