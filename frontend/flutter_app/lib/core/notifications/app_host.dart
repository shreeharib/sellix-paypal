/// Sits under the app: reloads the main data when the app comes back to the front, and runs the
/// notification poller while a finished shop is signed in.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/chats/chats_providers.dart';
import '../../features/orders/orders_providers.dart';
import '../../features/settings/settings_providers.dart';
import '../../features/stock/stock_providers.dart';
import '../api/sellix_api.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import '../router.dart';
import '../theme_mode.dart';
import 'local_notifier.dart';
import 'notification_poller.dart';

/// How often the app looks for new questions and paid orders.
const notificationPollInterval = Duration(seconds: 60);

/// The shop to notify for: signed in, onboarding finished, notifications on. Null otherwise.
final notifyShopProvider = FutureProvider<String?>((ref) async {
  if (!ref.watch(notificationsEnabledProvider)) return null;
  final auth = await ref.watch(authControllerProvider.future);
  if (auth != AuthStatus.signedIn) return null;
  if (!await ref.watch(onboardingCompletedProvider.future)) return null;
  return (await ref.watch(sellixApiProvider).me()).merchant.id;
});

class AppHost extends ConsumerStatefulWidget {
  const AppHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppHost> createState() => _AppHostState();
}

class _AppHostState extends ConsumerState<AppHost> with WidgetsBindingObserver {
  Timer? _timer;
  NotificationPoller? _poller;
  SellixApi? _api;
  bool _notifierReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AsyncValue<String?>>(notifyShopProvider, (_, next) {
      final shopId = next.value;
      if (shopId == null) {
        if (!next.isLoading) _stop();
      } else {
        _start(shopId);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back in front: what the merchant sees may be minutes old.
    ref
      ..invalidate(todayProvider)
      ..invalidate(ordersProvider)
      ..invalidate(conversationsProvider)
      ..invalidate(openQuestionsProvider)
      ..invalidate(meProvider);
    unawaited(_poller?.poll());
  }

  Future<void> _start(String shopId) async {
    final api = ref.read(sellixApiProvider);
    if (_poller?.shopId == shopId && identical(api, _api)) return;
    _stop();
    _api = api;
    final notifier = ref.read(localNotifierProvider);
    if (!_notifierReady) {
      _notifierReady = true;
      await notifier.init(onTap: _open);
      final launched = await notifier.launchRoute();
      if (launched != null) _open(launched);
    }
    if (!mounted) return;
    SharedPreferences? prefs;
    try {
      prefs = ref.read(sharedPreferencesProvider);
    } on Object {
      prefs = null;
    }
    final poller = NotificationPoller(api: api, notifier: notifier, prefs: prefs, shopId: shopId);
    _poller = poller;
    unawaited(poller.poll());
    _timer = Timer.periodic(notificationPollInterval, (_) => unawaited(poller.poll()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _poller = null;
    _api = null;
  }

  /// A tapped notification opens its chat or order over whatever is on screen.
  void _open(String route) {
    if (!mounted) return;
    ref.read(routerProvider).push(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
