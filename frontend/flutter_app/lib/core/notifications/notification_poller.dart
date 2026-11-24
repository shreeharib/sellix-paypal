/// Every minute while the app is alive: new open questions and newly paid orders become local
/// notifications, at most one per item. Seen ids are kept on the phone.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../api/sellix_api.dart';
import '../format.dart';
import '../router.dart';
import 'local_notifier.dart';

class NotificationPoller {
  NotificationPoller({required this.api, required this.notifier, required this.prefs, required this.shopId});

  final SellixApi api;
  final LocalNotifier notifier;

  /// Null in tests or tools without preferences: then nothing is remembered between runs.
  final SharedPreferences? prefs;

  /// Seen ids are per shop, so signing in to another shop starts fresh.
  final String shopId;

  /// The most ids kept per kind. Older ones can't come back as new: the lists are newest first.
  static const keep = 300;

  /// Paid orders looked at per poll.
  static const ordersLooked = 50;

  final Map<String, List<String>> _memory = {};

  bool _running = false;

  String _key(String kind) => 'notify.$shopId.$kind';

  List<String>? _seen(String kind) => prefs?.getStringList(_key(kind)) ?? _memory[kind];

  Future<void> _remember(String kind, List<String> ids) async {
    final kept = ids.length > keep ? ids.sublist(ids.length - keep) : ids;
    _memory[kind] = kept;
    await prefs?.setStringList(_key(kind), kept);
  }

  /// Checks once. The first check on a phone only notes what is there: a merchant who installs the
  /// app isn't buried in notifications for old questions. Returns how many were shown.
  Future<int> poll() async {
    if (_running) return 0;
    _running = true;
    try {
      var shown = 0;
      shown += await _check<Question>(
        'questions',
        () => api.questions(),
        (q) => q.id,
        (q) => notifier.show(
          id: _idOf('q', q.id),
          title: 'sellix needs your answer',
          body: q.question,
          route: Routes.chat(q.conversationId),
        ),
      );
      shown += await _check<Order>(
        'paid_orders',
        () => api.orders(paymentStatus: const ['paid'], limit: ordersLooked),
        (o) => o.id,
        (o) => notifier.show(
          id: _idOf('o', o.id),
          title: 'Order #${o.number} is paid',
          body: '${money(o.totalMinor, o.currency)} came in. Open it to start on it.',
          route: Routes.order(o.id),
        ),
      );
      return shown;
    } finally {
      _running = false;
    }
  }

  Future<int> _check<T>(
    String kind,
    Future<List<T>> Function() load,
    String Function(T) idOf,
    Future<void> Function(T) notify,
  ) async {
    final List<T> items;
    try {
      items = await load();
    } on Object {
      // Offline or signed out: try again next time.
      return 0;
    }
    final seen = _seen(kind);
    final ids = [for (final item in items) idOf(item)];
    if (seen == null) {
      await _remember(kind, ids);
      return 0;
    }
    final known = seen.toSet();
    var shown = 0;
    // Oldest first, so they stack in the order they happened.
    for (final item in items.reversed) {
      final id = idOf(item);
      if (known.contains(id)) continue;
      await notify(item);
      known.add(id);
      shown++;
    }
    if (shown > 0) await _remember(kind, [...seen, for (final id in ids.reversed) if (!seen.contains(id)) id]);
    return shown;
  }

  /// A stable notification id per item, so the same item replaces itself instead of stacking.
  static int _idOf(String kind, String id) => '$kind:$id'.hashCode & 0x3fffffff;
}
