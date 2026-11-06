/// Order data shared across the app. Other features may import this file.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';

/// The most orders the API returns in one call. It has no paging, so everything worked out from
/// this list (tabs, customers, spend) only sees the latest 200 orders.
const ordersWindow = 200;

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
