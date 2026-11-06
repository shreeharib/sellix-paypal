/// What an order means to the merchant, worked out only from fields the API really returns.
///
/// Rules here deliberately stay tighter than the server. `PATCH /orders/{id}/status` accepts any
/// listed status from any other, and `POST /orders/{id}/cancel` accepts paid orders, so this file
/// is what keeps the app to sensible next steps.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../design/design.dart';
import 'orders_providers.dart';

enum OrderTab { todo, moving, waiting, done, all }

enum OrderMethod { pickup, localDelivery, courier, digital }

enum SalesPeriod { day, week, month }

OrderMethod methodOf(Order order) => switch (order.fulfilmentMethod) {
  'delivery' || 'local_delivery' => OrderMethod.localDelivery,
  'courier' => OrderMethod.courier,
  'digital' => OrderMethod.digital,
  _ => OrderMethod.pickup,
};

/// The customer gave money and it has not all gone back.
bool isPaid(Order order) =>
    order.paymentStatus == 'paid' || order.paymentStatus == 'partially_refunded';

bool isClosed(Order order) =>
    order.status == OrderStatus.cancelled ||
    order.status == OrderStatus.expired ||
    order.status == OrderStatus.refunded;

/// Delivered or completed: nothing is left to do for the order itself.
bool isFinished(Order order) =>
    order.status == OrderStatus.delivered || order.status == OrderStatus.completed;

/// Still waiting for money, in a status where confirming the money is safe. `mark-paid` on any
/// other unpaid status re-sells the stock and rewinds the order to `paid`, so it isn't offered.
bool canMarkPaid(Order order) =>
    !isPaid(order) &&
    (order.status == OrderStatus.awaitingPayment ||
        order.status == OrderStatus.pending ||
        order.status == OrderStatus.draft);

/// Cancelled, yet the money is still with the shop: `POST /cancel` never refunds. The order stays
/// on the merchant's list until a real refund goes through.
bool isRefundDue(Order order) =>
    (order.status == OrderStatus.cancelled || order.status == OrderStatus.expired) &&
    order.paymentStatus == 'paid';

/// Only a paid order can be refunded, and the server takes one refund per order.
bool canRefund(Order order) =>
    order.paymentStatus == 'paid' && order.status != OrderStatus.refunded;

/// Finished and closed orders can't be cancelled from the app. The server allows `delivered`.
bool canCancel(Order order) => !isClosed(order) && !isFinished(order);

/// The server gives stock back on a refund only from these statuses (`settle_refund`).
bool refundCanRestock(Order order) =>
    order.status == OrderStatus.paid ||
    order.status == OrderStatus.confirmed ||
    order.status == OrderStatus.completed;

/// Counts as money earned: paid, and not cancelled or refunded since. A part refund has no amount
/// in the API, so it can't be counted honestly.
bool countsAsSale(Order order) => order.paymentStatus == 'paid' && !isClosed(order);

/// One step on an order's own path.
class OrderStage {
  const OrderStage(this.label, this.icon);

  final String label;
  final IconData icon;
}

// BACKEND GAP: the prototype's preparing, out for delivery and shipped stages have no status in
// the API, so they are not shown. Only paid, confirmed, ready, delivered and completed exist.
const _placed = OrderStage('Placed', TablerIcons.receipt);
const _accepted = OrderStage('Accepted', TablerIcons.check);
const _readyPickup = OrderStage('Ready for pickup', TablerIcons.package);
const _packed = OrderStage('Packed', TablerIcons.package);
const _pickedUp = OrderStage('Picked up', TablerIcons.flag);
const _delivered = OrderStage('Delivered', TablerIcons.flag);
const _sent = OrderStage('Sent', TablerIcons.send);

List<OrderStage> stagesOf(OrderMethod method) => switch (method) {
  OrderMethod.pickup => const [_placed, _accepted, _readyPickup, _pickedUp],
  OrderMethod.localDelivery || OrderMethod.courier => const [
    _placed,
    _accepted,
    _packed,
    _delivered,
  ],
  OrderMethod.digital => const [_placed, _accepted, _sent],
};

/// Where a status sits on the path of [method]. Statuses before payment read as the first step.
int stageIndexOf(String status, OrderMethod method) {
  final last = stagesOf(method).length - 1;
  return switch (status) {
    OrderStatus.confirmed => 1,
    OrderStatus.ready => method == OrderMethod.digital ? 1 : 2,
    OrderStatus.delivered || OrderStatus.completed => last,
    _ => 0,
  };
}

/// The one step the merchant can take next.
class NextStep {
  const NextStep({
    required this.label,
    required this.icon,
    required this.question,
    required this.doneText,
    required this.task,
    required this.targetStatus,
    this.undoStatus,
  });

  final String label;
  final IconData icon;
  final String question;
  final String doneText;
  final String Function(String name) task;
  final String targetStatus;

  /// The status Undo returns to. Null means no undo.
  final String? undoStatus;

  /// `POST /complete` checks the order was paid, so it's used for this status over the PATCH.
  bool get usesComplete => targetStatus == OrderStatus.completed;
}

/// Next step for a paid, open order. Null for anything else, so nothing moves before payment.
NextStep? nextStepOf(Order order) {
  if (isClosed(order) || !isPaid(order)) return null;
  final method = methodOf(order);
  switch (order.status) {
    case OrderStatus.paid:
      // No undo here: going back to `paid` fires the database trigger that adds the order to the
      // customer's lifetime totals a second time.
      return NextStep(
        label: 'Accept order',
        icon: TablerIcons.check,
        question: 'Accept this order?',
        doneText: 'Order accepted',
        task: (n) => 'Accept $n’s order',
        targetStatus: OrderStatus.confirmed,
      );
    case OrderStatus.confirmed:
      return switch (method) {
        OrderMethod.pickup => NextStep(
          label: 'Mark as ready for pickup',
          icon: TablerIcons.package,
          question: 'Ready for pickup?',
          doneText: 'Ready for pickup',
          task: (n) => 'Get $n’s order ready',
          targetStatus: OrderStatus.ready,
          undoStatus: OrderStatus.confirmed,
        ),
        OrderMethod.localDelivery || OrderMethod.courier => NextStep(
          label: 'Mark as packed',
          icon: TablerIcons.package,
          question: 'Is it packed?',
          doneText: 'Marked as packed',
          task: (n) => 'Pack $n’s order',
          targetStatus: OrderStatus.ready,
          undoStatus: OrderStatus.confirmed,
        ),
        OrderMethod.digital => NextStep(
          label: 'Mark as sent',
          icon: TablerIcons.send,
          question: 'Did you send it?',
          doneText: 'Marked as sent',
          task: (n) => 'Send $n’s order',
          targetStatus: OrderStatus.completed,
          undoStatus: OrderStatus.confirmed,
        ),
      };
    case OrderStatus.ready:
      return switch (method) {
        OrderMethod.localDelivery || OrderMethod.courier => NextStep(
          label: 'Mark as delivered',
          icon: TablerIcons.flag,
          question: 'Is it delivered?',
          doneText: 'Marked as delivered',
          task: (n) => 'Deliver $n’s order',
          targetStatus: OrderStatus.delivered,
          undoStatus: OrderStatus.ready,
        ),
        OrderMethod.pickup || OrderMethod.digital => NextStep(
          label: method == OrderMethod.pickup ? 'Mark as picked up' : 'Mark as sent',
          icon: method == OrderMethod.pickup ? TablerIcons.flag : TablerIcons.send,
          question: method == OrderMethod.pickup ? 'Did they pick it up?' : 'Did you send it?',
          doneText: method == OrderMethod.pickup ? 'Marked as picked up' : 'Marked as sent',
          task: (n) => method == OrderMethod.pickup ? 'Hand over $n’s order' : 'Send $n’s order',
          targetStatus: OrderStatus.completed,
          undoStatus: OrderStatus.ready,
        ),
      };
    default:
      return null;
  }
}

/// The status "Go back one stage" returns to, or null. Never `paid`: see [nextStepOf].
/// A finished order can only go back shortly after, for a mistaken tap.
String? previousStatusOf(Order order, {DateTime? lastChange, DateTime? now}) {
  if (isClosed(order) || !isPaid(order)) return null;
  if (order.status == OrderStatus.ready) return OrderStatus.confirmed;
  if (!isFinished(order) || lastChange == null) return null;
  if ((now ?? DateTime.now()).difference(lastChange) > const Duration(minutes: 15)) return null;
  return methodOf(order) == OrderMethod.digital ? OrderStatus.confirmed : OrderStatus.ready;
}

/// Chip and grouping for one order.
class OrderLook {
  const OrderLook(this.label, this.tone, this.icon);

  final String label;
  final SxChipTone tone;
  final IconData icon;
}

OrderLook lookOf(Order order) {
  if (isRefundDue(order)) {
    return const OrderLook('Refund due', SxChipTone.attention, TablerIcons.arrow_back_up);
  }
  switch (order.status) {
    case OrderStatus.expired:
      return const OrderLook('Expired', SxChipTone.neutral, TablerIcons.clock_x);
    case OrderStatus.cancelled:
      return const OrderLook('Cancelled', SxChipTone.neutral, TablerIcons.ban);
    case OrderStatus.refunded:
      return const OrderLook('Refunded', SxChipTone.neutral, TablerIcons.arrow_back_up);
  }
  if (!isPaid(order)) {
    return const OrderLook('Waiting payment', SxChipTone.neutral, TablerIcons.clock);
  }
  switch (order.status) {
    case OrderStatus.completed:
      return const OrderLook('Completed', SxChipTone.positive, TablerIcons.check);
    case OrderStatus.delivered:
      return const OrderLook('Delivered', SxChipTone.positive, TablerIcons.check);
    case OrderStatus.paid:
      // BACKEND GAP: no "seen" flag, so "New order" can't turn into the prototype's "To accept".
      return const OrderLook('New order', SxChipTone.attention, TablerIcons.bell_ringing);
  }
  final stage = stagesOf(methodOf(order))[stageIndexOf(order.status, methodOf(order))];
  return OrderLook(stage.label, SxChipTone.neutral, stage.icon);
}

/// With the customer, not the merchant: only a pickup order that is ready.
bool _withCustomer(Order order) =>
    order.status == OrderStatus.ready && methodOf(order) == OrderMethod.pickup;

/// Whether the next move is the merchant's.
bool isMyMove(Order order) {
  if (isRefundDue(order)) return true;
  return nextStepOf(order) != null && !_withCustomer(order);
}

/// The tab an order is in. Every order is in exactly one, so the counts add up to All.
OrderTab tabOf(Order order) {
  if (isRefundDue(order)) return OrderTab.todo;
  if (isClosed(order) || isFinished(order)) return OrderTab.done;
  if (!isPaid(order)) return OrderTab.waiting;
  return isMyMove(order) ? OrderTab.todo : OrderTab.moving;
}

/// Orders the merchant must act on, most urgent first: money owed back, then new orders, then the
/// rest, oldest first. // BACKEND GAP: `needed_by` is free text, so they can't sort by due time.
List<Order> ordersToAct(List<Order> orders) {
  int rank(Order o) => isRefundDue(o) ? 0 : (o.status == OrderStatus.paid ? 1 : 2);
  final list = orders.where((o) => tabOf(o) == OrderTab.todo).toList();
  list.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.createdAt.compareTo(b.createdAt);
  });
  return list;
}

List<Order> ordersInTab(OrderTab tab, List<Order> orders) => switch (tab) {
  OrderTab.todo => ordersToAct(orders),
  OrderTab.all => orders,
  _ => orders.where((o) => tabOf(o) == tab).toList(),
};

/// A titled part of a tab's list. An empty title draws no header.
class OrderSection {
  const OrderSection(this.title, this.orders);

  final String title;
  final List<Order> orders;
}

List<OrderSection> sectionsOf(OrderTab tab, List<Order> list, DateTime businessDate) {
  List<Order> pick(bool Function(Order) test) => list.where(test).toList();
  // BACKEND GAP: `needed_by` is free text and the business date isn't on the order, so the
  // prototype's Pre-orders, Upcoming and Scheduled-for-later sections can't be worked out.
  return switch (tab) {
    OrderTab.moving => [OrderSection('Waiting for pickup', list)],
    OrderTab.done => [
      OrderSection('Finished', pick(isFinished)),
      OrderSection('Cancelled, expired or refunded', pick((o) => !isFinished(o))),
    ],
    OrderTab.all => [
      OrderSection('Today', pick((o) => isOnBusinessDate(o.createdAt, businessDate))),
      OrderSection('Earlier', pick((o) => !isOnBusinessDate(o.createdAt, businessDate))),
    ],
    _ => [OrderSection('', list)],
  };
}

/// Paid sales for a period, per currency. Amounts in different currencies are never added.
class SalesSummary {
  const SalesSummary(this.count, this.byCurrency);

  final int count;
  final Map<String, int> byCurrency;

  /// INR when there is any, otherwise the first currency by name.
  String? get mainCurrency {
    if (byCurrency.isEmpty) return null;
    if (byCurrency.containsKey('INR')) return 'INR';
    return (byCurrency.keys.toList()..sort()).first;
  }

  int get mainMinor => byCurrency[mainCurrency] ?? 0;

  /// The other currencies, as `US$12.00`.
  List<String> get others => [
    for (final entry in byCurrency.entries)
      if (entry.key != mainCurrency) money(entry.value, entry.key),
  ];
}

SalesSummary salesFor(List<Order> orders, SalesPeriod period, DateTime businessDate) {
  final days = switch (period) {
    SalesPeriod.day => 1,
    SalesPeriod.week => 7,
    SalesPeriod.month => 30,
  };
  var count = 0;
  final byCurrency = <String, int>{};
  for (final order in orders.where(countsAsSale)) {
    final age = daysBetween((order.paidAt ?? order.createdAt).toLocal(), businessDate);
    if (age < 0 || age >= days) continue;
    count++;
    byCurrency[order.currency] = (byCurrency[order.currency] ?? 0) + order.totalMinor;
  }
  return SalesSummary(count, byCurrency);
}

/// The list may be cut off: the API returned as many orders as it ever does.
bool ordersClipped(List<Order> orders) => orders.length >= ordersWindow;

String itemsLine(Order order) {
  if (order.items.isEmpty) return 'No items';
  final first = order.items.first;
  final quantity = first.quantity > 1 ? '${first.quantity} × ' : '';
  final more = order.items.length > 1 ? ' + ${order.items.length - 1} more' : '';
  return '$quantity${first.label}$more';
}

String methodVerb(OrderMethod method) => switch (method) {
  OrderMethod.pickup => 'Pickup',
  OrderMethod.localDelivery => 'Deliver',
  OrderMethod.courier => 'Reach by',
  OrderMethod.digital => 'Send',
};

String methodLabel(OrderMethod method) => switch (method) {
  OrderMethod.pickup => 'Pickup',
  OrderMethod.localDelivery => 'Delivery',
  OrderMethod.courier => 'Courier',
  OrderMethod.digital => 'Digital',
};

IconData methodIcon(OrderMethod method) => switch (method) {
  OrderMethod.pickup => TablerIcons.building_store,
  OrderMethod.localDelivery => TablerIcons.motorbike,
  OrderMethod.courier => TablerIcons.truck_delivery,
  OrderMethod.digital => TablerIcons.send,
};

/// The due time in words, for open orders. // BACKEND GAP: `needed_by` is free text, so the
/// prototype's "late by" and "in 20 min" can't be worked out.
String? dueText(Order order) {
  final needed = order.neededBy?.trim();
  if (needed == null || needed.isEmpty || isClosed(order) || isFinished(order)) return null;
  return '${methodVerb(methodOf(order))} $needed';
}

/// `12 min`, `1 h 5 min`, rounded up so it never reads 0 too early.
String minWords(Duration duration) {
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

/// What happens next and who does it, in one line.
String nextHint(Order order, String name, {DateTime? now}) {
  if (isRefundDue(order)) {
    return 'Next: refund ${money(order.totalMinor, order.currency)}. It has not gone back yet.';
  }
  if (isClosed(order) || isFinished(order)) {
    return '${lookOf(order).label} · placed ${formatDate(order.createdAt)}';
  }
  if (!isPaid(order)) {
    final expires = order.holdExpiresAt;
    if (expires == null) return 'Waiting for $name to pay';
    final left = expires.difference(now ?? DateTime.now());
    return left.isNegative
        ? 'Waiting for $name to pay · hold ran out'
        : 'Waiting for $name to pay · ${minWords(left)} left';
  }
  if (_withCustomer(order)) return 'Waiting for $name to pick up';
  final next = nextStepOf(order);
  if (next == null) return '';
  return 'Next: ${next.label.toLowerCase()}';
}

String channelName(String channel) => switch (channel) {
  'instagram' => 'Instagram',
  'whatsapp' => 'WhatsApp',
  'messenger' => 'Messenger',
  'facebook' => 'Facebook',
  '' => 'Unknown',
  _ => channel[0].toUpperCase() + channel.substring(1),
};

SxBrand? channelBrand(String channel) => switch (channel) {
  'instagram' => SxBrand.instagram,
  'whatsapp' => SxBrand.whatsapp,
  'messenger' => SxBrand.messenger,
  'facebook' => SxBrand.facebook,
  _ => null,
};

/// Shown where an order has no conversation, or conversations could not load. Never a made-up name.
const unknownCustomer = 'Customer';

Map<String, String> handlesById(List<Conversation> conversations) => {
  for (final conversation in conversations) conversation.id: conversation.customerHandle,
};

/// Customer label for an order: `customer_handle` joined on `conversation_id`.
String customerNameOf(Order order, Map<String, String> handles) =>
    handles[order.conversationId] ?? unknownCustomer;
