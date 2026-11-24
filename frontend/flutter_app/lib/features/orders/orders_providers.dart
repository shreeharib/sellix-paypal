/// Order data shared across the app. Other features may import this file.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';

/// The most orders the API returns in one call. Everything worked out from this list (tabs,
/// customers, spend) only sees the latest 200 orders; the Orders list loads older ones on request
/// ([olderOrdersProvider]).
const ordersWindow = 200;

/// Orders per "load more" page.
const ordersPage = 50;

/// The shop's latest orders, newest first, up to [ordersWindow].
final ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  return ref.watch(sellixApiProvider).orders(limit: ordersWindow);
});

/// One order's status history, oldest first.
final orderTimelineProvider = FutureProvider.autoDispose.family<List<OrderTimelineEvent>, String>(
  (ref, orderId) async {
    final events = await ref.watch(sellixApiProvider).orderTimeline(orderId);
    return [...events]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  },
);

/// One order by id (`GET /v1/orders/{id}`), so an order outside the latest list still opens. Null
/// when it isn't this shop's (404).
final orderProvider = FutureProvider.autoDispose.family<Order?, String>((ref, orderId) async {
  try {
    return await ref.watch(sellixApiProvider).order(orderId);
  } on ApiException catch (error) {
    if (error.statusCode == 404) return null;
    rethrow;
  }
});

/// The order's payment links and payments, its refund, and whether it can be refunded.
final orderPaymentsProvider = FutureProvider.autoDispose.family<OrderPayments, String>(
  (ref, orderId) => ref.watch(sellixApiProvider).orderPayments(orderId),
);

/// Orders older than the first [ordersWindow], loaded a page at a time from the Orders list.
class OlderOrders {
  const OlderOrders({this.orders = const [], this.done = false, this.loading = false, this.error});

  final List<Order> orders;

  /// The last page came back short: there is nothing older.
  final bool done;
  final bool loading;
  final Object? error;
}

class OlderOrdersController extends Notifier<OlderOrders> {
  @override
  OlderOrders build() {
    // A fresh first page starts the older pages over.
    ref.watch(ordersProvider);
    return const OlderOrders();
  }

  /// Loads the page before [oldest], the oldest order shown so far.
  Future<void> loadMore(DateTime oldest) async {
    if (state.loading || state.done) return;
    final had = state.orders;
    state = OlderOrders(orders: had, loading: true);
    try {
      final page = await ref.read(sellixApiProvider).orders(limit: ordersPage, before: oldest);
      final known = {for (final o in had) o.id};
      state = OlderOrders(
        orders: [...had, for (final o in page) if (!known.contains(o.id)) o],
        done: page.length < ordersPage,
      );
    } on Object catch (error) {
      state = OlderOrders(orders: had, error: error);
    }
  }
}

final olderOrdersProvider = NotifierProvider.autoDispose<OlderOrdersController, OlderOrders>(
  OlderOrdersController.new,
);

/// The first page and the older pages, without repeats.
List<Order> withOlder(List<Order> first, OlderOrders older) {
  if (older.orders.isEmpty) return first;
  final known = {for (final o in first) o.id};
  return [...first, for (final o in older.orders) if (!known.contains(o.id)) o];
}

/// Whether the list may go on past what is loaded.
bool mayHaveOlder(List<Order> first, OlderOrders older) =>
    !older.done && (first.length >= ordersWindow || older.orders.isNotEmpty);
