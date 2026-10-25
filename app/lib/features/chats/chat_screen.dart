import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import 'chats_screen.dart';

final messagesProvider = FutureProvider.autoDispose.family<List<ChatMessage>, String>(
  (ref, conversationId) => ref.watch(sellixApiProvider).messages(conversationId),
);

/// One chat: the messages, and the switch for whether the agent replies here.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final chats = ref.watch(conversationsProvider).asData?.value ?? const <Conversation>[];
    final chat = chats.where((c) => c.id == conversationId).firstOrNull;
    final messages = ref.watch(messagesProvider(conversationId));
    return Scaffold(
      appBar: AppBar(title: Text(chat?.customerHandle ?? '')),
      body: Column(
        children: [
          if (chat != null) _AgentSwitch(chat: chat),
          Expanded(
            child: AsyncView(
              value: messages,
              onRetry: () => ref.invalidate(messagesProvider(conversationId)),
              data: (items) => items.isEmpty
                  ? MessageView(icon: Icons.chat_outlined, title: l10n.chatsNoMessages)
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(messagesProvider(conversationId).future),
                      child: ContentWidth(
                        child: ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(Insets.md),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _Bubble(message: items[items.length - 1 - index]),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentSwitch extends ConsumerStatefulWidget {
  const _AgentSwitch({required this.chat});

  final Conversation chat;

  @override
  ConsumerState<_AgentSwitch> createState() => _AgentSwitchState();
}

class _AgentSwitchState extends ConsumerState<_AgentSwitch> {
  bool _saving = false;

  Future<void> _toggle(bool active) async {
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).switchAgent(widget.chat.id, active: active);
      ref.invalidate(conversationsProvider);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SwitchListTile(
        value: widget.chat.agentActive,
        onChanged: _saving ? null : _toggle,
        title: Text(
          widget.chat.agentActive ? l10n.chatsAgentInThisChat : l10n.chatsAgentInThisChatOff,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mine = !message.fromCustomer;
    final failed = message.status == 'failed';
    final sender = switch (message.sender) {
      'agent' => l10n.chatsSenderAgent,
      'merchant' => l10n.chatsSenderYou,
      _ => null,
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Insets.xs),
          padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
          decoration: BoxDecoration(
            color: mine ? colors.primaryContainer : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Insets.radius),
            border: failed ? Border.all(color: colors.error) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sender != null) Text(sender, style: theme.textTheme.labelSmall),
              Text(message.body),
              const SizedBox(height: Insets.xs),
              Text(
                failed
                    ? l10n.chatsNotDelivered
                    : formatTime(message.createdAt, Localizations.localeOf(context).toString()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: failed ? colors.error : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
