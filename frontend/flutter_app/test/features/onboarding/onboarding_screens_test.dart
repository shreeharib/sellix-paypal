import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/onboarding/ob_hours_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_live_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_pay_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_rules_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_shop_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_stock_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_talk_screen.dart';
import 'package:sellix_merchant/features/onboarding/ob_test_screen.dart';

import '../../support/fake_sellix_api.dart';

class _SignedIn extends AuthController {
  @override
  Future<AuthStatus> build() async => AuthStatus.signedIn;
}

/// A test screen under a small router, so each step's navigation is visible.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeSellixApi fake,
  Widget screen, {
  ThemeData? theme,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(520 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      for (final r in [Routes.obTalk, Routes.obRules, Routes.obHours, Routes.obPay, Routes.obTest, Routes.obStock, Routes.obLive, Routes.home])
        GoRoute(path: r, builder: (_, _) => Text('at $r', textDirection: TextDirection.ltr)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sellixApiProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(_SignedIn.new),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router, theme: theme ?? sellixLight),
    ),
  );
  return router;
}

/// A label as drawn, also when an icon sits inside the same rich text.
Finder _label(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().replaceAll('\uFFFC', '').trim() == text,
);

/// Past a snack's timer, which must not outlive the test.
Future<void> _snackGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = _label(text).last;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  group('shop step', () {
    testWidgets('shows a skeleton, then the server’s answers', (tester) async {
      final fake = FakeSellixApi.empty()..delay = const Duration(milliseconds: 200);
      await _pump(tester, fake, const ObShopScreen());
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SxSkeletonList), findsOneWidget);
      await _settle(tester);
      expect(find.text('Tell sellix about your shop'), findsOneWidget);
      expect(tester.widget<EditableText>(find.byType(EditableText).first).controller.text, 'Test Shop');
    });

    testWidgets('load error has a retry that works', (tester) async {
      final fake = FakeSellixApi.empty()..failure = const ApiException('Could not reach sellix');
      await _pump(tester, fake, const ObShopScreen());
      await _settle(tester);
      expect(find.text('Could not reach sellix'), findsOneWidget);
      fake.failure = null;
      await _tapText(tester, 'Try again');
      expect(find.text('Tell sellix about your shop'), findsOneWidget);
    });

    testWidgets('says what is missing, then saves and moves on', (tester) async {
      final fake = FakeSellixApi.empty();
      await _pump(tester, fake, const ObShopScreen());
      await _settle(tester);

      await _tapText(tester, 'Continue');
      expect(find.text('Pick what you sell.'), findsOneWidget);
      expect(fake.calls, isNot(contains('saveOnboarding')));

      await _tapText(tester, 'Other');
      await _tapText(tester, 'Continue');
      expect(find.text('Tell sellix what you sell.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(SxField, 'What do you sell?'), 'Pet food');
      await tester.enterText(find.widgetWithText(SxField, 'Shop name'), 'Paws');
      await tester.enterText(find.widgetWithText(SxField, 'City (optional)'), 'Chennai');
      await _tapText(tester, 'Continue');

      expect(fake.calls, contains('saveOnboarding'));
      expect(fake.merchant.name, 'Paws');
      expect(fake.answers.category, 'Pet food');
      expect(fake.answers.city, 'Chennai');
      expect(fake.answers.address, isNull);
      expect(find.text('at ${Routes.obTalk}'), findsOneWidget);
    });

    testWidgets('a failed save stays on the step and says why', (tester) async {
      final fake = FakeSellixApi.empty()
        ..answers = const OnboardingAnswers(category: 'Clothing');
      await _pump(tester, fake, const ObShopScreen());
      await _settle(tester);
      fake.failure = const ApiException('Saving failed');
      await _tapText(tester, 'Continue');
      expect(find.text('Saving failed'), findsOneWidget);
      expect(find.text('at ${Routes.obTalk}'), findsNothing);
      await _snackGone(tester);
    });

    testWidgets('works in dark', (tester) async {
      await _pump(tester, FakeSellixApi.empty(), const ObShopScreen(), theme: sellixDark);
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('talk step saves the voice and keeps earlier answers', (tester) async {
    final fake = FakeSellixApi.empty()..answers = const OnboardingAnswers(category: 'Clothing', city: 'Madurai');
    await _pump(tester, fake, const ObTalkScreen());
    await _settle(tester);
    expect(find.textContaining('An example, not a real chat'), findsOneWidget);

    await _tapText(tester, 'Formal');
    await _tapText(tester, 'By name');
    await _tapText(tester, 'Continue');

    expect(fake.answers.tone, 'formal');
    expect(fake.answers.addressCustomers, 'By name');
    expect(fake.answers.intro, 'Hi, I am Test Shop’s assistant');
    expect(fake.answers.city, 'Madurai');
    expect(fake.answers.faqs, contains('Customers write in: '));
    expect(find.text('at ${Routes.obRules}'), findsOneWidget);
  });

  testWidgets('rules step uses the category and writes the rules', (tester) async {
    final fake = FakeSellixApi.empty()..answers = const OnboardingAnswers(category: 'Food and sweets');
    await _pump(tester, fake, const ObRulesScreen());
    await _settle(tester);
    expect(find.text('Allergy and diet questions'), findsOneWidget);
    expect(find.text('Delivery'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More of bulk order size'));
    await _settle(tester);
    await tester.tap(find.byType(SxToggle).first);
    await _settle(tester);
    await _tapText(tester, 'Continue');

    expect(fake.answers.faqs, contains('Bulk orders above 35 pieces'));
    expect(fake.answers.faqs, contains('Answer without asking the shop: Discounts and bargaining.'));
    expect(fake.answers.neverPromise, 'Same-day custom orders, Delivery times, Sugar-free');
    expect(fake.answers.fulfilment, 'We deliver to your door. The shop confirms the charge.');
    expect(find.text('at ${Routes.obHours}'), findsOneWidget);
  });

  testWidgets('hours step saves hours and closed days', (tester) async {
    final fake = FakeSellixApi.empty();
    await _pump(tester, fake, const ObHoursScreen());
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Open on Sun'));
    await _settle(tester);
    await _tapText(tester, 'Continue');
    expect(fake.answers.hours, 'Tue–Sat, 9:00 AM – 8:00 PM');
    expect(fake.answers.weeklyOff, 'Mon; Sun');
    expect(find.text('at ${Routes.obPay}'), findsOneWidget);
  });

  group('pay step', () {
    testWidgets('checks the UPI ID, and Skip moves on without saving', (tester) async {
      final fake = FakeSellixApi.empty();
      await _pump(tester, fake, const ObPayScreen());
      await _settle(tester);
      expect(_label('Not set up yet'), findsOneWidget);
      expect(find.textContaining('WhatsApp is not available yet'), findsOneWidget);

      await _tapText(tester, 'Continue');
      expect(find.textContaining('Enter your UPI ID'), findsOneWidget);
      await tester.enterText(find.byType(SxField), 'nope');
      await _tapText(tester, 'Continue');
      expect(find.textContaining('That is not a UPI ID'), findsOneWidget);
      expect(fake.calls, isNot(contains('saveOnboarding')));

      await _tapText(tester, 'Skip');
      expect(fake.calls, isNot(contains('saveOnboarding')));
      expect(find.text('at ${Routes.obTest}'), findsOneWidget);
    });

    testWidgets('saves a good UPI ID; PayPal says Ready only when it is', (tester) async {
      final fake = FakeSellixApi.empty()..paymentsReady = true;
      await _pump(tester, fake, const ObPayScreen());
      await _settle(tester);
      expect(_label('Ready'), findsOneWidget);
      await tester.enterText(find.byType(SxField), 'shop@okbank');
      await _tapText(tester, 'Continue');
      expect(fake.answers.upiId, 'shop@okbank');
    });
  });

  group('test step', () {
    testWidgets('sends to the real assistant and shows only what it answered', (tester) async {
      final fake = FakeSellixApi.empty();
      await _pump(tester, fake, const ObTestScreen());
      await _settle(tester);
      expect(fake.calls, contains('simulatorChat'));
      expect(find.textContaining('Nothing is sent to anyone'), findsOneWidget);

      await _tapText(tester, '20% discount?');
      expect(fake.calls, contains('simulatorSend'));
      expect(find.text('20% discount?'), findsOneWidget);
      expect(find.text('Test reply'), findsOneWidget);
    });

    testWidgets('a failed send says so and shows no reply', (tester) async {
      final fake = FakeSellixApi.empty();
      await _pump(tester, fake, const ObTestScreen());
      await _settle(tester);
      fake.failure = const ApiException('The assistant is not available');
      await _tapText(tester, '20% discount?');
      expect(find.text('The assistant is not available'), findsOneWidget);
      expect(find.byType(SxTypingBubble), findsNothing);
      await _snackGone(tester);
    });

    testWidgets('load error has a retry; Continue still moves on', (tester) async {
      final fake = FakeSellixApi.empty()..failure = const ApiException('No chat');
      await _pump(tester, fake, const ObTestScreen());
      await _settle(tester);
      expect(find.text('No chat'), findsOneWidget);
      fake.failure = null;
      await _tapText(tester, 'Try again');
      expect(_label('Test chat'), findsOneWidget);
      await _tapText(tester, 'Continue');
      expect(find.text('at ${Routes.obStock}'), findsOneWidget);
    });
  });

  group('stock step', () {
    testWidgets('a new shop adds a product and really saves opening stock', (tester) async {
      final fake = FakeSellixApi.empty()..answers = const OnboardingAnswers(category: 'Food and sweets');
      await _pump(tester, fake, const ObStockScreen());
      await _settle(tester);
      expect(find.text('What did you make today?'), findsOneWidget);
      expect(find.text('Add your first product'), findsOneWidget);
      expect(find.text('Speaking your stock is not available yet'), findsOneWidget);

      await _tapText(tester, 'Add product');
      await _tapText(tester, 'Add to the list');
      expect(find.text('Enter the product’s name.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(SxField, 'Name'), 'Choco lava');
      await tester.enterText(find.widgetWithText(SxField, 'Price'), '99.50');
      await _tapText(tester, 'Add to the list');
      expect(find.text('Choco lava'), findsOneWidget);
      expect(find.text('₹99.50'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('More of Choco lava'));
      await _settle(tester);
      await _tapText(tester, 'Confirm and go live');

      expect(fake.calls, contains('setOpeningStock'));
      expect(fake.stock.single.product, 'Choco lava');
      expect(fake.stock.single.priceMinor, 9950);
      expect(fake.stock.single.opening, 2);
      expect(find.text('at ${Routes.obLive}'), findsOneWidget);
    });

    testWidgets('typing goes through the parser; no counts or no price cannot go live', (tester) async {
      final fake = FakeSellixApi.empty();
      await _pump(tester, fake, const ObStockScreen());
      await _settle(tester);
      await _tapText(tester, 'Type it');
      await tester.enterText(find.byType(SxField), 'Cushion');
      await _tapText(tester, 'Make the list');
      expect(fake.calls, contains('parseStockText'));
      expect(_label('Add a price'), findsOneWidget);

      await _tapText(tester, 'Confirm and go live');
      expect(fake.calls, isNot(contains('setOpeningStock')));
      expect(_label('Add to the list'), findsOneWidget);
      await _snackGone(tester);
    });

    testWidgets('load error has a retry; Skip saves no stock', (tester) async {
      final fake = FakeSellixApi.empty()..failure = const ApiException('No stock');
      await _pump(tester, fake, const ObStockScreen());
      await _settle(tester);
      expect(find.text('No stock'), findsOneWidget);
      fake.failure = null;
      await _tapText(tester, 'Try again');
      expect(find.text('Add your first product'), findsOneWidget);
      await _tapText(tester, 'Skip');
      expect(fake.calls, isNot(contains('setOpeningStock')));
      expect(find.text('at ${Routes.obLive}'), findsOneWidget);
    });
  });

  group('live step', () {
    testWidgets('completes on the server, says it is waiting without stock, updates the redirect', (tester) async {
      final fake = FakeSellixApi.empty();
      await _pump(
        tester,
        fake,
        const ObLiveScreen(),
        overrides: [
          onboardingCompletedProvider.overrideWith((ref) async => (await ref.read(sellixApiProvider).onboarding()).completed),
        ],
      );
      await _settle(tester);
      expect(fake.onboardingCompleted, isTrue);
      expect(find.text('sellix is waiting for stock'), findsOneWidget);
      expect(find.text('sellix is live'), findsNothing);

      final before = fake.calls.where((c) => c == 'onboarding').length;
      await _tapText(tester, 'Open home');
      expect(fake.calls.where((c) => c == 'onboarding').length, greaterThan(before));
      expect(find.text('at ${Routes.home}'), findsOneWidget);
    });

    testWidgets('says live only with stock, and names only connected channels', (tester) async {
      final fake = FakeSellixApi.empty()
        ..channels = const [Channel(channel: 'instagram', username: 'shop', status: 'active')];
      await fake.setOpeningStock(const [StockLine(product: 'Cake', priceMinor: 45000, quantity: 3)]);
      await _pump(tester, fake, const ObLiveScreen());
      await _settle(tester);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('sellix is live'), findsOneWidget);
      expect(find.text('It is answering your Instagram DMs now.'), findsOneWidget);
    });

    testWidgets('a failed completion has a retry and no way home', (tester) async {
      final fake = FakeSellixApi.empty()..failure = const ApiException('Could not finish');
      await _pump(tester, fake, const ObLiveScreen());
      await _settle(tester);
      expect(find.text('Could not finish'), findsOneWidget);
      expect(_label('Open home'), findsNothing);
      fake.failure = null;
      await _tapText(tester, 'Try again');
      expect(fake.onboardingCompleted, isTrue);
      expect(_label('Open home'), findsOneWidget);
    });
  });
}
