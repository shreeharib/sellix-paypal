import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/nav_badges.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/chats/chat_screen.dart';
import 'package:sellix_merchant/features/chats/chats_providers.dart';
import 'package:sellix_merchant/features/chats/chats_screen.dart';

import '../../support/fake_sellix_api.dart';

const _chatB = '00000000-0000-4000-8000-0000000000b1';
const _chatC = '00000000-0000-4000-8000-0000000000c1';

Conversation _conversation(
  String id,
  String handle, {
  bool active = true,
  String body = 'Hi there',
  String sender = 'customer',
}) => Conversation(
  id: id,
  channel: 'instagram',
  customerHandle: handle,
  agentActive: active,
  agentPausedReason: active ? null : 'merchant_switched_off',
  lastMessageSender: sender,
  lastMessageBody: body,
  lastMessageAt: FakeSellixApi.now,
);

ChatMessage _message(String id, String sender, String body, {String status = 'sent'}) =>
    ChatMessage(
      id: id,
      direction: sender == 'customer' ? 'inbound' : 'outbound',
      sender: sender,
      body: body,
      status: status,
      createdAt: FakeSellixApi.now,
    );

/// No drafts unless a test adds some: the seed's draft has its own test.
FakeSellixApi _fake() => FakeSellixApi()..draftsByConversation = {};

class _ClosedQuestionApi extends FakeSellixApi {
  _ClosedQuestionApi() {
    draftsByConversation = {};
  }

  @override
  Future<Question> answerQuestion(String questionId, String answer, {bool always = false}) async {
    calls.add('answerQuestion');
    throw const ApiException('Already answered', statusCode: 409);
  }
}

class _RecordingApi extends FakeSellixApi {
  _RecordingApi() {
    draftsByConversation = {};
  }

  String? answer;
  bool? always;

  @override
  Future<Question> answerQuestion(String questionId, String answer, {bool always = false}) {
    this.answer = answer;
    this.always = always;
    return super.answerQuestion(questionId, answer, always: always);
  }
}

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester, FakeSellixApi fake, {String? start}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: start ?? Routes.chats,
    routes: [
      GoRoute(path: Routes.chats, builder: (_, _) => const ChatsScreen()),
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(s.pathParameters['id']!)),
      GoRoute(path: '/order/:id', builder: (_, s) => Text('order ${s.pathParameters['id']}')),
      GoRoute(path: '/customer/:id', builder: (_, s) => Text('customer ${s.pathParameters['id']}')),
    ],
  );
  addTearDown(router.dispose);
  _container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [sellixApiProvider.overrideWithValue(fake)],
  );
  addTearDown(_container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(
        theme: buildSellixTheme(SxPalette.light, Brightness.light),
        routerConfig: router,
      ),
    ),
  );
}

/// The live dot pulses for ever, so `pumpAndSettle` can't be used.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A snackbar's timer must not outlive the test.
Future<void> _clearSnack(WidgetTester tester) async {
  hideSxSnack();
  await _settle(tester);
}

/// Taps the last match. Contains, not equals: a button or event with an icon holds it in its text.
Future<void> _tapText(WidgetTester tester, String text) => _tap(tester, find.textContaining(text).last);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  group('chat state', () {
    final chat = _conversation('c', 'x');
    Order order(String status) => Order(
      id: status,
      number: 1,
      status: status,
      currency: 'INR',
      totalMinor: 100,
      conversationId: 'c',
      createdAt: FakeSellixApi.now,
      paidAt: null,
      holdExpiresAt: null,
      items: const [],
    );

    test('follows the question, the switch, then the order', () {
      final question = Question(
        id: 'q',
        conversationId: 'c',
        question: '?',
        status: 'open',
        answer: null,
        createdAt: FakeSellixApi.now,
        answeredAt: null,
      );
      final paused = _conversation('c', 'x', active: false);
      expect(chatStateOf(chat, [question], []), ChatState.needsYou);
      expect(chatStateOf(paused, [], []), ChatState.you);
      expect(chatStateOf(chat, [], []), ChatState.sellix);
      expect(chatStateOf(chat, [], [order(OrderStatus.awaitingPayment)]), ChatState.waitingPayment);
      expect(chatStateOf(chat, [], [order(OrderStatus.paid)]), ChatState.done);
      expect(chatStateOf(chat, [], [order(OrderStatus.cancelled)]), ChatState.done);
    });

    test('the chat order is the most urgent open one', () {
      final closed = order(OrderStatus.cancelled);
      final waiting = order(OrderStatus.awaitingPayment);
      final done = order(OrderStatus.completed);
      expect(chatOrderOf([closed, done, waiting]), waiting);
      expect(chatOrderOf([closed]), closed);
      expect(chatOrderOf([]), isNull);
    });

    test('held drafts stay out of the timeline', () {
      final held = _message('d', 'agent', 'Held', status: 'sending');
      final sent = _message('m', 'customer', 'Sent');
      final timeline = chatTimeline([sent, held], [held], []);
      expect(timeline.map((e) => e.message), [sent]);
    });
  });

  group('chat list', () {
    FakeSellixApi seeded() => _fake()
      ..conversationList = [
        _conversation(_chatB, 'Second Customer', body: 'Do you deliver?', sender: 'agent'),
        _conversation(_chatC, 'Third Customer', active: false, body: 'Thanks'),
        _conversation(FakeIds.conversationA, 'First Customer', body: 'Hello'),
      ];

    testWidgets('shows a skeleton while loading', (tester) async {
      final fake = seeded()..delay = const Duration(seconds: 1);
      await _pump(tester, fake);
      await tester.pump();
      expect(find.byType(SxSkeletonList), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.byType(SxSkeletonList), findsNothing);
    });

    testWidgets('lists chats, needing you first, with derived states', (tester) async {
      await _pump(tester, seeded());
      await _settle(tester);
      expect(find.text('sellix is on 1 of these 3 chats'), findsOneWidget);
      expect(find.text('sellix: Do you deliver?'), findsOneWidget);
      expect(find.text('You are on it'), findsOneWidget);
      final needs = tester.getTopLeft(find.text('First Customer')).dy;
      expect(needs, lessThan(tester.getTopLeft(find.text('Second Customer')).dy));
      expect(_container.read(navBadgesProvider).chatsNeedYou, 1);
      expect(_container.read(navBadgesProvider).chatsLive, isTrue);
    });

    testWidgets('filters and searches', (tester) async {
      await _pump(tester, seeded());
      await _settle(tester);

      await _tap(tester, find.text('You'));
      expect(find.text('Third Customer'), findsOneWidget);
      expect(find.text('Second Customer'), findsNothing);

      await _tap(tester, find.text('All'));
      await tester.enterText(find.byType(TextField), 'deliver');
      await _settle(tester);
      expect(find.text('Second Customer'), findsOneWidget);
      expect(find.text('First Customer'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nothing like this');
      await _settle(tester);
      expect(find.text('No chats match'), findsOneWidget);
    });

    testWidgets('an empty shop says so', (tester) async {
      await _pump(tester, FakeSellixApi.empty());
      await _settle(tester);
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Chats show here when customers message you.'), findsOneWidget);
    });

    testWidgets('an error offers retry', (tester) async {
      final fake = seeded()..failure = const ApiException('Could not load chats');
      await _pump(tester, fake);
      await _settle(tester);
      expect(find.text('Could not load chats'), findsOneWidget);
      fake.failure = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('First Customer'), findsOneWidget);
    });

    testWidgets('a row opens its thread', (tester) async {
      await _pump(tester, seeded());
      await _settle(tester);
      await tester.tap(find.text('Second Customer'));
      await _settle(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });

  group('thread', () {
    final start = Routes.chat(FakeIds.conversationA);

    FakeSellixApi seeded() => _fake()
      ..messagesByConversation = {
        FakeIds.conversationA: [
          _message('m1', 'customer', 'Hello'),
          _message('m2', 'agent', 'Hi, how can I help?'),
          _message('m3', 'merchant', 'I can do that'),
        ],
      };

    testWidgets('shows a skeleton while loading', (tester) async {
      final fake = seeded()..delay = const Duration(seconds: 1);
      await _pump(tester, fake, start: start);
      await tester.pump();
      expect(find.byType(SxSkeletonList), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows the thread, its order and its question', (tester) async {
      await _pump(tester, seeded(), start: start);
      await _settle(tester);
      expect(find.text('customer.one'), findsOneWidget);
      expect(find.text('Hi, how can I help?'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      // The paid order outranks the unpaid one: it's the one to act on.
      expect(find.text('Order #2'), findsOneWidget);
      expect(find.textContaining('New order'), findsOneWidget);
      expect(find.text('Can this be delivered tomorrow?'), findsOneWidget);
    });

    testWidgets('an error offers retry', (tester) async {
      final fake = seeded()..failure = const ApiException('Could not load this chat');
      await _pump(tester, fake, start: start);
      await _settle(tester);
      expect(find.text('Could not load this chat'), findsOneWidget);
      fake.failure = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('takes over and hands back through the agent switch', (tester) async {
      final fake = seeded();
      await _pump(tester, fake, start: start);
      await _settle(tester);

      await _tapText(tester, 'Take over');
      expect(fake.calls, contains('switchAgent'));
      expect(fake.conversationList.single.agentActive, isFalse);
      expect(find.text('You are on this chat'), findsOneWidget);
      expect(find.textContaining('You took over. sellix is quiet in this chat.'), findsOneWidget);

      await _tapText(tester, 'Give back to sellix');
      expect(fake.conversationList.single.agentActive, isTrue);
      expect(find.text('sellix is on this chat'), findsOneWidget);
      expect(find.textContaining('sellix is back on this chat'), findsOneWidget);
    });

    testWidgets('a failed switch leaves the strip and says why', (tester) async {
      final fake = seeded();
      await _pump(tester, fake, start: start);
      await _settle(tester);
      fake.failure = const ApiException('Could not switch');
      await _tapText(tester, 'Take over');
      expect(find.text('sellix is on this chat'), findsOneWidget);
      expect(find.text('Could not switch'), findsOneWidget);
      await _clearSnack(tester);
    });

    testWidgets('answers the question only after confirming', (tester) async {
      final fake = _RecordingApi()
        ..messagesByConversation = {
          FakeIds.conversationA: [_message('m1', 'customer', 'Hello')],
        };
      await _pump(tester, fake, start: start);
      await _settle(tester);

      await _tapText(tester, 'Write my own reply');
      await _tapText(tester, 'Send');
      expect(find.text('Type a reply first'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Yes, by noon');
      await _settle(tester);
      await _tapText(tester, 'Send');
      expect(find.text('Send this to customer.one?'), findsOneWidget);
      expect(fake.calls, isNot(contains('answerQuestion')));

      await _tapText(tester, 'Cancel');
      expect(fake.calls, isNot(contains('answerQuestion')));

      await _tapText(tester, 'Write my own reply');
      await tester.enterText(find.byType(TextField).last, 'Yes, by noon');
      await _settle(tester);
      await _tapText(tester, 'Send');
      await _tapText(tester, 'Send');

      expect(fake.answer, 'Yes, by noon');
      expect(fake.always, isFalse);
      expect(find.textContaining('You answered: Yes, by noon'), findsOneWidget);
      expect(find.text('Can this be delivered tomorrow?'), findsNothing);
      expect(find.text('Sent to customer.one.'), findsOneWidget);
      expect(_container.read(navBadgesProvider).chatsNeedYou, 0);
      await _clearSnack(tester);
    });

    testWidgets('a suggested answer goes straight to the send check, then sends as is', (tester) async {
      final fake = _RecordingApi()
        ..messagesByConversation = {
          FakeIds.conversationA: [_message('m1', 'customer', 'Hello')],
        };
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
            suggestedAnswers: const ['Ready by noon', 'Ask them to wait'],
          ),
      ];
      await _pump(tester, fake, start: start);
      await _settle(tester);
      expect(find.text('Ready by noon'), findsOneWidget);
      expect(find.text('Write my own reply'), findsOneWidget);

      await _tapText(tester, 'Ready by noon');
      expect(find.text('Send this to customer.one?'), findsOneWidget);
      expect(fake.calls, isNot(contains('answerQuestion')));
      await _tapText(tester, 'Send');

      expect(fake.answer, 'Ready by noon');
      expect(fake.always, isFalse);
      await _clearSnack(tester);
    });

    testWidgets('a question closed meanwhile says so', (tester) async {
      final fake = _ClosedQuestionApi();
      await _pump(tester, fake, start: start);
      await _settle(tester);
      await _tapText(tester, 'Write my own reply');
      await tester.enterText(find.byType(TextField).last, 'Yes');
      await _settle(tester);
      await _tapText(tester, 'Send');
      await _tapText(tester, 'Send');
      expect(find.text('This question is already closed.'), findsOneWidget);
      await _clearSnack(tester);
    });

    testWidgets('the composer is off and can not send', (tester) async {
      final fake = seeded();
      await _pump(tester, fake, start: start);
      await _settle(tester);
      final composer = tester.widget<SxComposer>(find.byType(SxComposer));
      expect(composer.enabled, isFalse);
      expect(composer.onSend, isNull);
      expect(find.text('Reply in Instagram for now'), findsOneWidget);
      expect(find.text('You can’t send messages from this app yet. Reply in Instagram.'), findsOneWidget);
    });

    testWidgets('a held draft is shown apart, and sends after confirming', (tester) async {
      final draft = _message(FakeIds.draftA, 'agent', 'Held reply', status: 'sending');
      final fake = FakeSellixApi()
        ..messagesByConversation = {
          FakeIds.conversationA: [_message('m1', 'customer', 'Hello'), draft],
        }
        ..draftsByConversation = {
          FakeIds.conversationA: [draft],
        };
      await _pump(tester, fake, start: start);
      await _settle(tester);
      expect(find.text('sellix wrote this and is waiting for you'), findsOneWidget);
      expect(find.text('Sending…'), findsNothing);

      await _tapText(tester, 'Send');
      expect(fake.calls, isNot(contains('approveDraft')));
      await _tapText(tester, 'Send');
      expect(fake.calls, contains('approveDraft'));
      expect(find.text('sellix wrote this and is waiting for you'), findsNothing);
      await _clearSnack(tester);
    });

    testWidgets('the menu leads to the order and the customer', (tester) async {
      await _pump(tester, seeded(), start: start);
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Chat menu'));
      await _settle(tester);
      expect(find.text('1 paid order · ₹200 spent'), findsOneWidget);
      expect(find.text('Open in Instagram'), findsOneWidget);
      expect(find.text('Not available yet. sellix takes orders in the chat.'), findsOneWidget);

      await _tapText(tester, 'View customer');
      expect(find.text('customer ${FakeIds.conversationA}'), findsOneWidget);
    });
  });
}
