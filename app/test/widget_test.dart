import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/api/sellix_api.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/features/ask_me/ask_me_screen.dart';
import 'package:sellix_merchant/features/onboarding/onboarding_screen.dart';
import 'package:sellix_merchant/features/orders/orders_screen.dart';
import 'package:sellix_merchant/features/sign_in/sign_in_screen.dart';
import 'package:sellix_merchant/features/today/today_screen.dart';
import 'package:sellix_merchant/l10n/app_localizations.dart';

/// Screens against an in-memory API, so the UI can be tested without a server.
class FakeApi implements SellixApi {
  FakeApi({this.todayResult, this.orderResults = const [], this.questionResults = const [], this.onboardingResult});

  final Today? todayResult;
  final List<Order> orderResults;
  final List<Question> questionResults;
  final Onboarding? onboardingResult;
  bool? agentEnabledSentTo;
  final onboardingSaves = <({String shopName, Map<String, dynamic> answers, bool complete})>[];

  @override
  Future<Onboarding> onboarding() async => onboardingResult!;

  @override
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  }) async {
    onboardingSaves.add((shopName: shopName, answers: answers.toJson(), complete: complete));
    return onboardingResult!;
  }

  @override
  Future<Today> today() async => todayResult!;

  @override
  Future<List<Order>> orders({String? status}) async =>
      [for (final order in orderResults) if (status == null || order.status == status) order];

  @override
  Future<List<Question>> questions({required String status}) async =>
      [for (final question in questionResults) if (question.status == status) question];

  @override
  Future<Merchant> updateMerchant({String? name, bool? agentEnabled}) async {
    agentEnabledSentTo = agentEnabled;
    return Merchant(id: 'm-1', name: name ?? 'Sweet Crumbs', timezone: 'Asia/Kolkata', agentEnabled: agentEnabled ?? true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Today sampleToday({bool agentEnabled = true}) => Today(
      businessDate: DateTime(2026, 10, 25),
      agentEnabled: agentEnabled,
      stock: const [
        StockRow(
          variantId: 'v-1',
          product: 'Scoop cookie',
          variant: 'Chocolate',
          priceMinor: 6000,
          currency: 'INR',
          opening: 10,
          held: 2,
          sold: 3,
          available: 5,
        ),
        StockRow(
          variantId: 'v-2',
          product: 'Brownie',
          variant: null,
          priceMinor: 9000,
          currency: 'INR',
          opening: 4,
          held: 0,
          sold: 4,
          available: 0,
        ),
      ],
      openQuestions: 1,
      ordersAwaitingPayment: 2,
      ordersPaid: 3,
      revenueMinorByCurrency: const {'INR': 27000},
    );

Future<void> pumpScreen(WidgetTester tester, Widget screen, FakeApi api, {Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sellixApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Today shows stock, what is left, and sold-out items', (tester) async {
    await pumpScreen(tester, const TodayScreen(), FakeApi(todayResult: sampleToday()));

    expect(find.text('Scoop cookie (Chocolate)'), findsOneWidget);
    expect(find.text('5 left'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);
    expect(find.text('₹270'), findsOneWidget);
  });

  testWidgets('Switching the agent off on Today calls the API', (tester) async {
    final api = FakeApi(todayResult: sampleToday());
    await pumpScreen(tester, const TodayScreen(), api);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(api.agentEnabledSentTo, isFalse);
  });

  testWidgets('Today is shown in Tamil', (tester) async {
    await pumpScreen(tester, const TodayScreen(), FakeApi(todayResult: sampleToday()), locale: const Locale('ta'));

    expect(find.text('5 மீதம்'), findsOneWidget);
    expect(find.text('தீர்ந்துவிட்டது'), findsOneWidget);
  });

  testWidgets('Orders show number, status and total', (tester) async {
    final order = Order(
      id: 'o-1',
      number: 1042,
      status: 'awaiting_payment',
      currency: 'USD',
      totalMinor: 1250,
      fulfilment: 'pickup',
      deliveryAddress: null,
      neededBy: 'today evening',
      notes: null,
      createdAt: DateTime(2026, 10, 25, 10),
      holdExpiresAt: DateTime(2026, 10, 25, 10, 15),
      items: const [OrderItem(product: 'Gift box', variant: 'Chocolate', quantity: 1, unitPriceMinor: 1250)],
    );
    await pumpScreen(tester, const OrdersScreen(), FakeApi(orderResults: [order]));

    expect(find.text('Order #1042'), findsOneWidget);
    expect(find.text(r'$12.50'), findsOneWidget);
    expect(find.text('Waiting for payment'), findsWidgets);
  });

  testWidgets('Ask me shows the empty state when the agent has no questions', (tester) async {
    await pumpScreen(tester, const AskMeScreen(), FakeApi());

    expect(find.text('No questions right now'), findsOneWidget);
  });

  testWidgets('Sign-in offers "Continue with Instagram"', (tester) async {
    await pumpScreen(tester, const SignInScreen(), FakeApi());

    expect(find.text('Continue with Instagram'), findsOneWidget);
  });

  testWidgets('Onboarding confirms Instagram is connected, then saves each step and finishes', (tester) async {
    final api = FakeApi(
      onboardingResult: const Onboarding(
        shopName: 'sweetcrumbs',
        answers: OnboardingAnswers({}),
        completed: false,
        channels: [ConnectedChannel(channel: 'instagram', username: 'sweetcrumbs', status: 'active')],
        paymentsReady: true,
      ),
    );
    await pumpScreen(tester, const OnboardingScreen(), api);

    expect(find.text('Your Instagram is connected'), findsOneWidget);
    expect(find.text('Instagram · @sweetcrumbs'), findsOneWidget);
    expect(find.text('Receiving messages'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Shop name'), 'Sweet Crumbs');
    await tester.enterText(find.widgetWithText(TextField, 'What kind of shop'), 'Home bakery');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish later'));
    await tester.pumpAndSettle();

    expect(api.onboardingSaves.first.shopName, 'Sweet Crumbs');
    expect(api.onboardingSaves.first.answers, {'category': 'Home bakery', 'tone': 'friendly', 'emoji': true});
    expect(api.onboardingSaves.first.complete, isFalse);
    expect(api.onboardingSaves.last.complete, isTrue);
  });
}
