/// Customers, derived on the phone.
///
/// BACKEND GAP: there is no customers endpoint. A customer here is one conversation plus the orders
/// joined on `conversation_id`, limited to the latest 200 orders. The same person on two channels
/// shows as two customers. Name, phone, language and country aren't exposed by the API.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../chats/chats_providers.dart';
import 'order_logic.dart';
import 'orders_providers.dart';

class CustomerSummary {
  CustomerSummary(this.conversation, List<Order> orders)
    : orders = [...orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final Conversation conversation;

  /// Newest first.
  final List<Order> orders;

  String get id => conversation.id;

  /// The customer's name if the server knows it, otherwise their channel id.
  String get handle => conversation.customerHandle;

  List<Order> get paidOrders => orders.where(countsAsSale).toList();

  int get paidCount => paidOrders.length;

  bool get isRepeat => paidCount > 2;

  Map<String, int> get spentByCurrency {
    final out = <String, int>{};
    for (final order in paidOrders) {
      out[order.currency] = (out[order.currency] ?? 0) + order.totalMinor;
    }
    return out;
  }

  /// `₹2,500`, or `₹2,500 + US$12.00`. Null when nothing is spent. Never adds currencies.
  String? get spentText => joinMoney(spentByCurrency);

  /// `₹1,250`, per currency, rounded down in minor units.
  String? get perOrderText {
    final counts = <String, int>{};
    for (final order in paidOrders) {
      counts[order.currency] = (counts[order.currency] ?? 0) + 1;
    }
    return joinMoney({
      for (final entry in spentByCurrency.entries) entry.key: entry.value ~/ counts[entry.key]!,
    });
  }

  /// The address on their most recent order that has one.
  String? get lastAddress {
    for (final order in orders) {
      final address = order.deliveryAddress?.trim();
      if (address != null && address.isNotEmpty) return address;
    }
    return null;
  }

  DateTime? get firstOrderAt => orders.isEmpty ? null : orders.last.createdAt;

  DateTime? get lastActivity {
    final message = conversation.lastMessageAt;
    final order = orders.isEmpty ? null : orders.first.createdAt;
    if (message == null) return order;
    if (order == null) return message;
    return message.isAfter(order) ? message : order;
  }
}

String? joinMoney(Map<String, int> byCurrency) {
  if (byCurrency.isEmpty) return null;
  final keys = byCurrency.keys.toList()
    ..sort((a, b) {
      if (a == 'INR') return -1;
      if (b == 'INR') return 1;
      return a.compareTo(b);
    });
  return keys.map((key) => money(byCurrency[key]!, key)).join(' + ');
}

/// Most money first, in the shop's main currency, then most paid orders, then latest activity.
List<CustomerSummary> customersFrom(List<Conversation> conversations, List<Order> orders) {
  final byConversation = <String, List<Order>>{};
  for (final order in orders) {
    final id = order.conversationId;
    if (id != null) (byConversation[id] ??= []).add(order);
  }
  final customers = [
    for (final conversation in conversations)
      CustomerSummary(conversation, byConversation[conversation.id] ?? const []),
  ];
  final main = mainCurrencyOf(customers);
  int spent(CustomerSummary c) => c.spentByCurrency[main] ?? 0;
  customers.sort((a, b) {
    final bySpent = spent(b).compareTo(spent(a));
    if (bySpent != 0) return bySpent;
    final byCount = b.paidCount.compareTo(a.paidCount);
    if (byCount != 0) return byCount;
    final aTime = a.lastActivity, bTime = b.lastActivity;
    if (aTime == null || bTime == null) return aTime == bTime ? 0 : (aTime == null ? 1 : -1);
    return bTime.compareTo(aTime);
  });
  return customers;
}

/// INR when any customer paid in it, otherwise the first currency by name.
String? mainCurrencyOf(List<CustomerSummary> customers) {
  final currencies = {for (final c in customers) ...c.spentByCurrency.keys};
  if (currencies.isEmpty) return null;
  if (currencies.contains('INR')) return 'INR';
  return (currencies.toList()..sort()).first;
}

class CustomerStats {
  const CustomerStats({required this.buyers, required this.backPercent, required this.perOrder});

  final int buyers;
  final int backPercent;

  /// In the main currency. Null when nobody has paid.
  final String? perOrder;
}

CustomerStats customerStatsOf(List<CustomerSummary> customers) {
  final buyers = customers.where((c) => c.paidCount > 0).toList();
  final back = buyers.where((c) => c.paidCount > 1).length;
  final main = mainCurrencyOf(customers);
  var total = 0, count = 0;
  for (final buyer in buyers) {
    for (final order in buyer.paidOrders.where((o) => o.currency == main)) {
      total += order.totalMinor;
      count++;
    }
  }
  return CustomerStats(
    buyers: buyers.length,
    // Whole-number arithmetic, rounded to nearest.
    backPercent: buyers.isEmpty ? 0 : (back * 200 + buyers.length) ~/ (buyers.length * 2),
    perOrder: main == null || count == 0 ? null : money(total ~/ count, main),
  );
}

enum CustomerFilter { all, repeat, fresh }

bool matchesCustomer(CustomerSummary customer, CustomerFilter filter, String query) {
  final inFilter = switch (filter) {
    CustomerFilter.all => true,
    CustomerFilter.repeat => customer.isRepeat,
    CustomerFilter.fresh => customer.paidCount <= 1,
  };
  return inFilter && customer.handle.toLowerCase().contains(query.trim().toLowerCase());
}

/// Conversations joined to orders. Fails when either fails, as both are needed to be right.
final customersProvider = FutureProvider.autoDispose<List<CustomerSummary>>((ref) async {
  final both = await Future.wait<Object>([
    ref.watch(conversationsProvider.future),
    ref.watch(ordersProvider.future),
  ]);
  return customersFrom(both[0] as List<Conversation>, both[1] as List<Order>);
});

/// What sellix remembers about a customer, from the conversation.
final customerFactsProvider = FutureProvider.autoDispose.family<List<MemoryFact>, String>(
  (ref, conversationId) => ref.watch(sellixApiProvider).customerMemory(conversationId),
);
