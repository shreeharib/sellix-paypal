import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/app.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/chats/chat_screen.dart';
import 'package:sellix_merchant/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_sellix_api.dart';

class _FakeAuth extends AuthController {
  _FakeAuth(this.status);

  final AuthStatus status;

  @override
  Future<AuthStatus> build() async => status;
}

Future<void> _pumpApp(WidgetTester tester, {required AuthStatus auth, required bool completed}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sellixApiProvider.overrideWithValue(FakeSellixApi()),
        authControllerProvider.overrideWith(() => _FakeAuth(auth)),
        onboardingCompletedProvider.overrideWith((ref) async => completed),
      ],
      child: const SellixApp(),
    ),
  );
  await _settle(tester);
}

/// Real screens can run skeletons and countdowns forever, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SellixApp))).read(routerProvider);

/// Every shared widget at once, so a bad layout fails here and not on a feature screen.
class _Gallery extends StatefulWidget {
  const _Gallery();

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SxScaffold(
      floating: SxComposer(controller: _text, hint: 'Reply as Meena', onSend: () {}, onAttach: () {}),
      body: SxScrollList(
        onRefresh: () async {},
        children: [
          SxRootHeader(greeting: 'Good morning', shopName: 'A very long shop name that must not overflow the header row at all', unread: true, onBellTap: () {}, onAvatarTap: () {}),
          SxDetailHeader(title: 'Title', meta: 'meta', trailing: SxIconButton(icon: TablerIcons.dots, semanticLabel: 'Menu', onTap: () {})),
          const SxPageTitle(title: 'Orders', subtitle: 'Today'),
          const SxHeroCard(
            label: 'Today',
            value: '12,400',
            status: SxLivePill(state: SxAgentState.live),
            channels: [SxBrand.instagram, SxBrand.whatsapp],
            change: 'Up',
            sparkline: [1, 3, 2, 5],
            stats: [SxHeroStat(value: '1', label: 'Paid'), SxHeroStat(value: '2', label: 'Need you', attention: true)],
          ),
          const SxSectionHeader(title: 'Needs you', badge: 3, link: 'See all'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.s8,
              children: [
                SxNeedsYouCard(
                  name: 'Customer With A Long Name',
                  meta: 'Instagram, 2 min ago',
                  channel: SxBrand.instagram,
                  reason: 'A price ask that is long',
                  reasonIcon: TablerIcons.tag,
                  message: 'Can you do less?',
                  note: 'Below your floor. I did not reply.',
                  secondaryLabel: 'Open chat',
                  onSecondary: () {},
                  primaryLabel: 'Hold price and say so',
                  onPrimary: () {},
                ),
                SxRowCard(title: 'Row', meta: 'meta', icon: TablerIcons.package, onTap: () {}),
                SxStockRow(leading: const SxIconTile(icon: TablerIcons.package), title: 'Item', price: 'x', value: 0, onChanged: (_) {}),
                const SxBubble(text: 'hi', sender: SxBubbleSender.customer, time: 'now'),
                const SxBubble(text: 'hello', sender: SxBubbleSender.sellix),
                const SxBubble(text: 'hello', sender: SxBubbleSender.merchant),
                const SxTypingBubble(),
                const SxDateSeparator('Today'),
                const SxSystemEvent('Paid', icon: TablerIcons.check),
                SxAttachmentCard(leading: const SxIconTile(icon: TablerIcons.package, size: 48), title: 'Item', meta: 'x', onTap: () {}),
                SxBubbleLink(label: 'Show in English', onTap: () {}),
                SxEscalationCard(
                  body: 'Question?',
                  options: [
                    SxEscalationOption(label: 'Yes', recommended: true, onTap: () {}),
                    SxEscalationOption(label: 'Write my own reply', onTap: () {}),
                  ],
                ),
                SxVoiceCard(stateLabel: 'Listening', listening: true, transcript: 'two sarees', onMic: () {}),
                SxVoiceCard(stateLabel: 'Tap', stateIcon: TablerIcons.microphone, placeholder: 'Say it', onMic: () {}),
                SxField(label: 'Name', hint: 'Hint', prefix: '₹', errorText: 'Bad', onChanged: (_) {}),
                const SxField(maxLines: 3, hint: 'Area'),
                SxSegmented<int>(segments: const [SxSegment(0, 'One'), SxSegment(1, 'Two')], value: 1, onChanged: (_) {}),
                SxGroup(children: [
                  SxListRow(title: 'Row', subtitle: 'sub', value: 'val', icon: TablerIcons.bell, onTap: () {}),
                  SxSwitchRow(title: 'Switch', value: true, onChanged: (_) {}, leading: const SxBrandIcon(SxBrand.apple)),
                ]),
                SxChoiceCard(title: 'Choice', subtitle: 's', selected: true, check: true, onTap: () {}),
                const SxKeyValue(label: 'Key', value: 'Value', divider: true),
                const SxStepsBar(total: 4, current: 1),
                const SxMeter(fraction: 0.4),
                SxTimeChip(label: '9:00 AM', onTap: () {}),
                const SxBanner(message: 'Note'),
                const SxLocalOnlyNote(),
                const SxAiNote('A note'),
                const SxSkeleton(height: 40),
                const SxChip(label: 'Paid', tone: SxChipTone.positive, icon: TablerIcons.check, dot: true),
                Row(children: const [SxChip(label: 'In a Row'), SxBadge(count: 3)]),
                SxButtonRow(children: [
                  SxButton(label: 'Back', kind: SxButtonKind.secondary, onTap: () {}),
                  SxButton(label: 'A long primary label that has to wrap in half a row', icon: TablerIcons.check, onTap: () {}),
                ]),
                Row(children: [SxButton(label: 'In row', onTap: () {})]),
                SxButton(label: 'Busy', loading: true, fullWidth: true, onTap: () {}),
                SxBottomCta(label: 'Go', onTap: () {}),
                SxTakeoverStrip(sellixOn: true, onToggle: () {}),
                SxTakeoverStrip(sellixOn: false, onToggle: () {}),
                SxPickChip(label: 'Pick', selected: true, onTap: () {}),
                const SxEmptyState(icon: TablerIcons.package, title: 'Empty', body: 'Body', actionLabel: 'Do'),
                SxErrorState(error: 'x', onRetry: () {}),
                const SxLogo(size: 40),
                const SxLogo(size: 40, surface: SxLogoSurface.anchor),
                SxAnchorCard(child: const Text('Anchor')),
              ],
            ),
          ),
          SxFilterChips(children: [SxFilterChip(label: 'All', selected: true, badge: 2, onTap: () {}), SxFilterChip(label: 'New', selected: false, onTap: () {})]),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SxFloatingNav(
              currentIndex: 1,
              onTap: (_) {},
              items: const [
                SxNavItem(icon: TablerIcons.home, label: 'Home'),
                SxNavItem(icon: TablerIcons.message_circle, label: 'Chats', badge: 3),
                SxNavItem(icon: TablerIcons.package, label: 'Stock', liveDot: true),
                SxNavItem(icon: TablerIcons.receipt, label: 'Orders', badge: 12),
                SxNavItem(icon: TablerIcons.user, label: 'Profile'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('every svg asset parses and draws', (tester) async {
    const names = ['apple', 'facebook', 'google', 'instagram', 'logo_glyph', 'logo_tile', 'messenger', 'paypal', 'upi', 'whatsapp'];
    for (final name in names) {
      final info = await tester.runAsync(() => vg.loadPicture(SvgAssetLoader('assets/icons/$name.svg'), null));
      expect(info!.size.isEmpty, isFalse, reason: name);
      info.picture.dispose();
    }
  });

  group('redirect', () {
    const signedIn = AsyncData(AuthStatus.signedIn);
    const signedOut = AsyncData(AuthStatus.signedOut);
    const done = AsyncData(true);
    const notDone = AsyncData(false);
    String? go(String l, AsyncValue<AuthStatus> a, AsyncValue<bool> s) => sellixRedirect(location: l, auth: a, setup: s);

    test('loading goes to splash, but never tears down a running sign-in', () {
      expect(go(Routes.home, const AsyncLoading(), const AsyncLoading()), Routes.splash);
      expect(go(Routes.connecting, const AsyncLoading(), const AsyncLoading()), isNull);
    });
    test('signed out reaches only the sign-in screens', () {
      expect(go(Routes.home, signedOut, notDone), Routes.auth);
      expect(go(Routes.chat('a'), signedOut, notDone), Routes.auth);
      expect(go(Routes.connected, signedOut, notDone), Routes.auth);
      expect(go(Routes.welcome, signedOut, notDone), isNull);
      expect(go(Routes.autherror, signedOut, notDone), isNull);
      expect(go(Routes.splash, signedOut, notDone), Routes.auth);
    });
    test('a new shop is held in onboarding', () {
      expect(go(Routes.home, signedIn, notDone), Routes.obShop);
      expect(go(Routes.auth, signedIn, notDone), Routes.obShop);
      expect(go(Routes.obPay, signedIn, notDone), isNull);
      expect(go(Routes.connected, signedIn, notDone), isNull);
    });
    test('a finished shop leaves sign-in but can finish its last onboarding steps', () {
      expect(go(Routes.splash, signedIn, done), Routes.home);
      expect(go(Routes.auth, signedIn, done), Routes.home);
      expect(go(Routes.obLive, signedIn, done), isNull);
      expect(go(Routes.order('1'), signedIn, done), isNull);
    });
    test('a failed onboarding check does not block the app', () {
      expect(go(Routes.home, signedIn, const AsyncError('x', StackTrace.empty)), isNull);
    });
  });

  testWidgets('every route opens; tabs show the nav, task screens hide it', (tester) async {
    await _pumpApp(tester, auth: AuthStatus.signedIn, completed: true);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SxFloatingNav), findsOneWidget);

    final router = _router(tester);
    for (final tab in [Routes.chats, Routes.stock, Routes.orders, Routes.profile, Routes.home]) {
      router.go(tab);
      await _settle(tester);
      expect(find.byType(SxFloatingNav).hitTestable(), findsOneWidget, reason: tab);
    }

    await tester.tap(find.descendant(of: find.byType(SxFloatingNav), matching: find.bySemanticsLabel(RegExp('^Chats'))));
    await _settle(tester);
    expect(router.state.matchedLocation, Routes.chats);
    await tester.tap(find.descendant(of: find.byType(SxFloatingNav), matching: find.bySemanticsLabel(RegExp('^Home'))));
    await _settle(tester);

    final tasks = [
      Routes.notifications, Routes.needs, Routes.insights, Routes.chat('c 1'), Routes.morning,
      Routes.product('v1'), Routes.addproduct, Routes.editProduct('v1'), Routes.order('o1'), Routes.customers,
      Routes.customer('u1'), Routes.automations, Routes.automation('a1'), Routes.newauto, Routes.rules,
      Routes.channels, Routes.payments, Routes.shopprofile, Routes.hours,
      Routes.obShop, Routes.obTalk, Routes.obRules, Routes.obHours, Routes.obPay, Routes.obTest, Routes.obStock, Routes.obLive,
      Routes.connected,
    ];
    for (final task in tasks) {
      router.push(task);
      await _settle(tester);
      expect(find.byType(SxFloatingNav).hitTestable(), findsNothing, reason: task);
      router.pop();
      await _settle(tester);
      expect(find.byType(SxFloatingNav).hitTestable(), findsOneWidget, reason: 'back from $task');
    }

    // A signed-in shop on /connecting has nothing left to do there: it moves on to Home.
    router.push(Routes.connecting);
    await _settle(tester);
    await _settle(tester);
    router.go(Routes.home);
    await _settle(tester);

    router.push(Routes.chat('c 1'));
    await _settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).conversationId, 'c 1');
    // Back button falls back to the parent when there is nothing to pop, and pops otherwise.
    await tester.tap(find.bySemanticsLabel('Back'));
    await _settle(tester);
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget);
  });

  testWidgets('signed out lands on auth, and the sign-in screens all open', (tester) async {
    await _pumpApp(tester, auth: AuthStatus.signedOut, completed: false);
    final router = _router(tester);
    expect(router.state.matchedLocation, Routes.auth);
    for (final r in [Routes.welcome, Routes.prebrief, Routes.iglogin, Routes.connecting, Routes.autherror]) {
      router.go(r);
      await _settle(tester);
      expect(router.state.matchedLocation, r);
    }
  });

  for (final (name, theme) in [('light', sellixLight), ('dark', sellixDark)]) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 1.6)]) {
      testWidgets('gallery lays out: $name, $width wide, text x$scale', (tester) async {
        tester.view.physicalSize = Size(width * 3, 6000 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: const _Gallery(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('sheet, confirm, snack with undo, async view', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: sellixLight,
      home: Builder(builder: (c) {
        ctx = c;
        return const SxScaffold(body: SizedBox());
      }),
    ));

    final answer = showSxConfirm(ctx, title: 'Send?', body: 'To the customer', confirmLabel: 'Send it');
    await tester.pumpAndSettle();
    expect(find.text('Send?'), findsOneWidget);
    await tester.tap(find.text('Send it'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);

    final dismissed = showSxConfirm(ctx, title: 'Send?', confirmLabel: 'Send it');
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(await dismissed, isFalse);

    showSxSheet<void>(ctx, title: 'Edit', builder: (_) => const SxField(hint: 'on sheet'));
    await tester.pumpAndSettle();
    showSxSnack(ctx, 'Above the sheet', icon: TablerIcons.check);
    await tester.pumpAndSettle();
    expect(find.text('Above the sheet'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Above the sheet')).dy,
      lessThan(tester.getTopLeft(find.byType(SxField)).dy),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Above the sheet'), findsNothing);
    Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pumpAndSettle();

    var undone = false;
    showSxSnack(ctx, 'sellix paused', icon: TablerIcons.player_pause, action: 'Undo', onAction: () => undone = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('sellix paused'), findsNothing);

    Widget view(AsyncValue<List<int>> v) => MaterialApp(
          theme: sellixDark,
          home: Scaffold(
            body: SxAsyncView<List<int>>(
              value: v,
              onRetry: () {},
              isEmpty: (d) => d.isEmpty,
              empty: const Text('nothing'),
              builder: (_, d) => Text('data ${d.length}'),
            ),
          ),
        );
    await tester.pumpWidget(view(const AsyncLoading()));
    expect(find.byType(SxSkeletonList), findsOneWidget);
    await tester.pumpWidget(view(const AsyncError('secret', StackTrace.empty)));
    await tester.pump();
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.pumpWidget(view(const AsyncData([])));
    expect(find.text('nothing'), findsOneWidget);
    await tester.pumpWidget(view(const AsyncData([1])));
    expect(find.text('data 1'), findsOneWidget);
  });
}
