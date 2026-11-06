import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/settings/automation_screen.dart';
import 'package:sellix_merchant/features/settings/automations_screen.dart';
import 'package:sellix_merchant/features/settings/automations_store.dart';
import 'package:sellix_merchant/features/settings/newauto_screen.dart';

import '../../support/fake_sellix_api.dart';
import 'settings_harness.dart';

const _key = 'automations.v1.${FakeIds.merchant}';

void main() {
  group('Automations', () {
    testWidgets('error then retry', (tester) async {
      final fake = FakeSellixApi()..failure = const ApiException('Server is down');
      await pumpScreen(tester, const AutomationsScreen(), fake);
      await settle(tester);
      expect(find.text('Server is down'), findsOneWidget);
      fake.failure = null;
      await tapText(tester, 'Try again');
      expect(find.text('Comment to DM'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('no invented numbers, nothing optional on, and every card is marked', (tester) async {
      await pumpScreen(tester, const AutomationsScreen(), FakeSellixApi());
      await settle(tester);
      expect(find.text('0 of 6'), findsOneWidget);
      expect(find.text('86%'), findsNothing);
      expect(find.textContaining('recovered'), findsNothing);
      // One per optional card plus the banner, which ends in a full stop.
      expect(find.text(automationLocalNote), findsNWidgets(6));
      expect(find.text('$automationLocalNote.'), findsOneWidget);
      // Win back joins the list only once chosen.
      expect(find.text('Win back regulars'), findsNothing);
      await drain(tester);
    });

    testWidgets('a switch saves on the phone, says it is not active, and Undo works', (tester) async {
      final prefs = await pumpScreen(tester, const AutomationsScreen(), FakeSellixApi());
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Comment to DM').first);
      await settle(tester);
      expect(jsonDecode(prefs.getString(_key)!)['state']['comment']['on'], isTrue);
      expect(find.text('Comment to DM saved as on. Not active yet.'), findsOneWidget);
      expect(find.text('1 of 6'), findsOneWidget);
      await tapText(tester, 'Undo');
      expect(jsonDecode(prefs.getString(_key)!)['state']['comment']['on'], isFalse);
      await drain(tester);
    });

    testWidgets('state belongs to one shop', (tester) async {
      await pumpScreen(
        tester,
        const AutomationsScreen(),
        FakeSellixApi(),
        prefs: {
          'automations.v1.another-shop': jsonEncode({
            'state': {
              'comment': {'on': true},
            },
          }),
        },
      );
      await settle(tester);
      expect(find.text('0 of 6'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('survives a corrupt saved value', (tester) async {
      await pumpScreen(tester, const AutomationsScreen(), FakeSellixApi(), prefs: {_key: 'not json'});
      await settle(tester);
      expect(find.text('0 of 6'), findsOneWidget);
      await drain(tester);
    });
  });

  group('Automation detail', () {
    testWidgets('changes wait and mode, saved only on Save changes', (tester) async {
      final prefs = await pumpScreen(tester, const AutomationScreen('pay'), FakeSellixApi());
      await settle(tester);
      expect(find.text('10 minutes'), findsOneWidget);
      expect(find.text('$automationLocalNote.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('More of wait minutes'));
      await settle(tester);
      expect(find.text('15 minutes'), findsOneWidget);
      await tapText(tester, 'Draft first');
      expect(prefs.getString(_key), isNull);

      await tapText(tester, 'Save changes');
      await settle(tester, 10);
      final saved = jsonDecode(prefs.getString(_key)!)['state']['pay'];
      expect(saved['wait'], 15);
      expect(saved['mode'], 'draft');
      expect(find.text('route:/automations'), findsOneWidget);
      expect(find.text('$automationLocalNote.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('adds a word, refusing an empty one', (tester) async {
      await pumpScreen(tester, const AutomationScreen('comment'), FakeSellixApi());
      await settle(tester);
      await tapText(tester, 'Add');
      await tapText(tester, 'Add word');
      expect(find.text('Type a word first'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'combien');
      await tester.pump();
      await tapText(tester, 'Add word');
      expect(find.text('combien'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the built-in one shows the agent state, not the local note or a switch', (tester) async {
      await pumpScreen(tester, const AutomationScreen('dm'), FakeSellixApi());
      await settle(tester);
      expect(find.textContaining('Always on', findRichText: true), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('$automationLocalNote.'), findsNothing);
      expect(find.text('Save changes'), findsNothing);
      await drain(tester);
    });

    testWidgets('an unknown id is an empty state', (tester) async {
      await pumpScreen(tester, const AutomationScreen('nope'), FakeSellixApi());
      await settle(tester);
      expect(find.text('Automation not found'), findsOneWidget);
      await drain(tester);
    });
  });

  group('New automation', () {
    testWidgets('a template must be picked, and is saved as on', (tester) async {
      final prefs = await pumpScreen(tester, const NewAutoScreen(), FakeSellixApi());
      await settle(tester);
      expect(find.text('Turn on'), findsNothing);
      await tapText(tester, 'Save on this phone');
      expect(find.text('Pick a template first.'), findsOneWidget);
      expect(prefs.getString(_key), isNull);

      await tapText(tester, 'Win back regulars');
      await tapText(tester, 'Save on this phone');
      await settle(tester, 10);
      expect(jsonDecode(prefs.getString(_key)!)['state']['winback']['on'], isTrue);
      expect(find.text('$automationLocalNote.'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('build your own: trigger first, preview uses real stock, and it is stored', (tester) async {
      final prefs = await pumpScreen(tester, const NewAutoScreen(), FakeSellixApi());
      await settle(tester);
      await tapText(tester, 'Build your own');
      await tapText(tester, 'Save on this phone');
      expect(find.text('Pick what starts it first.'), findsOneWidget);

      await tapText(tester, 'Item sells out');
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.byType(SxBubble), findsOneWidget);
      expect(find.textContaining('Item A is back today'), findsOneWidget);
      expect(find.textContaining('Meena'), findsNothing);

      await tapText(tester, 'Save on this phone');
      await settle(tester, 10);
      final custom = jsonDecode(prefs.getString(_key)!)['custom'] as List;
      expect(custom.single['trigger'], 'Item sells out');
      expect(custom.single['message'], contains('{product}'));
      await drain(tester);
    });
  });
}
