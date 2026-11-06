import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/nav_badges.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'chat_labels.dart';
import 'chats_providers.dart';

/// Every DM sellix is handling, and the ones that need the merchant on top.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _search = TextEditingController();
  ChatFilter _filter = ChatFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pushBadges(ChatListData data) {
    final needYou = data.needYou;
    final live = data.sellixOn > 0;
    final badges = ref.read(navBadgesProvider);
    if (badges.chatsNeedYou == needYou && badges.chatsLive == live) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(navBadgesProvider.notifier).update(chatsNeedYou: needYou, chatsLive: live);
      }
    });
  }

  Future<void> _open(Conversation chat) async {
    await context.push(Routes.chat(chat.id));
    // Back from the thread: its question, order and agent switch may all have moved.
    if (mounted) await refreshChatList(ref);
  }

  @override
  Widget build(BuildContext context) {
    return SxScaffold(
      body: SxAsyncView<ChatListData>(
        value: ref.watch(chatListProvider),
        onRetry: () => refreshChatList(ref),
        loading: const SxSkeletonList(topHeight: 160),
        builder: (context, data) {
          _pushBadges(data);
          return _list(context, data);
        },
      ),
    );
  }

  Widget _list(BuildContext context, ChatListData data) {
    final p = context.sx;
    final rows = filterChats(data, _filter, _search.text);
    final searching = _search.text.trim().isNotEmpty;
    return SxScrollList(
      onRefresh: () => refreshChatList(ref),
      children: [
        const SizedBox(height: SxSpace.s12),
        const SxPageTitle(title: 'Chats'),
        if (data.conversations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s4, SxSpace.screen, 0),
            child: Row(
              spacing: 6,
              children: [
                const SxPulseDot(),
                Expanded(
                  child: Text(
                    'sellix is on ${data.sellixOn} of these ${data.conversations.length} chats',
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: SxSpace.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
          child: SxField(
            controller: _search,
            hint: 'Search name or message',
            trailing: Icon(TablerIcons.search, size: 20, color: p.textSecondary),
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: SxSpace.s12),
        SxFilterChips(
          children: [
            for (final filter in ChatFilter.values)
              SxFilterChip(
                label: filter.label,
                selected: filter == _filter,
                badge: filter == ChatFilter.needsYou && data.needYou > 0 ? data.needYou : null,
                onTap: () => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: SxSpace.s12),
        if (rows.isEmpty)
          SxEmptyState(
            icon: TablerIcons.message_off,
            title: searching ? 'No chats match' : 'Nothing here',
            body: searching
                ? 'Try a name or a word from the message.'
                : _filter == ChatFilter.all
                ? 'Chats show here when customers message you.'
                : 'Chats in this state show here.',
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.s8,
              children: [
                for (final (index, chat) in rows.indexed)
                  SxFadeUp(
                    key: ValueKey('${_filter.name}-${chat.id}'),
                    index: index,
                    child: _ChatRow(
                      chat: chat,
                      state: data.stateOf(chat),
                      onTap: () => _open(chat),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The prototype's `UI.chatRow`.
// BACKEND GAP: conversations have no language or unread count, so the row shows neither.
class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.state, required this.onTap});

  final Conversation chat;
  final ChatState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final time = chat.lastMessageAt;
    return SxCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: SxSpace.s12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SxSpace.s12,
        children: [
          SxCustomerAvatar(
            name: chat.customerHandle,
            needsYou: state == ChatState.needsYou,
            channel: channelBrand(chat.channel),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: SxSpace.s8,
                  children: [
                    Expanded(
                      child: Text(
                        chat.customerHandle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                      ),
                    ),
                    if (time != null)
                      Text(chatStamp(time), style: SxText.micro.copyWith(color: p.textSecondary)),
                  ],
                ),
                Text(
                  chatPreview(chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxText.caption.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: SxSpace.s8),
                chatStateChip(state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
