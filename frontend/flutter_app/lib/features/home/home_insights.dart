/// Sales insights, added up on the phone from the orders the API returns.
///
/// All money is integer minor units. Doubles appear only for bar heights and percentages.
// BACKEND GAP: no insights endpoint and no date filter on orders, so this only sees the latest
// [ordersWindow] orders. Screens show a note when that cuts into the period.
// BACKEND GAP: Order has no business_date, so days are worked out in the phone's timezone.
library;

import 'package:intl/intl.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../orders/orders_providers.dart';
import 'home_providers.dart';

enum InsightPeriod { today, week, month }

class InsightBar {
  const InsightBar(this.label, this.minor);

  final String label;
  final int minor;
}

class InsightTrend {
  const InsightTrend(this.text, this.up);

  final String text;
  final bool up;
}

class BestSeller {
  const BestSeller(this.label, this.quantity);

  final String label;
  final int quantity;
}

class ChannelShare {
  const ChannelShare(this.channel, this.percent);

  final String channel;
  final int percent;
}

class InsightReport {
  const InsightReport({
    required this.period,
    required this.currency,
    required this.totalMinor,
    required this.otherTotals,
    required this.orderCount,
    required this.averageMinor,
    required this.trend,
    required this.bars,
    required this.bestSellers,
    required this.busyHours,
    required this.peakNote,
    required this.chats,
    required this.placed,
    required this.channels,
    required this.repeatPercent,
    required this.handledAlonePercent,
    required this.answerTime,
    required this.windowCutsPeriod,
  });

  final InsightPeriod period;
  final String currency;
  final int totalMinor;

  /// Sales in other currencies, never added to [totalMinor].
  final Map<String, int> otherTotals;

  /// Paid orders, in every currency.
  final int orderCount;

  /// Average in [currency] only. Null with no sales in it.
  final int? averageMinor;
  final InsightTrend? trend;
  final List<InsightBar> bars;
  final List<BestSeller> bestSellers;

  /// Orders placed per hour, 9 AM to 8 PM.
  final List<int> busyHours;
  final String? peakNote;

  /// Chats whose latest message falls in the period.
  final int chats;

  /// Orders placed in the period.
  final int placed;
  final List<ChannelShare> channels;
  final int? repeatPercent;
  final int? handledAlonePercent;
  final Duration? answerTime;

  /// The order window doesn't reach back to the start of the period.
  final bool windowCutsPeriod;
}

DateTime _dayOf(DateTime time) => dateOnly(time.toLocal());

/// When an order's money counts.
DateTime saleTime(Order order) => order.paidAt ?? order.createdAt;

/// Money earned: paid, and not cancelled or refunded since. Same rule as the Orders tab.
bool isSale(Order order) =>
    order.paymentStatus == 'paid' &&
    order.status != OrderStatus.cancelled &&
    order.status != OrderStatus.expired &&
    order.status != OrderStatus.refunded;

/// Sales on [from, to), by currency.
Map<String, int> salesBetween(List<Order> orders, DateTime from, DateTime to) {
  final totals = <String, int>{};
  for (final order in orders.where(isSale)) {
    final day = _dayOf(saleTime(order));
    if (day.isBefore(from) || !day.isBefore(to)) continue;
    totals[order.currency] = (totals[order.currency] ?? 0) + order.totalMinor;
  }
  return totals;
}

/// Whether the order list reaches back to [day], so totals for it are complete.
bool ordersReach(List<Order> orders, DateTime day) {
  if (orders.length < ordersWindow) return true;
  return orders.any((order) => !_dayOf(order.createdAt).isAfter(day));
}

/// "12% more than last week". Null when there is nothing fair to compare with.
InsightTrend? trendOf(int current, int base, String than) {
  if (base <= 0) return null;
  final percent = ((current - base) * 100 / base).round();
  if (percent == 0) return InsightTrend('Same as $than', true);
  return InsightTrend('${percent.abs()}% ${percent > 0 ? 'more' : 'less'} than $than', percent > 0);
}

/// Home's "compared with the same day last week".
InsightTrend? homeTrend(List<Order> orders, int currentMinor, String currency, DateTime businessDate) {
  final base = addDays(businessDate, -7);
  if (!ordersReach(orders, base)) return null;
  final baseTotal = salesBetween(orders, base, addDays(base, 1))[currency] ?? 0;
  return trendOf(currentMinor, baseTotal, 'last ${DateFormat('EEEE').format(businessDate)}');
}

/// Sales per hour today up to [now], for the hero sparkline and the Today bars. Starts at the first
/// sale or six hours back, whichever is earlier, so the bars add up to the total.
List<InsightBar> hourlyBars(List<Order> orders, String currency, DateTime businessDate, DateTime now) {
  final sameDay = daysBetween(now, businessDate) == 0;
  final lastHour = sameDay ? now.hour : 23;
  final perHour = <int, int>{};
  for (final order in orders.where((o) => isSale(o) && o.currency == currency)) {
    final local = saleTime(order).toLocal();
    if (daysBetween(local, businessDate) != 0) continue;
    perHour[local.hour] = (perHour[local.hour] ?? 0) + order.totalMinor;
  }
  var first = lastHour - 6;
  if (first < 0) first = 0;
  for (final hour in perHour.keys) {
    if (hour < first) first = hour;
  }
  return [
    for (var hour = first; hour <= lastHour; hour++)
      InsightBar(
        hour == lastHour && sameDay ? 'Now' : _hourLabel(hour),
        perHour[hour] ?? 0,
      ),
  ];
}

String _hourLabel(int hour) {
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve${hour < 12 ? 'a' : 'p'}';
}

String _hourWord(int hour) {
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve ${hour < 12 ? 'AM' : 'PM'}';
}

InsightReport computeInsights({
  required InsightPeriod period,
  required List<Order> orders,
  required List<Conversation> conversations,
  required List<Question> questions,
  required DateTime businessDate,
  required DateTime now,
}) {
  final today = dateOnly(businessDate);
  final end = addDays(today, 1);
  final (DateTime start, DateTime prevStart, DateTime prevEnd, String than) = switch (period) {
    InsightPeriod.today => (
      today,
      addDays(today, -7),
      addDays(today, -6),
      'last ${DateFormat('EEEE').format(today)}',
    ),
    InsightPeriod.week => (addDays(today, -6), addDays(today, -13), addDays(today, -6), 'last week'),
    InsightPeriod.month => (
      DateTime(today.year, today.month),
      DateTime(today.year, today.month - 1),
      _sameDayLastMonth(today),
      'this time last month',
    ),
  };
  bool inPeriod(DateTime time) {
    final day = _dayOf(time);
    return !day.isBefore(start) && day.isBefore(end);
  }

  final sales = [
    for (final order in orders)
      if (isSale(order) && inPeriod(saleTime(order))) order,
  ];
  final totals = <String, int>{};
  for (final order in sales) {
    totals[order.currency] = (totals[order.currency] ?? 0) + order.totalMinor;
  }
  final fallback = orders.isNotEmpty ? orders.first.currency : 'INR';
  final currency = leadCurrency(totals, fallback);
  final total = totals[currency] ?? 0;
  final inCurrency = sales.where((o) => o.currency == currency).length;

  final trend = ordersReach(orders, prevStart)
      ? trendOf(total, salesBetween(orders, prevStart, prevEnd)[currency] ?? 0, than)
      : null;

  final bars = switch (period) {
    InsightPeriod.today => hourlyBars(orders, currency, today, now),
    InsightPeriod.week => [
      for (var i = 6; i >= 0; i--)
        _dayBar(orders, currency, addDays(today, -i)),
    ],
    InsightPeriod.month => _weekBars(sales, currency, today),
  };

  final sold = <String, int>{};
  for (final order in sales) {
    for (final item in order.items) {
      sold[item.label] = (sold[item.label] ?? 0) + item.quantity;
    }
  }
  final best = sold.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  final placed = [
    for (final order in orders)
      if (order.status != OrderStatus.draft && inPeriod(order.createdAt)) order,
  ];
  final busy = List.filled(12, 0);
  for (final order in placed) {
    final hour = order.createdAt.toLocal().hour;
    if (hour >= 9 && hour <= 20) busy[hour - 9]++;
  }

  final byChannel = <String, int>{};
  for (final order in placed) {
    byChannel[order.channel] = (byChannel[order.channel] ?? 0) + 1;
  }
  final channels = [
    for (final entry in byChannel.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      ChannelShare(entry.key, (entry.value * 100 / placed.length).round()),
  ];

  // Repeat customers look at every order we can see: a period is too short to repeat in.
  final ordersPerChat = <String, int>{};
  for (final order in orders.where(isSale)) {
    final id = order.conversationId;
    if (id != null) ordersPerChat[id] = (ordersPerChat[id] ?? 0) + 1;
  }
  final repeat = ordersPerChat.isEmpty
      ? null
      : (ordersPerChat.values.where((n) => n > 1).length * 100 / ordersPerChat.length).round();

  final activeChats = {
    for (final chat in conversations)
      if (chat.lastMessageAt != null && inPeriod(chat.lastMessageAt!)) chat.id,
  };
  final asked = {
    for (final q in questions)
      if (inPeriod(q.createdAt)) q.conversationId,
  };
  final alone = activeChats.isEmpty
      ? null
      : ((activeChats.length - activeChats.where(asked.contains).length) * 100 / activeChats.length).round();

  final waits = [
    for (final q in questions)
      if (q.answeredAt != null && inPeriod(q.answeredAt!)) q.answeredAt!.difference(q.createdAt),
  ]..sort();

  return InsightReport(
    period: period,
    currency: currency,
    totalMinor: total,
    otherTotals: {
      for (final entry in totals.entries)
        if (entry.key != currency) entry.key: entry.value,
    },
    orderCount: sales.length,
    averageMinor: inCurrency == 0 ? null : total ~/ inCurrency,
    trend: trend,
    bars: bars,
    bestSellers: [for (final entry in best.take(5)) BestSeller(entry.key, entry.value)],
    busyHours: busy,
    peakNote: _peakNote(busy),
    chats: activeChats.length,
    placed: placed.length,
    channels: channels,
    repeatPercent: repeat,
    handledAlonePercent: alone,
    answerTime: waits.isEmpty ? null : waits[waits.length ~/ 2],
    windowCutsPeriod: !ordersReach(orders, start),
  );
}

DateTime _sameDayLastMonth(DateTime today) {
  final first = DateTime(today.year, today.month);
  final next = DateTime(today.year, today.month - 1, today.day + 1);
  return next.isAfter(first) ? first : next;
}

InsightBar _dayBar(List<Order> orders, String currency, DateTime day) => InsightBar(
  DateFormat('EEE').format(day),
  salesBetween(orders, day, addDays(day, 1))[currency] ?? 0,
);

List<InsightBar> _weekBars(List<Order> sales, String currency, DateTime today) {
  final weeks = List.filled((today.day - 1) ~/ 7 + 1, 0);
  for (final order in sales.where((o) => o.currency == currency)) {
    final index = (_dayOf(saleTime(order)).day - 1) ~/ 7;
    if (index < weeks.length) weeks[index] += order.totalMinor;
  }
  return [for (final (i, minor) in weeks.indexed) InsightBar('W${i + 1}', minor)];
}

/// The busiest three hours in a row. Says nothing on too few orders to mean anything.
String? _peakNote(List<int> busy) {
  if (busy.fold(0, (a, b) => a + b) < 3) return null;
  var best = 0;
  var bestCount = -1;
  for (var i = 0; i + 3 <= busy.length; i++) {
    final count = busy[i] + busy[i + 1] + busy[i + 2];
    if (count > bestCount) {
      best = i;
      bestCount = count;
    }
  }
  return 'Orders peak ${_hourWord(9 + best)} to ${_hourWord(9 + best + 3)}.';
}

/// `6 min`, `2 h`, `3 days`.
String shortDuration(Duration duration) {
  if (duration.inMinutes < 1) return 'Under 1 min';
  if (duration.inMinutes < 60) return '${duration.inMinutes} min';
  if (duration.inHours < 48) return '${duration.inHours} h';
  return '${duration.inDays} days';
}
