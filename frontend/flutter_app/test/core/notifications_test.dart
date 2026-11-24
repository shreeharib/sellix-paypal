import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/notifications/app_host.dart';
import 'package:sellix_merchant/core/notifications/local_notifier.dart';
import 'package:sellix_merchant/core/notifications/notification_poller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sellix_api.dart';

/// Records what would reach the phone's notification shade.
class FakeNotifier implements LocalNotifier {
  void Function(String route)? onTap;
  final shown = <({int id, String title, String body, String route})>[];
  int inits = 0;
  bool asked = false;
  String? launch;

  @override
  Future<void> init({required void Function(String route) onTap}) async {
    inits++;
    this.onTap = onTap;
  }

  @override
  Future<bool> requestPermission() async => asked = true;

  @override
  Future<void> show({required int id, required String title, required String body, required String route}) async =>
      shown.add((id: id, title: title, body: body, route: route));

  @override
  Future<String?> launchRoute() async => launch;
}

class _SignedIn extends AuthController {
  @override
  Future<AuthStatus> build() async => AuthStatus.signedIn;
}

Question _question(String id, String text) => Question(
  id: id,
  conversationId: FakeIds.conversationA,
  question: text,
  status: 'open',
  answer: null,
  createdAt: FakeSellixApi.now,
  answeredAt: null,
);

Order _paid(String id, int number) => Order(
  id: id,
  number: number,
  status: OrderStatus.paid,
  currency: 'INR',
  totalMinor: 45000,
  conversationId: FakeIds.conversationA,
  createdAt: FakeSellixApi.now,
  paidAt: FakeSellixApi.now,
  holdExpiresAt: null,
  items: const [],
  paymentStatus: 'paid',
);

void main() {
  group('poller', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('the first check only notes what is there; then each new item notifies once', () async {
      final api = FakeSellixApi();
      final notifier = FakeNotifier();
      final poller = NotificationPoller(api: api, notifier: notifier, prefs: prefs, shopId: 'shop1');

      expect(await poller.poll(), 0);
      expect(notifier.shown, isEmpty);

      api.questionList = [...api.questionList, _question('q-new', 'Do you have it in blue?')];
      api.orderList = [...api.orderList, _paid('o-new', 41)];
      expect(await poller.poll(), 2);
      expect(notifier.shown.map((n) => n.title), ['sellix needs your answer', 'Order #41 is paid']);
      expect(notifier.shown.first.body, 'Do you have it in blue?');
      expect(notifier.shown.first.route, Routes.chat(FakeIds.conversationA));
      expect(notifier.shown.last.route, Routes.order('o-new'));
      expect(notifier.shown.last.body, contains('₹450'));

      // Nothing new: nothing shown again, also by a fresh poller (seen ids are on the phone).
      expect(await poller.poll(), 0);
      final again = NotificationPoller(api: api, notifier: notifier, prefs: prefs, shopId: 'shop1');
      expect(await again.poll(), 0);
      expect(notifier.shown, hasLength(2));
      expect(prefs.getStringList('notify.shop1.questions'), contains('q-new'));
    });

    test('a failed check shows nothing and tries again next time', () async {
      final api = FakeSellixApi();
      final notifier = FakeNotifier();
      final poller = NotificationPoller(api: api, notifier: notifier, prefs: prefs, shopId: 'shop1');
      await poller.poll();
      api.failure = const ApiException("Can't reach sellix. Check your connection.");
      api.questionList = [...api.questionList, _question('q2', 'Open on Sunday?')];
      expect(await poller.poll(), 0);
      api.failure = null;
      expect(await poller.poll(), 1);
    });

    test('seen ids are per shop', () async {
      final api = FakeSellixApi();
      final notifier = FakeNotifier();
      await NotificationPoller(api: api, notifier: notifier, prefs: prefs, shopId: 'a').poll();
      expect(prefs.getStringList('notify.a.questions'), [FakeIds.questionA]);
      expect(prefs.getStringList('notify.b.questions'), isNull);
    });
  });

  group('host', () {
    Future<(FakeSellixApi, FakeNotifier, GoRouter)> pumpHost(WidgetTester tester, {String? launch}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeSellixApi();
      final notifier = FakeNotifier()..launch = launch;
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(path: '/chat/:id', builder: (_, s) => Text('chat ${s.pathParameters['id']}')),
          GoRoute(path: '/order/:id', builder: (_, s) => Text('order ${s.pathParameters['id']}')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sellixApiProvider.overrideWithValue(api),
            sharedPreferencesProvider.overrideWithValue(prefs),
            authControllerProvider.overrideWith(_SignedIn.new),
            onboardingCompletedProvider.overrideWith((ref) async => true),
            notificationsEnabledProvider.overrideWithValue(true),
            localNotifierProvider.overrideWithValue(notifier),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => AppHost(child: child!),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return (api, notifier, router);
    }

    testWidgets('polls every minute, and a tap opens the right screen', (tester) async {
      final (api, notifier, _) = await pumpHost(tester);
      expect(notifier.inits, 1);
      expect(api.calls.where((c) => c == 'questions'), hasLength(1));

      api.questionList = [...api.questionList, _question('q-new', 'Is it eggless?')];
      await tester.pump(notificationPollInterval);
      await tester.pump();
      expect(notifier.shown.single.body, 'Is it eggless?');

      notifier.onTap!(notifier.shown.single.route);
      await tester.pumpAndSettle();
      expect(find.text('chat ${FakeIds.conversationA}'), findsOneWidget);
    });

    testWidgets('a notification that started the app opens its screen', (tester) async {
      await pumpHost(tester, launch: Routes.order(FakeIds.orderPaid));
      await tester.pumpAndSettle();
      expect(find.text('order ${FakeIds.orderPaid}'), findsOneWidget);
    });

    testWidgets('coming back to the app reloads and checks at once', (tester) async {
      final (api, notifier, _) = await pumpHost(tester);
      api.orderList = [...api.orderList, _paid('o-late', 77)];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(notifier.shown.single.title, 'Order #77 is paid');
    });

    testWidgets('signed out or not finished: no poller', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeSellixApi();
      final notifier = FakeNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sellixApiProvider.overrideWithValue(api),
            sharedPreferencesProvider.overrideWithValue(prefs),
            authControllerProvider.overrideWith(_SignedIn.new),
            onboardingCompletedProvider.overrideWith((ref) async => false),
            notificationsEnabledProvider.overrideWithValue(true),
            localNotifierProvider.overrideWithValue(notifier),
          ],
          child: const MaterialApp(home: AppHost(child: Text('x'))),
        ),
      );
      await tester.pump(notificationPollInterval * 2);
      expect(notifier.inits, 0);
      expect(api.calls, isNot(contains('questions')));
    });
  });
}
