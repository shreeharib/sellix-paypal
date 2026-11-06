import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'home_providers.dart';
import 'question_actions.dart';

/// Screen margin.
class HomeMargin extends StatelessWidget {
  const HomeMargin({super.key, required this.child, this.top = 0});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(SxSpace.screen, top, SxSpace.screen, 0),
    child: child,
  );
}

/// "All clear" in the needs-you list.
class AllClearCard extends StatelessWidget {
  const AllClearCard({super.key});

  @override
  Widget build(BuildContext context) => const SxRowCard(
    icon: TablerIcons.mood_smile,
    title: 'All clear',
    meta: 'sellix is handling every chat.',
    chevron: false,
  );
}

/// A needs-you card. On Home it pairs "Open chat" with "Answer"; the queue pairs "Dismiss" with
/// "Answer" and adds the links below.
class QuestionCard extends StatelessWidget {
  const QuestionCard({super.key, required this.question, required this.data, this.full = false});

  final Question question;
  final HomeData data;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final customer = data.customerOf(question.conversationId);
    final chat = data.chatOf(question.conversationId);
    final channel = chat?.channel;
    final aboveBar = !full;
    void openChat() => context.push(Routes.chat(question.conversationId));
    return SxNeedsYouCard(
      name: customer,
      meta: [if (channel != null) channelName(channel), relativeTime(question.createdAt)].join(', '),
      channel: channel == null ? null : brandOfChannel(channel),
      reason: questionReason(question),
      reasonIcon: TablerIcons.hand_stop,
      message: question.question,
      note: questionNote(question),
      secondaryLabel: full ? 'Dismiss' : 'Open chat',
      onSecondary: full ? () => dismissQuestionFlow(context, question, customer, aboveBar: aboveBar) : openChat,
      primaryLabel: 'Answer',
      onPrimary: () => answerQuestionFlow(context, question, customer, aboveBar: aboveBar),
      extra: full
          ? Padding(
              padding: const EdgeInsets.only(top: SxSpace.s8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SxLinkButton(label: 'Open chat', icon: TablerIcons.message_circle, onTap: openChat),
                  // BACKEND GAP: no voice transcription endpoint, so "Answer by voice" is off.
                  const Flexible(
                    child: SxLinkButton(label: 'Voice not ready yet', icon: TablerIcons.microphone, onTap: null),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

/// The compact order row used outside the Orders tab.
class HomeOrderRow extends StatelessWidget {
  const HomeOrderRow({super.key, required this.order, required this.data});

  final Order order;
  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final state = orderStateOf(order);
    final channel = channelName(order.channel);
    return SxCard(
      onTap: () => context.push(Routes.order(order.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SxSpace.s8,
        children: [
          Row(
            children: [
              const SxIconTile(icon: TablerIcons.receipt),
              const SizedBox(width: SxSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data.customerOf(order.conversationId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                          ),
                        ),
                        const SizedBox(width: SxSpace.s8),
                        Text(
                          money(order.totalMinor, order.currency),
                          style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      '#${order.number} · $channel · ${itemsLine(order)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SxChip(label: state.label, tone: state.tone, icon: state.icon),
        ],
      ),
    );
  }
}

/// A chat sellix is on, on Home.
class HomeChatRow extends StatelessWidget {
  const HomeChatRow({super.key, required this.chat, required this.data});

  final Conversation chat;
  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final awaiting = data.chatAwaitsPayment(chat.id);
    final last = chat.lastMessageAt;
    return SxRowCard(
      leading: SxCustomerAvatar(name: chat.customerHandle, channel: brandOfChannel(chat.channel)),
      title: chat.customerHandle,
      metaWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SxSpace.s8,
        children: [
          Text(chat.lastMessageBody ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          if (awaiting)
            const SxChip(label: 'Waiting payment', icon: TablerIcons.clock)
          else
            const SxChip(label: 'sellix on it', dot: true, pulse: true),
        ],
      ),
      trailing: last == null
          ? null
          : Text(relativeTime(last), style: SxText.micro.copyWith(color: p.textSecondary)),
      onTap: () => context.push(Routes.chat(chat.id)),
    );
  }
}
