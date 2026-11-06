import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../orders/orders_providers.dart';

/// Every conversation of the shop, as the backend sorts them. Shared: other features join orders to
/// it on `conversation_id` for the customer's handle.
final conversationsProvider = FutureProvider.autoDispose<List<Conversation>>(
  (ref) => ref.watch(sellixApiProvider).conversations(),
);

/// Open questions across the shop. The chat list and the thread both derive state from it.
final openQuestionsProvider = FutureProvider.autoDispose<List<Question>>(
  (ref) => ref.watch(sellixApiProvider).questions(),
);

/// Answered questions across the shop, for the "You answered" lines in a thread. The backend keeps
/// no message for them.
final answeredQuestionsProvider = FutureProvider.autoDispose<List<Question>>(
  (ref) => ref.watch(sellixApiProvider).questions(status: 'answered'),
);

/// The most the backend returns in one call.
// BACKEND GAP: messages have no paging, so a thread only shows its latest 500.
const chatMessagesWindow = 500;

/// A conversation's messages, oldest first.
final chatMessagesProvider = FutureProvider.autoDispose.family<List<ChatMessage>, String>(
  (ref, id) => ref.watch(sellixApiProvider).messages(id, limit: chatMessagesWindow),
);

/// Replies sellix wrote and is holding for approval (draft-mode shops only; otherwise empty).
final chatDraftsProvider = FutureProvider.autoDispose.family<List<ChatMessage>, String>(
  (ref, id) => ref.watch(sellixApiProvider).drafts(id),
);

/// What sellix remembers about this customer.
final chatMemoryProvider = FutureProvider.autoDispose.family<List<MemoryFact>, String>(
  (ref, id) => ref.watch(sellixApiProvider).customerMemory(id),
);

/// Everything the chat list shows.
class ChatListData {
  const ChatListData({required this.conversations, required this.open, required this.orders});

  final List<Conversation> conversations;
  final List<Question> open;
  final List<Order> orders;

  ChatState stateOf(Conversation chat) => chatStateOf(chat, open, orders);

  /// Chats with an open question.
  int get needYou => conversations.where((c) => stateOf(c) == ChatState.needsYou).length;

  /// The prototype's "sellix is on N": sellix is working the chat, including waiting for payment.
  int get sellixOn => conversations.where((c) {
    final state = stateOf(c);
    return state == ChatState.sellix || state == ChatState.waitingPayment;
  }).length;
}

final chatListProvider = FutureProvider.autoDispose<ChatListData>((ref) async {
  final conversations = ref.watch(conversationsProvider.future);
  final open = ref.watch(openQuestionsProvider.future);
  final orders = ref.watch(ordersProvider.future);
  await Future.wait<Object?>([conversations, open, orders]);
  return ChatListData(conversations: await conversations, open: await open, orders: await orders);
});

/// Reloads the list. A failure stays on the provider, where the screen reports it.
Future<void> refreshChatList(WidgetRef ref) async {
  ref
    ..invalidate(conversationsProvider)
    ..invalidate(openQuestionsProvider)
    ..invalidate(ordersProvider);
  try {
    await ref.read(chatListProvider.future);
  } on Object {
    // Shown by SxAsyncView.
  }
}

/// The filters above the list. The prototype's "Taking order" can't be derived, so its place holds
/// "sellix on it", the prototype's label for the chats sellix is handling.
// BACKEND GAP: conversation order stage, needed for the prototype's "Taking order" filter.
enum ChatFilter {
  all('All'),
  needsYou('Needs you'),
  sellix('sellix on it'),
  waitingPayment('Waiting payment'),
  you('You'),
  done('Done');

  const ChatFilter(this.label);

  final String label;

  bool matches(ChatState state) => switch (this) {
    ChatFilter.all => true,
    ChatFilter.needsYou => state == ChatState.needsYou,
    ChatFilter.sellix => state == ChatState.sellix,
    ChatFilter.waitingPayment => state == ChatState.waitingPayment,
    ChatFilter.you => state == ChatState.you,
    ChatFilter.done => state == ChatState.done,
  };
}

/// The rows for a filter and a search, chats that need the merchant on top, otherwise as the
/// backend sorts them (latest activity first).
List<Conversation> filterChats(ChatListData data, ChatFilter filter, String query) {
  final wanted = query.trim().toLowerCase();
  final found = data.conversations.where(
    (chat) =>
        filter.matches(data.stateOf(chat)) &&
        (chat.customerHandle.toLowerCase().contains(wanted) ||
            (chat.lastMessageBody ?? '').toLowerCase().contains(wanted)),
  );
  return [
    ...found.where((chat) => data.stateOf(chat) == ChatState.needsYou),
    ...found.where((chat) => data.stateOf(chat) != ChatState.needsYou),
  ];
}

/// Everything one thread shows. [conversation] is null when the chat isn't in the latest 100 the
/// backend lists.
// BACKEND GAP: no GET /v1/conversations/{id}, so an older chat can't be opened from a link.
class ChatThread {
  const ChatThread({
    required this.conversation,
    required this.messages,
    required this.drafts,
    required this.open,
    required this.answered,
    required this.allOpen,
    required this.orders,
  });

  final Conversation? conversation;
  final List<ChatMessage> messages;
  final List<ChatMessage> drafts;

  /// This chat's questions.
  final List<Question> open;
  final List<Question> answered;

  /// The whole shop's open questions, for the nav badge.
  final List<Question> allOpen;

  /// This chat's orders, newest first.
  final List<Order> orders;
}

final chatThreadProvider = FutureProvider.autoDispose.family<ChatThread, String>((ref, id) async {
  final conversations = ref.watch(conversationsProvider.future);
  final messages = ref.watch(chatMessagesProvider(id).future);
  final drafts = ref.watch(chatDraftsProvider(id).future);
  final open = ref.watch(openQuestionsProvider.future);
  final answered = ref.watch(answeredQuestionsProvider.future);
  final orders = ref.watch(ordersProvider.future);
  await Future.wait<Object?>([conversations, messages, drafts, open, answered, orders]);
  final allOpen = await open;
  return ChatThread(
    conversation: (await conversations).where((chat) => chat.id == id).firstOrNull,
    messages: await messages,
    drafts: await drafts,
    open: allOpen.where((q) => q.conversationId == id).toList(),
    answered: (await answered).where((q) => q.conversationId == id).toList(),
    allOpen: allOpen,
    orders: ordersOf(id, await orders),
  );
});

/// Reloads one thread. A failure stays on the provider, where the screen reports it.
Future<void> refreshChatThread(WidgetRef ref, String id) async {
  ref
    ..invalidate(conversationsProvider)
    ..invalidate(chatMessagesProvider(id))
    ..invalidate(chatDraftsProvider(id))
    ..invalidate(openQuestionsProvider)
    ..invalidate(answeredQuestionsProvider)
    ..invalidate(ordersProvider);
  try {
    await ref.read(chatThreadProvider(id).future);
  } on Object {
    // Shown by SxAsyncView.
  }
}

/// One line of a thread: a message or a "You answered" event, in time order.
class ChatEntry {
  const ChatEntry({required this.time, this.message, this.answered});

  final DateTime time;
  final ChatMessage? message;
  final Question? answered;
}

/// The thread in time order, without drafts: the backend lists a held draft among the messages with
/// status "sending", and it must not read as something the customer got. [answered] are this chat's
/// answered questions.
List<ChatEntry> chatTimeline(
  List<ChatMessage> messages,
  List<ChatMessage> drafts,
  List<Question> answered,
) {
  final held = {for (final draft in drafts) draft.id};
  final entries = [
    for (final message in messages)
      if (!message.isDraft && !held.contains(message.id))
        ChatEntry(time: message.createdAt, message: message),
    for (final question in answered)
      ChatEntry(time: question.answeredAt ?? question.createdAt, answered: question),
  ];
  // Dart's sort isn't stable, and messages can share a timestamp.
  final order = {for (final (index, entry) in entries.indexed) entry: index};
  return entries..sort((a, b) {
    final byTime = a.time.compareTo(b.time);
    return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
  });
}

/// The state of a chat in the list. The backend has no such field: see [chatStateOf].
enum ChatState { needsYou, you, waitingPayment, done, sellix }

const _closedStatuses = {OrderStatus.expired, OrderStatus.cancelled, OrderStatus.refunded};

/// Derives the state from real data, in this order: an open question, then the merchant having
/// taken over, then the conversation's latest order, otherwise sellix is on it. As in the prototype,
/// a chat's state follows its order: unpaid is waiting payment, and paid or closed is done.
///
/// The prototype's "Taking order" isn't derivable: the API exposes no order stage per conversation.
// BACKEND GAP: conversation order stage, needed for a "Taking order" state.
ChatState chatStateOf(Conversation chat, List<Question> open, List<Order> orders) {
  if (open.any((q) => q.conversationId == chat.id)) return ChatState.needsYou;
  if (!chat.agentActive) return ChatState.you;
  final latest = latestOrderOf(chat.id, orders);
  if (latest == null) return ChatState.sellix;
  return switch (latest.status) {
    OrderStatus.awaitingPayment => ChatState.waitingPayment,
    OrderStatus.draft || OrderStatus.pending => ChatState.sellix,
    _ => ChatState.done,
  };
}

/// The conversation's orders, newest first.
List<Order> ordersOf(String conversationId, List<Order> orders) {
  final mine = [
    for (final order in orders)
      if (order.conversationId == conversationId) order,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return mine;
}

Order? latestOrderOf(String conversationId, List<Order> orders) {
  final mine = ordersOf(conversationId, orders);
  return mine.isEmpty ? null : mine.first;
}

/// The order to show in a chat: its most urgent open order, otherwise its latest. Takes the chat's
/// orders, newest first. Mirrors the prototype's `chatOrder`.
Order? chatOrderOf(List<Order> mine) {
  int rank(Order order) => switch (order.status) {
    OrderStatus.paid => 0,
    OrderStatus.awaitingPayment => 1,
    OrderStatus.completed || OrderStatus.delivered => 3,
    _ => 2,
  };
  Order? best;
  for (final order in mine) {
    if (_closedStatuses.contains(order.status)) continue;
    if (best == null || rank(order) < rank(best)) best = order;
  }
  return best ?? mine.firstOrNull;
}
