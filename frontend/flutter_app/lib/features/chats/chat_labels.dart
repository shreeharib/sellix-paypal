import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../design/design.dart';
import 'chats_providers.dart';

/// `instagram` reads `Instagram`.
String channelName(String channel) => switch (channel) {
  'instagram' => 'Instagram',
  'whatsapp' => 'WhatsApp',
  'messenger' => 'Messenger',
  '' => 'the app',
  _ => channel[0].toUpperCase() + channel.substring(1),
};

SxBrand? channelBrand(String channel) => switch (channel) {
  'instagram' => SxBrand.instagram,
  'whatsapp' => SxBrand.whatsapp,
  'messenger' => SxBrand.messenger,
  _ => null,
};

/// The first word of a handle, for copy like "Sent to Priya".
String firstNameOf(String handle) {
  final words = handle.trim().split(RegExp(r'\s+'));
  return words.first.isEmpty ? handle : words.first;
}

/// `4:12 PM` today, otherwise `Yesterday` or `Thu 29 Oct`.
String chatStamp(DateTime time) {
  final day = dayLabel(time);
  return day == 'Today' ? formatTime(time) : day;
}

/// The last message, with who wrote it when it wasn't the customer.
String chatPreview(Conversation chat) {
  final body = chat.lastMessageBody;
  if (body == null || body.isEmpty) return 'No messages yet';
  return switch (chat.lastMessageSender) {
    'agent' => 'sellix: $body',
    'merchant' => 'You: $body',
    _ => body,
  };
}

/// The chip of a chat's state, with the prototype's labels.
Widget chatStateChip(ChatState state) => switch (state) {
  ChatState.needsYou => const SxChip(
    label: 'Needs you',
    tone: SxChipTone.attention,
    icon: TablerIcons.hand_stop,
  ),
  ChatState.sellix => const SxChip(label: 'sellix on it', dot: true, pulse: true),
  ChatState.waitingPayment => const SxChip(label: 'Waiting payment'),
  ChatState.you => const SxChip(label: 'You are on it'),
  ChatState.done => const SxChip(label: 'Done', tone: SxChipTone.positive),
};

/// An order's status chip, the prototype's `ORDER_STATE` mapped onto the backend's statuses.
Widget orderStatusChip(Order order) => switch (order.status) {
  OrderStatus.expired => const SxChip(label: 'Expired', icon: TablerIcons.clock_x),
  OrderStatus.cancelled => const SxChip(label: 'Cancelled', icon: TablerIcons.ban),
  OrderStatus.refunded => const SxChip(label: 'Refunded', icon: TablerIcons.arrow_back_up),
  OrderStatus.awaitingPayment => const SxChip(label: 'Waiting payment', icon: TablerIcons.clock),
  OrderStatus.completed => const SxChip(
    label: 'Completed',
    tone: SxChipTone.positive,
    icon: TablerIcons.check,
  ),
  OrderStatus.delivered => const SxChip(
    label: 'Delivered',
    tone: SxChipTone.positive,
    icon: TablerIcons.check,
  ),
  OrderStatus.paid => const SxChip(
    label: 'New order',
    tone: SxChipTone.attention,
    icon: TablerIcons.bell_ringing,
  ),
  OrderStatus.confirmed => const SxChip(label: 'Accepted', icon: TablerIcons.check),
  OrderStatus.ready => SxChip(
    label: order.fulfilmentMethod == 'pickup' ? 'Ready for pickup' : 'Ready',
    icon: TablerIcons.package,
  ),
  _ => const SxChip(label: 'Placed', icon: TablerIcons.receipt),
};

/// The small line under a bubble: its time, or what's happening to it.
String bubbleTime(ChatMessage message) => switch (message.status) {
  'sending' => 'Sending…',
  'failed' => 'Not sent, ${formatTime(message.createdAt)}',
  _ => formatTime(message.createdAt),
};

/// What the backend will do with an answer to [question], before the merchant commits to it.
String answerNote(Question question, String first, String channel) => switch (question.windowState) {
  'closed' => '$channel’s window for this chat has closed, so $first won’t get this.',
  'human_agent_only' =>
    'It has been over 24 hours. This goes when $channel allows it, or when $first writes again.',
  _ => 'sellix passes this on to $first. You can’t undo this.',
};

/// The confirmation after an answer, saying what really happened to it.
String answeredSnack(String? delivery, String first, String channel) => switch (delivery) {
  'sent' => 'Sent to $first.',
  'human_agent' => 'Sent to $first as you wrote it.',
  'pending_window' => 'Saved. $first gets this when they write again.',
  'expired' => 'Saved, but $first won’t get this. The $channel window has closed.',
  _ => 'Answer saved.',
};

/// The line a thread keeps for an answered question.
String answeredEvent(Question question) {
  final line = 'You answered: ${question.answer ?? ''}';
  return switch (question.answerDelivery) {
    'pending_window' => '$line (waiting for them to write again)',
    'expired' => '$line (not delivered)',
    _ => line,
  };
}
