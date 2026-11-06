import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/settings/automation_screen.dart';
import 'package:sellix_merchant/features/settings/automations_screen.dart';
import 'package:sellix_merchant/features/settings/channels_screen.dart';
import 'package:sellix_merchant/features/settings/hours_screen.dart';
import 'package:sellix_merchant/features/settings/newauto_screen.dart';
import 'package:sellix_merchant/features/settings/payments_screen.dart';
import 'package:sellix_merchant/features/settings/profile_screen.dart';
import 'package:sellix_merchant/features/settings/rules_screen.dart';
import 'package:sellix_merchant/features/settings/shopprofile_screen.dart';

import '../../support/fake_sellix_api.dart';
import 'settings_harness.dart';

const _failure = ApiException('Server is down');

/// Records what each save asked for.
class _SpyApi extends FakeSellixApi {
  final List<bool> completeFlags = [];

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

    testWidgets('shop type saves the category only, with Undo', (tester) async {
      final fake = _SpyApi();
      await pumpScreen(tester, const ProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'Test category');
      await tapText(tester, 'Clothing');
      expect(fake.answers.category, 'Clothing');
      expect(fake.answers.city, 'Test City');
      expect(fake.completeFlags, [false]);
      await tapText(tester, 'Undo');
      expect(fake.answers.category, 'Test category');
      await drain(tester);
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
      await pumpScreen(tester, const ShopProfileScreen(), fake);
      await settle(tester);
      await tapText(tester, 'How sellix talks');
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
