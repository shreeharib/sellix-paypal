import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/settings/automation_screen.dart';
import 'package:sellix_merchant/features/settings/automations_screen.dart';
import 'package:sellix_merchant/features/settings/channels_screen.dart';
import 'package:sellix_merchant/features/settings/hours_screen.dart';
import 'package:sellix_merchant/features/settings/newauto_screen.dart';
import 'package:sellix_merchant/features/settings/payments_screen.dart';
import 'package:sellix_merchant/features/settings/profile_screen.dart';
import 'package:sellix_merchant/features/settings/rules_screen.dart';
import 'package:sellix_merchant/features/settings/settings_providers.dart';
import 'package:sellix_merchant/features/settings/shopprofile_screen.dart';
import 'package:sellix_merchant/features/stock/stock_providers.dart';

import '../../support/fake_sellix_api.dart';
import 'settings_harness.dart';

const _failure = ApiException('Server is down');

/// Records what each save asked for.
class _SpyApi extends FakeSellixApi {
  final List<bool> completeFlags = [];
  bool failShopTypes = false;

  @override
  Future<List<ShopTypeChoice>> shopTypes() async {
    if (failShopTypes) {
      calls.add('shopTypes');
      throw const ApiException('Not found', statusCode: 404);
    }
    return super.shopTypes();
  }

  @override
  Future<Onboarding> saveOnboarding({
    required String shopName,
    required OnboardingAnswers answers,
    bool complete = false,
  }) {
    completeFlags.add(complete);
    return super.saveOnboarding(shopName: shopName, answers: answers, complete: complete);
  }
}

void main() {
  group('Every screen shows a skeleton while loading', () {
    final screens = <String, Widget>{
      'Profile': const ProfileScreen(),
      'Payments': const PaymentsScreen(),
      'Hours': const HoursScreen(),
      'Rules': const RulesScreen(),
      'What sellix knows': const ShopProfileScreen(),
      'Channels': const ChannelsScreen(),
      'Automations': const AutomationsScreen(),
      'Automation': const AutomationScreen('pay'),
      'New automation': const NewAutoScreen(),
    };
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets(name, (tester) async {
        final fake = FakeSellixApi()..delay = const Duration(seconds: 1);
        await pumpScreen(tester, screen, fake);
        await tester.pump();
        expect(find.byType(SxSkeletonList), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);
        expect(find.byType(SxSkeletonList), findsNothing);
        await drain(tester);
      });
    }
  });

  group('Profile', () {
    testWidgets('shows a skeleton, then real data', (tester) async {
      final fake = FakeSellixApi()..delay = const Duration(milliseconds: 300);
      await pumpScreen(tester, const ProfileScreen(), fake);
      await tester.pump();
      expect(find.text('Test Shop'), findsNothing);
      await settle(tester);
      expect(find.text('Test Shop'), findsOneWidget);
      expect(find.text('@test.shop'), findsOneWidget);
      expect(find.text('Test category'), findsOneWidget);
      expect(find.text('Every day'), findsOneWidget);
      expect(find.textContaining('Connected', findRichText: true), findsOneWidget);
      expect(find.text('Not available yet'), findsOneWidget);
      expect(find.text('Free plan'), findsNothing);
      await drain(tester);
    });

    testWidgets('error then retry', (tester) async {
      final fake = FakeSellixApi()..failure = _failure;
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('Test Shop'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the agent switch calls the API and only then confirms', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      expect(fake.calls, isNot(contains('updateMerchant')));
      await tester.tap(find.byType(SxToggle).first);
      await settle(tester);
      expect(fake.calls, contains('updateMerchant'));
      expect(fake.merchant.agentEnabled, isFalse);
      expect(find.text('Off: messages are saved, nobody replies'), findsOneWidget);
      expect(find.text('sellix is paused. Messages are saved.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a failed agent switch goes back and says so', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      fake.failure = _failure;
      await tester.tap(find.byType(SxToggle).first);
      await settle(tester);
      expect(fake.merchant.agentEnabled, isTrue);
      expect(find.text('Replying to your DMs'), findsOneWidget);
      expect(find.text('Server is down'), findsWidgets);
      await drain(tester);
    });

    testWidgets('appearance changes the theme and is remembered', (tester) async {
      final prefs = await pumpScreen(tester, const ProfileScreen(), FakeSellixApi());
      await settle(tester);
      await tapText(tester, 'Dark');
      expect(prefs.getString('theme_mode'), 'dark');
      await drain(tester);
    });

    testWidgets('sign out asks first', (tester) async {
      final auth = FakeAuth();
      await pumpScreen(tester, const ProfileScreen(), FakeSellixApi(), auth: auth);
      await settle(tester);
      await tapText(tester, 'Sign out');
      expect(auth.signOuts, 0);
      await tapText(tester, 'Stay');
      expect(auth.signOuts, 0);
      await tapText(tester, 'Sign out');
      await tester.tap(find.text('Sign out').last);
      await settle(tester);
      expect(auth.signOuts, 1);
      await drain(tester);
    });

    testWidgets('shop type saves the backend id and the category, keeps the rest, with Undo', (tester) async {
      final fake = _SpyApi();
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Test category');
      // The backend's types, not the app's own.
      expect(fake.calls, contains('shopTypes'));
      for (final label in ['Bakery & sweets', 'Jewellery & accessories', 'Beauty & makeup', 'Plants & garden']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Clothing'), findsNothing);
      await tapText(tester, 'Dress & clothing shop');
      expect(fake.answers.shopType, 'dress_shop');
      expect(fake.answers.category, 'Dress & clothing shop');
      expect(fake.answers.city, 'Test City');
      expect(fake.completeFlags, [false]);
      expect(find.text('Shop type is now Dress & clothing shop.'), findsOneWidget);
      await tapText(tester, 'Undo');
      expect(fake.answers.category, 'Test category');
      expect(fake.answers.shopType, isNull);
      await drain(tester);
    });

    testWidgets('the list is the backend’s, whatever it holds', (tester) async {
      final fake = _SpyApi()
        ..shopTypeList = const [
          ShopTypeChoice(id: 'cobbler', label: 'Cobbler & shoe repair'),
          ShopTypeChoice(id: 'other', label: 'Other kind of shop'),
        ];
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Test category');
      expect(find.text('Cobbler & shoe repair'), findsOneWidget);
      expect(find.text('Bakery & sweets'), findsNothing);
      await tapText(tester, 'Cobbler & shoe repair');
      expect(fake.answers.shopType, 'cobbler');
      expect(fake.answers.category, 'Cobbler & shoe repair');
      await drain(tester);
    });

    testWidgets('if the list can’t be had, the built-in seven are offered', (tester) async {
      final fake = _SpyApi()..failShopTypes = true;
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Test category');
      expect(fake.calls, contains('shopTypes'));
      for (final t in builtInShopTypes) {
        expect(find.text(t.label), findsOneWidget, reason: t.label);
      }
      expect(builtInShopTypes.map((t) => t.id), [
        'bakery',
        'jewellery',
        'beauty',
        'plants',
        'handmade_gifts',
        'dress_shop',
        'other',
      ]);
      await tapText(tester, 'Plants & garden');
      expect(fake.answers.shopType, 'plants');
      await drain(tester);
    });

    testWidgets('Other keeps what the merchant typed as the category', (tester) async {
      final fake = _SpyApi();
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Test category');
      await tapText(tester, 'Other kind of shop');
      await tapText(tester, 'Save shop type');
      expect(find.text('Type what you sell first'), findsOneWidget);
      await tester.enterText(find.widgetWithText(SxField, 'What do you sell?').last, 'Kites');
      await tapText(tester, 'Save shop type');
      expect(fake.answers.shopType, 'other');
      expect(fake.answers.category, 'Kites');
      // The row shows what was typed, not the type's generic label.
      expect(find.text('Kites'), findsWidgets);
      await drain(tester);
    });

    testWidgets('a saved shop type shows by its label, and is the one ticked', (tester) async {
      final fake = _SpyApi()..answers = const OnboardingAnswers(category: 'Dress & clothing shop', shopType: 'dress_shop', city: 'Test City');
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Dress & clothing shop');
      final tick = tester.widget<SxChoiceCard>(find.widgetWithText(SxChoiceCard, 'Dress & clothing shop'));
      expect(tick.selected, isTrue);
      expect(tester.widget<SxChoiceCard>(find.widgetWithText(SxChoiceCard, 'Bakery & sweets')).selected, isFalse);
      await drain(tester);
    });

    test('changing the type makes the add-product form follow', () async {
      final fake = _SpyApi();
      final container = ProviderContainer(overrides: [sellixApiProvider.overrideWithValue(fake)]);
      addTearDown(container.dispose);
      container.listen(productSchemaProvider, (_, _) {});
      expect((await container.read(productSchemaProvider.future)).shopType, 'bakery');
      await saveAnswers(container, (a) => a.copyWith(shopType: 'dress_shop', category: 'Dress & clothing shop'));
      final schema = await container.read(productSchemaProvider.future);
      expect(schema.shopType, 'dress_shop');
      expect(schema.stockModes.map((m) => m.id), isNot(contains(StockMode.daily)));
    });

    testWidgets('morning reminder is local and says so', (tester) async {
      final prefs = await pumpScreen(tester, const ProfileScreen(), FakeSellixApi());
      await settle(tester);
      expect(find.text('Saved on this phone only, not active yet'), findsWidgets);
      await tapText(tester, 'Morning reminder');
      await tapText(tester, '7:00 AM');
      expect(prefs.getString('alerts.${FakeIds.merchant}.morning'), '7:00 AM');
      expect(find.text('7:00 AM'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('builds in dark', (tester) async {
      await pumpScreen(tester, const ProfileScreen(), FakeSellixApi(), dark: true);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await drain(tester);
    });
  });

  group('Saving answers', () {
    testWidgets('payments keeps fields it did not edit, even ones changed after it loaded', (tester) async {
      final fake = _SpyApi();
      await pumpScreen(tester, const PaymentsScreen(), fake);
      await settle(tester);

      fake.answers = fake.answers.copyWith(faqs: 'changed elsewhere');
      await tester.enterText(find.byType(TextField), 'shop@okbank');
      await tester.pump();
      await tapText(tester, 'Save');
      await settle(tester, 10);

      expect(fake.answers.upiId, 'shop@okbank');
      expect(fake.answers.faqs, 'changed elsewhere');
      expect(fake.answers.city, 'Test City');
      expect(fake.answers.tone, 'friendly');
      expect(fake.completeFlags, [false]);
      expect(fake.onboardingCompleted, isTrue);
      expect(find.text('route:/profile'), findsOneWidget);
      expect(find.text('Payment settings saved.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('payments and hours keep the shop type', (tester) async {
      final fake = _SpyApi();
      fake.answers = fake.answers.copyWith(shopType: 'dress_shop');
      await pumpScreen(tester, const PaymentsScreen(), fake);
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'shop@okbank');
      await tester.pump();
      await tapText(tester, 'Save');
      await settle(tester, 10);
      expect(fake.answers.upiId, 'shop@okbank');
      expect(fake.answers.shopType, 'dress_shop');
      await drain(tester);

      await pumpScreen(tester, const HoursScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Save');
      await settle(tester, 10);
      expect(fake.answers.hours, isNotNull);
      expect(fake.answers.shopType, 'dress_shop');
      await drain(tester);
    });

    testWidgets('does not turn a not-finished shop into a finished one', (tester) async {
      final fake = _SpyApi()..onboardingCompleted = false;
      await pumpScreen(tester, const PaymentsScreen(), fake);
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'shop@okbank');
      await tester.pump();
      await tapText(tester, 'Save');
      await settle(tester, 10);
      expect(fake.onboardingCompleted, isFalse);
      await drain(tester);
    });
  });

  group('Payments', () {
    testWidgets('error then retry, and PayPal shows its real state', (tester) async {
      final fake = FakeSellixApi()..failure = _failure;
      await pumpScreen(tester, const PaymentsScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('PayPal'), findsOneWidget);
      expect(find.textContaining('Not ready', findRichText: true), findsOneWidget);
      expect(find.textContaining('Ready', findRichText: true), findsNothing);
      await drain(tester);
    });

    testWidgets('refuses a malformed UPI ID and a failed save stays on the screen', (tester) async {
      final fake = FakeSellixApi();
      await pumpScreen(tester, const PaymentsScreen(), fake);
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'not a upi id');
      await tester.pump();
      await tapText(tester, 'Save');
      expect(find.text('Check the UPI ID. It looks like yourname@bank.'), findsOneWidget);
      expect(fake.calls, isNot(contains('saveOnboarding')));

      await tester.enterText(find.byType(TextField), 'ab@bank');
      await tester.pump();
      fake.failure = _failure;
      await tapText(tester, 'Save');
      expect(find.text('Server is down'), findsWidgets);
      expect(find.text('PayPal'), findsOneWidget);
      await drain(tester);
    });
  });

  group('Opening hours', () {
    testWidgets('turning a day off saves the text and keeps other answers', (tester) async {
      final fake = _SpyApi();
      await pumpScreen(tester, const HoursScreen(), fake);
      await settle(tester);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Closed'), findsNothing);

      await tester.tap(find.byType(SxToggle).first);
      await settle(tester);
      expect(find.text('Closed'), findsOneWidget);

      await tapText(tester, 'Save');
      await settle(tester, 10);
      expect(fake.answers.hours, 'Tue–Sun, 9:00 AM – 8:00 PM');
      expect(fake.answers.weeklyOff, 'Mon');
      expect(fake.answers.city, 'Test City');
      expect(fake.completeFlags, [false]);
      await drain(tester);
    });

    testWidgets('saved text it cannot read is shown, and left alone unless edited', (tester) async {
      final fake = FakeSellixApi()..answers = const OnboardingAnswers(hours: 'Most evenings', city: 'X');
      await pumpScreen(tester, const HoursScreen(), fake);
      await settle(tester);
      expect(find.textContaining('Most evenings'), findsOneWidget);
      await tapText(tester, 'Save');
      await settle(tester, 10);
      expect(fake.calls, isNot(contains('saveOnboarding')));
      expect(fake.answers.hours, 'Most evenings');
      await drain(tester);
    });

    testWidgets('error then retry', (tester) async {
      final fake = FakeSellixApi()..failure = _failure;
      await pumpScreen(tester, const HoursScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('Sun'), findsOneWidget);
      await drain(tester);
    });
  });

  group('Saved rules', () {
    FakeSellixApi withRules() => FakeSellixApi()
      ..profile = ShopProfile(
        version: 3,
        contentMd: '# Test Shop\n- Open daily.\n## Saved answers\n- Bulk orders: ask the owner.',
        createdAt: FakeSellixApi.now,
      );

    testWidgets('empty state', (tester) async {
      await pumpScreen(tester, const RulesScreen(), FakeSellixApi());
      await settle(tester);
      expect(find.text('No rules yet'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('error then retry', (tester) async {
      final fake = withRules()..failure = _failure;
      await pumpScreen(tester, const RulesScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('Bulk orders'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('add validates, then writes the section and keeps the profile', (tester) async {
      final fake = withRules();
      await pumpScreen(tester, const RulesScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Add a rule');
      await tapText(tester, 'Add rule');
      expect(find.text('Type what customers ask'), findsOneWidget);
      expect(fake.calls, isNot(contains('saveShopProfile')));

      await tester.enterText(find.byType(TextField).at(0), 'Sunday delivery?');
      await tester.enterText(find.byType(TextField).at(1), 'Before 2 PM.');
      await tester.pump();
      await tapText(tester, 'Add rule');
      expect(
        fake.profile!.contentMd,
        '# Test Shop\n- Open daily.\n## Saved answers\n- Sunday delivery? Before 2 PM.\n- Bulk orders: ask the owner.',
      );
      expect(find.text('Rule added. sellix will answer this alone.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('delete with Undo', (tester) async {
      final fake = withRules();
      await pumpScreen(tester, const RulesScreen(), fake);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Delete rule'));
      await settle(tester);
      expect(fake.profile!.contentMd, '# Test Shop\n- Open daily.');
      expect(find.text('No rules yet'), findsOneWidget);
      await tapText(tester, 'Undo');
      expect(fake.profile!.contentMd, '# Test Shop\n- Open daily.\n## Saved answers\n- Bulk orders: ask the owner.');
      await drain(tester);
    });
  });

  group('What sellix knows', () {
    testWidgets('error then retry, and shows real answers', (tester) async {
      final fake = FakeSellixApi()..failure = _failure;
      await pumpScreen(tester, const ShopProfileScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('Friendly, light emoji.'), findsOneWidget);
      expect(find.textContaining('Version 1'), findsOneWidget);
      await tapText(tester, 'As text');
      expect(find.text('# Test Shop'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('edits only the opened topic through the answers', (tester) async {
      final fake = _SpyApi();
      await pumpScreen(tester, const ShopProfileScreen(), fake);
      await settle(tester);
      fake.answers = fake.answers.copyWith(faqs: 'changed elsewhere');
      await tapText(tester, 'What you sell');
      await tester.enterText(find.byType(TextField), 'Cakes and cookies');
      await tester.pump();
      await tapText(tester, 'Save');
      await settle(tester, 10);

      expect(fake.answers.products, 'Cakes and cookies');
      expect(fake.answers.faqs, 'changed elsewhere');
      expect(fake.answers.tone, 'friendly');
      expect(fake.calls, contains('saveOnboarding'));
      expect(fake.calls, isNot(contains('saveShopProfile')));
      expect(fake.completeFlags, [false]);
      await drain(tester);
    });

    testWidgets('changes tone and shop name, refusing an empty name', (tester) async {
      final fake = _SpyApi();
      // Saved by an older app: cleared on the next save, never shown.
      fake.answers = fake.answers.copyWith(addressCustomers: 'Sir or madam', intro: 'Hi, I am Test Shop’s assistant');
      await pumpScreen(tester, const ShopProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'How sellix talks');
      expect(find.text('Sir or madam'), findsNothing);
      expect(find.text('How sellix introduces itself'), findsNothing);
      await tapText(tester, 'Formal');
      await tapText(tester, 'Shop');
      await tester.enterText(find.byType(TextField).first, '  ');
      await tester.pump();
      await tapText(tester, 'Save');
      expect(find.text('Type your shop name'), findsOneWidget);
      expect(fake.calls, isNot(contains('saveOnboarding')));

      await tester.enterText(find.byType(TextField).first, 'New Name');
      await tester.pump();
      await tapText(tester, 'Save');
      await settle(tester, 10);
      expect(fake.answers.tone, 'formal');
      expect(fake.answers.addressCustomers, isNull);
      expect(fake.answers.intro, isNull);
      expect(fake.merchant.name, 'New Name');
      expect(fake.answers.category, 'Test category');
      await drain(tester);
    });
  });

  group('Channels', () {
    testWidgets('shows real status, and WhatsApp connect is disabled with a label', (tester) async {
      await pumpScreen(tester, const ChannelsScreen(), FakeSellixApi());
      await settle(tester);
      expect(find.textContaining('@test.shop'), findsOneWidget);
      expect(find.textContaining('Connected', findRichText: true), findsOneWidget);
      expect(find.text('Reconnect Instagram'), findsNothing);
      expect(find.text('Connecting WhatsApp is not available yet'), findsOneWidget);
      expect(find.text('Messages today'), findsNothing);
      await tapText(tester, 'Connect');
      expect(find.textContaining('WhatsApp is connected'), findsNothing);
      await drain(tester);
    });

    testWidgets('error then retry', (tester) async {
      final fake = FakeSellixApi()..failure = _failure;
      await pumpScreen(tester, const ChannelsScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('Instagram'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('reconnect runs the real flow and checks the result', (tester) async {
      final fake = FakeSellixApi()
        ..channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'error')];
      final auth = FakeAuth(
        onSignIn: () async {
          fake.channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'active')];
        },
      );
      await pumpScreen(tester, const ChannelsScreen(), fake, auth: auth);
      await settle(tester);
      expect(find.textContaining('Instagram disconnected'), findsOneWidget);
      await tapText(tester, 'Reconnect Instagram');
      expect(auth.signIns, 1);
      expect(find.textContaining('Connected', findRichText: true), findsOneWidget);
      expect(find.text('Instagram is back.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a shop with no Instagram can connect it with the real login', (tester) async {
      final fake = FakeSellixApi()..channels = const [];
      final auth = FakeAuth(
        onSignIn: () async {
          fake.channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'active')];
        },
      );
      await pumpScreen(tester, const ChannelsScreen(), fake, auth: auth);
      await settle(tester);
      expect(find.text('Not connected'), findsOneWidget);
      await tapText(tester, 'Connect Instagram');
      expect(auth.signIns, 1);
      expect(find.text('Instagram is connected.'), findsOneWidget);
      expect(find.textContaining('@test.shop'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('reconnect does not claim success if the channel is still down', (tester) async {
      final fake = FakeSellixApi()
        ..channels = const [Channel(channel: 'instagram', username: 'test.shop', status: 'revoked')];
      await pumpScreen(tester, const ChannelsScreen(), fake, auth: FakeAuth());
      await settle(tester);
      await tapText(tester, 'Reconnect Instagram');
      expect(find.text('Instagram did not reconnect. Please try again.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('reconnect into another shop says so', (tester) async {
      final fake = FakeSellixApi()
        ..channels = const [Channel(channel: 'instagram', username: 'a', status: 'error')];
      final auth = FakeAuth(
        onSignIn: () async {
          fake
            ..merchant = const Merchant(id: 'other', name: 'Other Shop', timezone: 'UTC', agentEnabled: true)
            ..channels = const [Channel(channel: 'instagram', username: 'b', status: 'active')];
        },
      );
      await pumpScreen(tester, const ChannelsScreen(), fake, auth: auth);
      await settle(tester);
      await tapText(tester, 'Reconnect Instagram');
      expect(find.textContaining('You are now in Other Shop'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('a cancelled reconnect is not an error and not a success', (tester) async {
      final fake = FakeSellixApi()
        ..channels = const [Channel(channel: 'instagram', username: 'a', status: 'error')];
      final auth = FakeAuth(onSignIn: () async => throw const SignInCancelled());
      await pumpScreen(tester, const ChannelsScreen(), fake, auth: auth);
      await settle(tester);
      await tapText(tester, 'Reconnect Instagram');
      expect(find.textContaining('Reconnect cancelled'), findsOneWidget);
      await drain(tester);
    });
  });
}
