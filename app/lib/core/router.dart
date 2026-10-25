import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ask_me/ask_me_screen.dart';
import '../features/chats/chat_screen.dart';
import '../features/chats/chats_screen.dart';
import '../features/onboarding/onboarding_providers.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/splash_screen.dart';
import '../features/sign_in/sign_in_screen.dart';
import '../features/today/today_screen.dart';
import 'auth/auth_controller.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const today = '/today';
  static const askMe = '/ask-me';
  static const orders = '/orders';
  static const chats = '/chats';
  static const settings = '/settings';

  static String chat(String conversationId) => '$chats/$conversationId';
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AsyncValue<AuthStatus>>(const AsyncLoading());
  ref.listen(authControllerProvider, (_, next) => auth.value = next, fireImmediately: true);
  final setup = ValueNotifier<AsyncValue<bool>>(const AsyncLoading());
  ref.listen(onboardingStatusProvider, (_, next) => setup.value = next, fireImmediately: true);
  ref
    ..onDispose(auth.dispose)
    ..onDispose(setup.dispose);

  return GoRouter(
    initialLocation: Routes.today,
    refreshListenable: Listenable.merge([auth, setup]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final status = auth.value;
      if (status is AsyncLoading<AuthStatus>) {
        return location == Routes.splash ? null : Routes.splash;
      }
      final signedIn = status is AsyncData<AuthStatus> && status.value == AuthStatus.signedIn;
      if (!signedIn) return location == Routes.signIn ? null : Routes.signIn;
      if (setup.value is AsyncLoading<bool>) {
        return location == Routes.splash ? null : Routes.splash;
      }
      // A new shop goes through onboarding first. A failed check doesn't block the app:
      // its screens show the error with a retry.
      final needsSetup = setup.value is AsyncData<bool> && setup.value.value == false;
      if (needsSetup) return location == Routes.onboarding ? null : Routes.onboarding;
      if (location == Routes.signIn || location == Routes.splash || location == Routes.onboarding) {
        return Routes.today;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.today, builder: (_, _) => const TodayScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.askMe, builder: (_, _) => const AskMeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.orders, builder: (_, _) => const OrdersScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.chats,
                builder: (_, _) => const ChatsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => ChatScreen(conversationId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
    ],
  );
});
