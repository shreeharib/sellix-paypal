import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'format.dart';
import '../design/widgets/sx_snack.dart';
import '../features/chats/chat_screen.dart';
import '../features/chats/chats_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/insights_screen.dart';
import '../features/home/needs_screen.dart';
import '../features/home/notifications_screen.dart';
import '../features/onboarding/ob_hours_screen.dart';
import '../features/onboarding/ob_live_screen.dart';
import '../features/onboarding/ob_pay_screen.dart';
import '../features/onboarding/ob_rules_screen.dart';
import '../features/onboarding/ob_shop_screen.dart';
import '../features/onboarding/ob_stock_screen.dart';
import '../features/onboarding/ob_talk_screen.dart';
import '../features/onboarding/ob_test_screen.dart';
import '../features/orders/customer_screen.dart';
import '../features/orders/customers_screen.dart';
import '../features/orders/order_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/settings/automation_screen.dart';
import '../features/settings/automations_screen.dart';
import '../features/settings/channels_screen.dart';
import '../features/settings/hours_screen.dart';
import '../features/settings/newauto_screen.dart';
import '../features/settings/payments_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/settings/rules_screen.dart';
import '../features/settings/shopprofile_screen.dart';
import '../features/signin/auth_screen.dart';
import '../features/signin/autherror_screen.dart';
import '../features/signin/connected_screen.dart';
import '../features/signin/connecting_screen.dart';
import '../features/signin/iglogin_screen.dart';
import '../features/signin/prebrief_screen.dart';
import '../features/signin/splash_screen.dart';
import '../features/signin/welcome_screen.dart';
import '../features/stock/addproduct_screen.dart';
import '../features/stock/day_stock_screen.dart';
import '../features/stock/morning_screen.dart';
import '../features/stock/product_screen.dart';
import '../features/stock/stock_screen.dart';
import 'app_shell.dart';
import 'auth/auth_controller.dart';
import 'providers.dart';

abstract final class Routes {
  // Sign in
  static const splash = '/splash';
  static const auth = '/auth';
  static const welcome = '/welcome';
  static const prebrief = '/prebrief';
  static const iglogin = '/iglogin';
  static const connecting = '/connecting';
  static const connected = '/connected';
  static const autherror = '/autherror';

  // Onboarding
  static const obShop = '/ob-shop';
  static const obTalk = '/ob-talk';
  static const obRules = '/ob-rules';
  static const obHours = '/ob-hours';
  static const obPay = '/ob-pay';
  static const obTest = '/ob-test';
  static const obStock = '/ob-stock';
  static const obLive = '/ob-live';

  // Root tabs
  static const home = '/home';
  static const chats = '/chats';
  static const stock = '/stock';
  static const orders = '/orders';
  static const profile = '/profile';

  // Task screens: full screen, no nav bar
  static const notifications = '/notifications';
  static const needs = '/needs';
  static const insights = '/insights';
  static const morning = '/morning';
  static const addproduct = '/addproduct';
  static const stockForDay = '/stock-for';
  static const customers = '/customers';
  static const automations = '/automations';
  static const newauto = '/newauto';
  static const rules = '/rules';
  static const channels = '/channels';
  static const payments = '/payments';
  static const shopprofile = '/shopprofile';
  static const hours = '/hours';

  /// Set the stock for a later day, the way today's list is set.
  static String stockFor(DateTime day) => '$stockForDay?date=${businessDateString(day)}';
  static String chat(String conversationId) => '/chat/${Uri.encodeComponent(conversationId)}';
  static String order(String orderId) => '/order/${Uri.encodeComponent(orderId)}';
  static String product(String variantId) => '/product/${Uri.encodeComponent(variantId)}';
  static String customer(String customerId) => '/customer/${Uri.encodeComponent(customerId)}';
  static String automation(String automationId) => '/automation/${Uri.encodeComponent(automationId)}';

  /// The add-product form opened on an existing product.
  static String editProduct(String variantId) => '$addproduct?id=${Uri.encodeQueryComponent(variantId)}';
}

/// Screens a signed-out merchant may see. A failed or running sign-in stays here.
const _signedOutScreens = {
  Routes.splash,
  Routes.auth,
  Routes.welcome,
  Routes.prebrief,
  Routes.iglogin,
  Routes.connecting,
  Routes.autherror,
};

/// Onboarding screens; each moves to the next by itself.
const _onboardingScreens = {
  Routes.obShop,
  Routes.obTalk,
  Routes.obRules,
  Routes.obHours,
  Routes.obPay,
  Routes.obTest,
  Routes.obStock,
  Routes.obLive,
};

/// The sign-in flow signs the merchant in part way: these finish on their own terms.
const _signInFinish = {Routes.connecting, Routes.connected};

/// Has this shop finished onboarding? Invalidate it when onboarding completes.
final onboardingCompletedProvider = FutureProvider<bool>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  if (auth != AuthStatus.signedIn) return false;
  final answers = await ref.watch(sellixApiProvider).onboarding();
  return answers.completed;
});

/// Where a merchant belongs right now, or null to stay. Pure so it reads top to bottom.
String? sellixRedirect({
  required String location,
  required AsyncValue<AuthStatus> auth,
  required AsyncValue<bool> setup,
}) {
  if (auth.isLoading && !auth.hasValue) {
    return _signedOutScreens.contains(location) ? null : Routes.splash;
  }
  final signedIn = auth.hasValue && !auth.hasError && auth.requireValue == AuthStatus.signedIn;
  if (!signedIn) {
    // Splash only covers the wait: from here it moves on.
    return _signedOutScreens.contains(location) && location != Routes.splash ? null : Routes.auth;
  }

  if (_signInFinish.contains(location)) return null;

  if (setup.isLoading && !setup.hasValue) {
    return location == Routes.splash ? null : Routes.splash;
  }
  // A new shop goes through onboarding first. A failed check doesn't block the app:
  // its screens show the error with a retry.
  final needsSetup = setup.hasValue && !setup.hasError && setup.requireValue == false;
  if (needsSetup) return _onboardingScreens.contains(location) ? null : Routes.obShop;

  if (_signedOutScreens.contains(location)) return Routes.home;
  return null;
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Prototype `push`: slide from the right, iOS back swipe.
Page<void> _push(GoRouterState state, Widget child) => CupertinoPage<void>(key: state.pageKey, child: child);

/// Prototype `up`: a modal task slides up.
Page<void> _up(GoRouterState state, Widget child) =>
    CupertinoPage<void>(key: state.pageKey, fullscreenDialog: true, child: child);

/// Prototype `fade`: replaces what was there. Fade and scale from 0.985 in 320 ms.
Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      child: child,
      transitionsBuilder: (_, animation, _, child) {
        final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween<double>(begin: 0.985, end: 1).animate(a), child: child),
        );
      },
    );

GoRoute _route(String path, Page<void> Function(GoRouterState, Widget) page, Widget Function(GoRouterState) screen) =>
    GoRoute(
      path: path,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (_, state) => page(state, screen(state)),
    );

StatefulShellBranch _tab(String path, Widget screen) => StatefulShellBranch(
      routes: [
        GoRoute(path: path, pageBuilder: (_, state) => NoTransitionPage<void>(key: state.pageKey, child: screen)),
      ],
    );

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AsyncValue<AuthStatus>>(const AsyncLoading());
  final setup = ValueNotifier<AsyncValue<bool>>(const AsyncLoading());
  ref.listen(authControllerProvider, (_, next) => auth.value = next, fireImmediately: true);
  ref.listen(onboardingCompletedProvider, (_, next) => setup.value = next, fireImmediately: true);
  ref
    ..onDispose(auth.dispose)
    ..onDispose(setup.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: Listenable.merge([auth, setup]),
    observers: [SxSnackNavigatorObserver()],
    redirect: (_, state) => sellixRedirect(location: state.matchedLocation, auth: auth.value, setup: setup.value),
    routes: [
      // Sign in
      _route(Routes.splash, _fade, (_) => const SplashScreen()),
      _route(Routes.auth, _fade, (_) => const AuthScreen()),
      _route(Routes.welcome, _push, (_) => const WelcomeScreen()),
      _route(Routes.prebrief, _push, (_) => const PrebriefScreen()),
      _route(Routes.iglogin, _up, (_) => const IgLoginScreen()),
      _route(Routes.connecting, _fade, (_) => const ConnectingScreen()),
      _route(Routes.connected, _fade, (_) => const ConnectedScreen()),
      _route(Routes.autherror, _fade, (_) => const AuthErrorScreen()),

      // Onboarding
      _route(Routes.obShop, _push, (_) => const ObShopScreen()),
      _route(Routes.obTalk, _push, (_) => const ObTalkScreen()),
      _route(Routes.obRules, _push, (_) => const ObRulesScreen()),
      _route(Routes.obHours, _push, (_) => const ObHoursScreen()),
      _route(Routes.obPay, _push, (_) => const ObPayScreen()),
      _route(Routes.obTest, _push, (_) => const ObTestScreen()),
      _route(Routes.obStock, _push, (_) => const ObStockScreen()),
      _route(Routes.obLive, _fade, (_) => const ObLiveScreen()),

      // Root tabs, with the floating nav
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          _tab(Routes.home, const HomeScreen()),
          _tab(Routes.chats, const ChatsScreen()),
          _tab(Routes.stock, const StockScreen()),
          _tab(Routes.orders, const OrdersScreen()),
          _tab(Routes.profile, const ProfileScreen()),
        ],
      ),

      // Task screens, over the shell without the nav
      _route(Routes.notifications, _push, (_) => const NotificationsScreen()),
      _route(Routes.needs, _push, (_) => const NeedsScreen()),
      _route(Routes.insights, _push, (_) => const InsightsScreen()),
      _route('/chat/:id', _push, (s) => ChatScreen(s.pathParameters['id']!)),
      _route(Routes.morning, _up, (_) => const MorningScreen()),
      _route('/product/:id', _push, (s) => ProductScreen(s.pathParameters['id']!)),
      _route(
        Routes.stockForDay,
        _up,
        (s) => DayStockScreen(
          day: s.uri.queryParameters['date'] == null
              ? null
              : parseBusinessDate(s.uri.queryParameters['date']!),
        ),
      ),
      _route(Routes.addproduct, _up, (s) => AddProductScreen(variantId: s.uri.queryParameters['id'])),
      _route('/order/:id', _push, (s) => OrderScreen(s.pathParameters['id']!)),
      _route(Routes.customers, _push, (_) => const CustomersScreen()),
      _route('/customer/:id', _push, (s) => CustomerScreen(s.pathParameters['id']!)),
      _route(Routes.automations, _push, (_) => const AutomationsScreen()),
      _route('/automation/:id', _push, (s) => AutomationScreen(s.pathParameters['id']!)),
      _route(Routes.newauto, _up, (_) => const NewAutoScreen()),
      _route(Routes.rules, _push, (_) => const RulesScreen()),
      _route(Routes.channels, _push, (_) => const ChannelsScreen()),
      _route(Routes.payments, _push, (_) => const PaymentsScreen()),
      _route(Routes.shopprofile, _push, (_) => const ShopProfileScreen()),
      _route(Routes.hours, _push, (_) => const HoursScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
