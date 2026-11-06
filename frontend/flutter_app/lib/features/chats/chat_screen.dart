import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/nav_badges.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'chat_labels.dart';
import 'chat_sheets.dart';
import 'chats_providers.dart';

/// One conversation: read it, answer what sellix asks, take over or hand back.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen(this.conversationId, {super.key});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  String get _id => widget.conversationId;

  /// The switch's result, until a reload agrees with it.
  bool? _agentActive;
  bool _switching = false;

  /// The note the last take over or give back left at the end of the thread.
  ({String text, IconData icon})? _switchNote;

  /// Answers given on this screen: shown at once, even if the reload after them fails.
  final List<Question> _justAnswered = [];
  final Set<String> _busy = {};
  int _stuckLength = -1;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stickToEnd(int length) {
    if (length == _stuckLength) return;
    _stuckLength = length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _pushBadge(ChatThread thread) {
    final answered = {for (final q in _justAnswered) q.id};
    final needYou = {
      for (final q in thread.allOpen)
        if (!answered.contains(q.id)) q.conversationId,
    }.length;
    if (ref.read(navBadgesProvider).chatsNeedYou == needYou) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navBadgesProvider.notifier).update(chatsNeedYou: needYou);
    });
  }

  Future<void> _refresh() => refreshChatThread(ref, _id);

  Future<void> _switchAgent(bool active) async {
    setState(() => _switching = true);
    try {
      final result = await ref.read(sellixApiProvider).switchAgent(_id, active: active);
      if (!mounted) return;
      setState(() {
        _agentActive = result.active;
        _switchNote = result.active
            ? (text: 'sellix is back on this chat', icon: TablerIcons.sparkles)
            : (text: 'You took over. sellix is quiet in this chat.', icon: TablerIcons.user);
      });
      _stuckLength = -1;
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) showSxSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _answer(Question question, Conversation chat) async {
    final first = firstNameOf(chat.customerHandle);
    final channel = channelName(chat.channel);
    final draft = await showAnswerSheet(context, question.question);
    if (draft == null || !mounted) return;
    final confirmed = await showSxConfirm(
      context,
      title: 'Send this to $first?',
      body: '“${draft.text}”\n\n${answerNote(question, first, channel)}',
      confirmLabel: 'Send',
      confirmIcon: TablerIcons.send,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(question.id));
    try {
      final answered = await ref
          .read(sellixApiProvider)
          .answerQuestion(question.id, draft.text, always: draft.always);
      if (!mounted) return;
      setState(() => _justAnswered.add(answered));
      // BACKEND GAP: an answer can't be taken back, so the prototype's Undo is left out.
      final said = answeredSnack(answered.answerDelivery, first, channel);
      showSxSnack(
        context,
        draft.always ? '$said Rule saved. sellix will answer this alone.' : said,
        icon: answered.answerDelivery == 'expired' ? TablerIcons.info_circle : TablerIcons.send,
      );
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 404 || error.statusCode == 409) {
        showSxSnack(context, 'This question is already closed.', icon: TablerIcons.info_circle);
        await _refresh();
      } else {
        showSxSnack(context, error.message);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(question.id));
    }
  }

  Future<void> _sendDraft(ChatMessage draft, Conversation chat) async {
    final first = firstNameOf(chat.customerHandle);
    final confirmed = await showSxConfirm(
      context,
      title: 'Send this to $first?',
      body: '“${draft.body}”',
      confirmLabel: 'Send',
      confirmIcon: TablerIcons.send,
    );
    if (!confirmed || !mounted) return;
    await _settleDraft(
      draft,
      () => ref.read(sellixApiProvider).approveDraft(_id, draft.id),
      'Sent to $first.',
    );
  }

  Future<void> _discardDraft(ChatMessage draft) async {
    final confirmed = await showSxConfirm(
      context,
      title: 'Discard this reply?',
      body: '“${draft.body}”',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    await _settleDraft(
      draft,
      () => ref.read(sellixApiProvider).discardDraft(_id, draft.id),
      'Reply discarded.',
    );
  }

  Future<void> _settleDraft(ChatMessage draft, Future<void> Function() act, String done) async {
    setState(() => _busy.add(draft.id));
    try {
      await act();
      if (!mounted) return;
      showSxSnack(context, done);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) showSxSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _busy.remove(draft.id));
    }
  }

  Future<void> _openMenu(ChatThread thread, Conversation chat) async {
    final order = chatOrderOf(thread.orders);
    final choice = await showChatMenu(context, chat: chat, orders: thread.orders, order: order);
    if (!mounted || choice == null) return;
    switch (choice) {
      case ChatMenuChoice.customer:
        await context.push(Routes.customer(chat.id));
      case ChatMenuChoice.order:
        await _openOrder(order!);
      case ChatMenuChoice.inbox:
        final opened = await launchUrl(
          Uri.parse('https://www.instagram.com/direct/inbox/'),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) showSxSnack(context, 'Could not open Instagram.');
    }
  }

  Future<void> _openOrder(Order order) async {
    await context.push(Routes.order(order.id));
    // Back from the order: the status link and the question may have moved.
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(chatThreadProvider(_id));
    final thread = value.value;
    final chat = thread?.conversation;
    if (chat != null && chat.agentActive == _agentActive) _agentActive = null;
    final sellixOn = _agentActive ?? chat?.agentActive ?? true;
    final order = thread == null ? null : chatOrderOf(thread.orders);
    return SxScaffold(
      floatingMargin: 16,
      floating: chat == null ? null : _disabledComposer(context, chat),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxDetailHeader(
            title: chat?.customerHandle ?? '',
            metaWidget: chat == null ? null : _channelMeta(context, chat),
            fallback: Routes.chats,
            trailing: chat == null
                ? null
                : SxIconButton(
                    icon: TablerIcons.dots_vertical,
                    semanticLabel: 'Chat menu',
                    onTap: () => _openMenu(thread!, chat),
                  ),
          ),
          if (chat != null) ...[
            SxTakeoverStrip(
              sellixOn: sellixOn,
              loading: _switching,
              onToggle: _switching ? null : () => _switchAgent(!sellixOn),
            ),
            if (order != null) _orderLink(context, order),
          ],
          Expanded(
            child: SxAsyncView<ChatThread>(
              value: value,
              onRetry: _refresh,
              loading: const SxSkeletonList(),
              isEmpty: (data) => data.conversation == null,
              empty: const SxEmptyState(
                icon: TablerIcons.message_off,
                title: 'This chat is not in your recent chats',
                body: 'Only your latest 100 chats can be opened.',
              ),
              builder: (context, data) {
                _pushBadge(data);
                return _messages(context, data, data.conversation!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelMeta(BuildContext context, Conversation chat) {
    final brand = channelBrand(chat.channel);
    // BACKEND GAP: conversations have no language, so the prototype's "Instagram, Tamil" and its
    // "Show in English" translations are left out.
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SxSpace.s4,
      children: [
        if (brand != null) SxBrandIcon(brand, size: 16),
        Text(
          channelName(chat.channel),
          style: SxText.caption.copyWith(color: context.sx.textSecondary),
        ),
      ],
    );
  }

  Widget _orderLink(BuildContext context, Order order) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SxSpace.screen, 0, SxSpace.screen, SxSpace.s8),
      child: Semantics(
        label: 'Open order ${order.number}',
        child: SxCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => _openOrder(order),
          child: Row(
            spacing: SxSpace.s8,
            children: [
              Text('Order #${order.number}', style: SxText.label.copyWith(color: p.textPrimary)),
              Expanded(
                child: Text(
                  money(order.totalMinor, order.currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxText.caption.copyWith(color: p.textSecondary),
                ),
              ),
              Flexible(child: orderStatusChip(order)),
              Icon(TablerIcons.chevron_right, size: 16, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messages(BuildContext context, ChatThread thread, Conversation chat) {
    final p = context.sx;
    final done = {for (final q in _justAnswered) q.id};
    final answered = [
      ...thread.answered,
      for (final q in _justAnswered)
        if (!thread.answered.any((known) => known.id == q.id)) q,
    ];
    final timeline = chatTimeline(thread.messages, thread.drafts, answered);
    final open = thread.open.where((q) => !done.contains(q.id)).toList();
    _stickToEnd(timeline.length + open.length + thread.drafts.length);

    final channel = channelName(chat.channel);
    String? day;
    return SxScrollList(
      controller: _scroll,
      onRefresh: _refresh,
      padding: EdgeInsets.fromLTRB(
        SxSpace.screen,
        SxSpace.s4,
        SxSpace.screen,
        sxBottomInset(context),
      ),
      children: [
        // One Column, so the list knows its full height and can open on the latest message.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: SxSpace.s8,
          children: [
            if (timeline.isEmpty)
              const SxSystemEvent('No messages yet', icon: TablerIcons.info_circle),
            for (final entry in timeline) ...[
              if (dayLabel(entry.time) != day) SxDateSeparator(day = dayLabel(entry.time)),
              _entry(entry),
            ],
            if (_switchNote case final note?) SxSystemEvent(note.text, icon: note.icon),
            for (final draft in thread.drafts)
              SxFadeUp(
                key: ValueKey(draft.id),
                child: SxEscalationCard(
                  title: 'sellix wrote this and is waiting for you',
                  icon: TablerIcons.pencil,
                  body: draft.body,
                  options: [
                    SxEscalationOption(
                      label: 'Send',
                      recommended: true,
                      onTap: _busy.contains(draft.id) ? null : () => _sendDraft(draft, chat),
                    ),
                    SxEscalationOption(
                      label: 'Discard',
                      onTap: _busy.contains(draft.id) ? null : () => _discardDraft(draft),
                    ),
                  ],
                ),
              ),
            for (final question in open)
              SxFadeUp(
                key: ValueKey(question.id),
                // BACKEND GAP: questions carry no suggested answers, so the prototype's option
                // buttons can't be shown. Only "Write my own reply" is real.
                child: SxEscalationCard(
                  body: question.question,
                  options: [
                    SxEscalationOption(
                      label: 'Write my own reply',
                      recommended: true,
                      onTap: _busy.contains(question.id) ? null : () => _answer(question, chat),
                    ),
                  ],
                ),
              ),
            // BACKEND GAP: no endpoint sends a free-form message from the merchant. The chat routers
            // (chats.py, questions.py) only switch the agent, answer questions and approve drafts.
            Padding(
              padding: const EdgeInsets.only(top: SxSpace.s8),
              child: Text(
                'You can’t send messages from this app yet. Reply in $channel.',
                textAlign: TextAlign.center,
                style: SxText.micro.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _entry(ChatEntry entry) {
    final question = entry.answered;
    if (question != null) {
      return SxSystemEvent(answeredEvent(question), icon: TablerIcons.check);
    }
    final message = entry.message!;
    // BACKEND GAP: messages carry no attachments or product cards, only their text.
    final text = message.body.isEmpty ? 'Sent an attachment' : message.body;
    return switch (message.sender) {
      'system' => SxSystemEvent(text, icon: TablerIcons.info_circle),
      'customer' => SxBubble(
        text: text,
        sender: SxBubbleSender.customer,
        time: bubbleTime(message),
      ),
      'merchant' => SxBubble(
        text: text,
        sender: SxBubbleSender.merchant,
        time: bubbleTime(message),
      ),
      _ => SxBubble(text: text, sender: SxBubbleSender.sellix, time: bubbleTime(message)),
    };
  }

  /// The prototype's composer, switched off. The backdrop keeps the thread from showing through it.
  Widget _disabledComposer(BuildContext context, Conversation chat) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.sx.page,
        borderRadius: BorderRadius.circular(SxRadius.pill),
      ),
      child: Opacity(
        opacity: 0.55,
        child: SxComposer(
          controller: _composer,
          hint: 'Reply in ${channelName(chat.channel)} for now',
          enabled: false,
          // BACKEND GAP: no endpoint sends a merchant's message. See the note in the thread.
          onSend: null,
        ),
      ),
    );
  }
}
