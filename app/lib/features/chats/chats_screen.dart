import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';

final conversationsProvider = FutureProvider.autoDispose<List<Conversation>>(
  (ref) => ref.watch(sellixApiProvider).conversations(),
);

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final chats = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navChats)),
      body: AsyncView(
        value: chats,
        onRetry: () => ref.invalidate(conversationsProvider),
        data: (items) => items.isEmpty
            ? MessageView(
                icon: Icons.forum_outlined,
                title: l10n.chatsEmpty,
                body: l10n.chatsEmptyHint,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(conversationsProvider.future),
                child: ContentWidth(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) => _ChatTile(chat: items[index]),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat});

  final Conversation chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final handle = chat.customerHandle;
    return ListTile(
      onTap: () => context.go(Routes.chat(chat.id)),
      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.xs),
      leading: CircleAvatar(child: Text(handle.isEmpty ? '?' : handle.characters.first.toUpperCase())),
      title: Text(handle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(chat.lastMessageBody ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (chat.lastMessageAt != null)
            Text(formatTime(chat.lastMessageAt!, locale), style: theme.textTheme.bodySmall),
          if (!chat.agentActive)
            Padding(
              padding: const EdgeInsets.only(top: Insets.xs),
              child: Text(
                context.l10n.chatsAgentPaused,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary),
              ),
            ),
        ],
      ),
    );
  }
}
