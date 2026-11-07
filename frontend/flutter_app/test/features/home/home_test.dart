import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/nav_badges.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/home/home_insights.dart';
import 'package:sellix_merchant/features/home/home_providers.dart';
import 'package:sellix_merchant/features/home/home_screen.dart';
import 'package:sellix_merchant/features/home/insights_screen.dart';
import 'package:sellix_merchant/features/home/needs_screen.dart';
import 'package:sellix_merchant/features/home/notifications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_sellix_api.dart';

/// A real router with [screen] at the start and a marker page for every place it can go.
Future<ProviderContainer> pumpScreen(WidgetTester tester, FakeSellixApi fake, Widget screen) async {
  // Tall, because the lists build lazily and every section should be on screen.
  tester.view.physicalSize = const Size(1170, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  GoRoute marker(String path) => GoRoute(path: path, builder: (_, s) => Text('page:${s.uri}'));
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      for (final path in [
        Routes.needs,
        Routes.notifications,
        Routes.insights,
        Routes.morning,
        Routes.channels,
        Routes.orders,
        Routes.chats,
        Routes.stock,
        Routes.profile,
        Routes.home,
        '/chat/:id',
        '/order/:id',
      ])
        marker(path),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sellixApiProvider.overrideWithValue(fake),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(theme: sellixLight, routerConfig: router),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byWidget(screen)));
}

/// Screens have repeating animations, so pumpAndSettle would never end.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first);
  await settle(tester);
}

Order paidOrder({
  required String id,
  required int number,
  required int minor,
  required DateTime at,
  String currency = 'INR',
  String status = OrderStatus.paid,
  String channel = 'instagram',
  String? conversationId = FakeIds.conversationA,
  String product = 'Item A',
  int quantity = 1,
}) => Order(
  id: id,
  number: number,
  status: status,
  currency: currency,
  totalMinor: minor,
  conversationId: conversationId,
  createdAt: at,
  paidAt: at,
  holdExpiresAt: null,
  items: [OrderItem(product: product, variant: null, quantity: quantity, unitPriceMinor: minor ~/ quantity)],
  paymentStatus: 'paid',
  channel: channel,
);

void main() {
  group('Home', () {
    testWidgets('shows a skeleton while loading', (tester) async {
      final fake = FakeSellixApi()..delay = const Duration(seconds: 1);
      await pumpScreen(tester, fake, const HomeScreen());
      await tester.pump();
      expect(find.byType(SxSkeletonList), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.byType(SxSkeletonList), findsNothing);
    });

    testWidgets('shows the real summary, and retry recovers from an error', (tester) async {
      final fake = FakeSellixApi()..failure = const ApiException('Server is down');
      await pumpScreen(tester, fake, const HomeScreen());
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);

      fake.failure = null;
      await tapText(tester, 'Try again');
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Test Shop'), findsOneWidget);
      expect(find.text('Today’s sales'), findsOneWidget);
      // The fake's one paid order is ₹200, from `today`, and no prototype data shows.
      expect(find.text('₹200'), findsWidgets);
      expect(find.text('customer.one'), findsWidgets);
      expect(find.textContaining('Can this be delivered tomorrow?'), findsOneWidget);
      expect(find.text('Orders to handle'), findsOneWidget);
      expect(find.textContaining('Lakshmi'), findsNothing);
      expect(find.textContaining('Priya'), findsNothing);
    });

    testWidgets('feeds the nav badges with real counts', (tester) async {
      final fake = FakeSellixApi();
      final container = await pumpScreen(tester, fake, const HomeScreen());
      await settle(tester);
      final badges = container.read(navBadgesProvider);
      expect(badges.chatsNeedYou, 1);
      expect(badges.ordersToAct, 1); // the paid order; the unpaid one is only waiting
    });

    testWidgets('a new shop sees the stock card and no invented figures', (tester) async {
      await pumpScreen(tester, FakeSellixApi.empty(), const HomeScreen());
      await settle(tester);
      expect(find.text('What’s in stock today?'), findsOneWidget);
      expect(find.text('No chats or orders yet'), findsOneWidget);
      expect(find.text('Same as yesterday'), findsNothing);
      expect(find.text('Needs you'), findsNothing);
    });

    testWidgets('answering sends through the API only after Send answer', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, fake, const HomeScreen());
      await settle(tester);

      await tapText(tester, 'Answer');
      expect(fake.calls, isNot(contains('answerQuestion')));

      // An empty answer is refused without a call.
      await tapText(tester, 'Send answer');
      expect(find.text('Type your answer first.'), findsOneWidget);
      expect(fake.calls, isNot(contains('answerQuestion')));

      await tester.enterText(find.byType(TextField), 'Yes, tomorrow at 11');
      await tester.pump();
      await tapText(tester, 'Send answer');
      await settle(tester);

      expect(fake.calls, contains('answerQuestion'));
      expect(fake.questionList.single.answer, 'Yes, tomorrow at 11');
      expect(find.text('Sent to customer.one.'), findsOneWidget);
      expect(find.text('All clear'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('pausing the agent calls the API', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, fake, const HomeScreen());
      await settle(tester);
      await tester.tap(find.byType(SxLivePill));
      await settle(tester);
      expect(find.text('Pause sellix?'), findsOneWidget);
      await tapText(tester, 'Until you turn it on');
      expect(fake.merchant.agentEnabled, isFalse);
      await settle(tester);
      expect(tester.widget<SxLivePill>(find.byType(SxLivePill)).state, SxAgentState.paused);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Add 6 more restocks only after confirming', (tester) async {
      final fake = FakeSellixApi();
      fake.stock = const [
        StockRow(
          variantId: FakeIds.variantA,
          product: 'Item A',
          variant: null,
          priceMinor: 10000,
          currency: 'INR',
          opening: 4,
          restocked: 0,
          held: 0,
          sold: 4,
          counterSales: 0,
          available: 0,
        ),
      ];
      await pumpScreen(tester, fake, const HomeScreen());
      await settle(tester);
      expect(find.text('Item A sold out today.'), findsOneWidget);
      await tapText(tester, 'Add 6 more');
      expect(fake.calls, isNot(contains('restock')));
      await tester.tap(find.text('Add 6 more').last);
      await settle(tester);
      expect(fake.calls, contains('restock'));
      expect(fake.stock.single.available, 6);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Needs you', () {
    testWidgets('suggested answers are one tap: the answer opens with the text filled in', (tester) async {
      final fake = FakeSellixApi();
      fake.questionList = [
        for (final q in fake.questionList)
          Question(
            id: q.id,
            conversationId: q.conversationId,
            question: q.question,
            status: q.status,
            answer: q.answer,
            createdAt: q.createdAt,
            answeredAt: q.answeredAt,
            windowClosesAt: q.windowClosesAt,
            windowState: q.windowState,
            suggestedAnswers: const ['Yes, tomorrow at 11', 'Not tomorrow'],
          ),
      ];
      await pumpScreen(tester, fake, const NeedsScreen());
      await settle(tester);
      expect(find.text('Yes, tomorrow at 11'), findsOneWidget);
      expect(find.text('Not tomorrow'), findsOneWidget);

      await tapText(tester, 'Not tomorrow');
      expect(find.widgetWithText(TextField, 'Not tomorrow'), findsOneWidget);
      expect(fake.calls, isNot(contains('answerQuestion'))); // filled in, not sent

      await tapText(tester, 'Send answer');
      await settle(tester);
      expect(fake.calls, contains('answerQuestion'));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('shows the queue, and dismissing asks first and closes the question', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, fake, const NeedsScreen());
      await settle(tester);
      expect(find.text('1 needs you · customers are waiting'), findsOneWidget);

      await tapText(tester, 'Dismiss');
      expect(find.text('Dismiss this question?'), findsOneWidget);
      expect(fake.calls, isNot(contains('closeQuestion')));

      await tester.tap(find.text('Dismiss').last);
      await settle(tester);
      expect(fake.calls, contains('closeQuestion'));
      expect(find.text('Nobody is waiting'), findsOneWidget);
      expect(find.text('All clear'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('error state offers retry', (tester) async {
      final fake = FakeSellixApi()..failure = const ApiException('No network');
      await pumpScreen(tester, fake, const NeedsScreen());
      await settle(tester);
      expect(find.text('No network'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Answered tab shows real answers', (tester) async {
      final fake = FakeSellixApi();
      await fake.answerQuestion(FakeIds.questionA, 'Yes we can');
      await pumpScreen(tester, fake, const NeedsScreen());
      await settle(tester);
      await tapText(tester, 'Answered');
      expect(find.text('Your answer: Yes we can'), findsOneWidget);
    });
  });

  group('Notifications', () {
    testWidgets('rows come from questions and orders, and mark all read clears them', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, fake, const NotificationsScreen());
      await settle(tester);
      expect(find.text('customer.one needs you'), findsOneWidget);
      expect(find.text('New order: #2'), findsOneWidget);
      expect(find.text('New order: #1'), findsOneWidget);
      expect(find.text('Stock is live'), findsOneWidget);
      expect(find.byType(SxPulseDot), findsNWidgets(3));

      await tapText(tester, 'Mark all read');
      expect(find.text('Mark all read'), findsNothing);
      expect(find.byType(SxPulseDot), findsNothing);
    });

    testWidgets('a row opens its order', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, fake, const NotificationsScreen());
      await settle(tester);
      await tapText(tester, 'New order: #2');
      expect(find.text('page:${Routes.order(FakeIds.orderPaid)}'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      final fake = FakeSellixApi.empty();
      await pumpScreen(tester, fake, const NotificationsScreen());
      await settle(tester);
      expect(find.text('Nothing yet'), findsOneWidget);
    });
  });

  group('Insights', () {
    testWidgets('adds up real orders, and switches period', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, fake, const InsightsScreen());
      await settle(tester);
      expect(find.text('This week'), findsWidgets);
      expect(find.text('₹200'), findsWidgets);
      expect(find.text('Best sellers'), findsOneWidget);
      expect(find.text('Not tracked yet. sellix doesn’t count these requests so far.'), findsOneWidget);
      // Prototype sample figures are gone.
      expect(find.text('86%'), findsNothing);
      expect(find.text('Tanglish'), findsNothing);

      await tapText(tester, 'This month');
      expect(find.text('By week'), findsOneWidget);
      await tapText(tester, 'Today');
      expect(find.text('By hour'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await pumpScreen(tester, FakeSellixApi.empty(), const InsightsScreen());
      await settle(tester);
      expect(find.text('No sales yet'), findsOneWidget);
    });

    testWidgets('error offers retry', (tester) async {
      final fake = FakeSellixApi()..failure = const ApiException('No network');
      await pumpScreen(tester, fake, const InsightsScreen());
      await settle(tester);
      expect(find.text('Try again'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Best sellers'), findsOneWidget);
    });
  });

  group('computeInsights', () {
    final day = DateTime(2026, 1, 15);
    final noon = DateTime(2026, 1, 15, 12);

    InsightReport report(InsightPeriod period, List<Order> orders, {List<Question> questions = const []}) =>
        computeInsights(
          period: period,
          orders: orders,
          conversations: const [],
          questions: questions,
          businessDate: day,
          now: noon,
        );

    test('keeps minor units exact and currencies apart', () {
      final r = report(InsightPeriod.today, [
        paidOrder(id: 'a', number: 1, minor: 10050, at: noon),
        paidOrder(id: 'b', number: 2, minor: 10051, at: noon),
        paidOrder(id: 'c', number: 3, minor: 1250, at: noon, currency: 'USD'),
      ]);
      expect(r.currency, 'INR');
      expect(r.totalMinor, 20101);
      expect(r.averageMinor, 10050); // whole minor units, in INR only
      expect(r.otherTotals, {'USD': 1250});
      expect(r.orderCount, 3);
    });

    test('leaves out unpaid and refunded orders, and cancelled ones still holding money', () {
      final r = report(InsightPeriod.today, [
        paidOrder(id: 'a', number: 1, minor: 100, at: noon, status: OrderStatus.cancelled),
        paidOrder(id: 'b', number: 2, minor: 200, at: noon, status: OrderStatus.refunded),
        paidOrder(id: 'c', number: 3, minor: 300, at: noon, status: OrderStatus.confirmed),
      ]);
      expect(r.totalMinor, 300);
    });

    test('gives no trend without a real base, and a true one with it', () {
      expect(report(InsightPeriod.week, [paidOrder(id: 'a', number: 1, minor: 100, at: noon)]).trend, isNull);
      final r = report(InsightPeriod.week, [
        paidOrder(id: 'a', number: 1, minor: 150, at: noon),
        paidOrder(id: 'b', number: 2, minor: 100, at: noon.subtract(const Duration(days: 8))),
      ]);
      expect(r.trend!.text, '50% more than last week');
      expect(r.trend!.up, isTrue);
    });

    test('says so when the order window cuts the period, and gives no trend', () {
      final orders = [
        for (var i = 0; i < 200; i++)
          paidOrder(id: '$i', number: i, minor: 100, at: noon.subtract(Duration(minutes: i))),
      ];
      final r = report(InsightPeriod.week, orders);
      expect(r.windowCutsPeriod, isTrue);
      expect(r.trend, isNull);
    });

    test('week bars cover seven days and add up to the total', () {
      final r = report(InsightPeriod.week, [
        paidOrder(id: 'a', number: 1, minor: 100, at: noon),
        paidOrder(id: 'b', number: 2, minor: 250, at: noon.subtract(const Duration(days: 3))),
      ]);
      expect(r.bars, hasLength(7));
      expect(r.bars.fold(0, (sum, bar) => sum + bar.minor), r.totalMinor);
    });

    test('answer time is the median of real answers', () {
      Question q(String id, int minutes) => Question(
        id: id,
        conversationId: 'c',
        question: 'q',
        status: 'answered',
        answer: 'a',
        createdAt: noon.subtract(Duration(minutes: minutes)),
        answeredAt: noon,
      );
      final r = report(InsightPeriod.today, const [], questions: [q('1', 2), q('2', 6), q('3', 90)]);
      expect(r.answerTime, const Duration(minutes: 6));
      expect(shortDuration(r.answerTime!), '6 min');
    });
  });

  group('order rules', () {
    final at = DateTime(2026, 1, 15, 12);

    test('match the Orders tab: paid, accepted, and refunds owed', () {
      Order o(String status, {String method = 'pickup'}) {
        final base = paidOrder(id: 'x', number: 1, minor: 100, at: at, status: status);
        return Order(
          id: base.id,
          number: base.number,
          status: base.status,
          currency: base.currency,
          totalMinor: base.totalMinor,
          conversationId: base.conversationId,
          createdAt: base.createdAt,
          paidAt: base.paidAt,
          holdExpiresAt: null,
          items: base.items,
          paymentStatus: 'paid',
          fulfilmentMethod: method,
        );
      }

      expect(orderIsToAct(o(OrderStatus.paid)), isTrue);
      expect(orderIsToAct(o(OrderStatus.confirmed)), isTrue);
      expect(orderIsToAct(o(OrderStatus.ready)), isFalse); // with the customer
      expect(orderIsToAct(o(OrderStatus.ready, method: 'delivery')), isTrue);
      expect(orderIsToAct(o(OrderStatus.completed)), isFalse);
      expect(orderIsToAct(o(OrderStatus.cancelled)), isTrue); // refund owed
    });
  });
}
