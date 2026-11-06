import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import 'settings_providers.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  bool _reconnecting = false;

  /// The only Instagram flow the app has is sign-in. The backend treats the same Instagram account as
  /// the same shop and renews its connection. A different account signs in to that account's shop, so
  /// this checks who came back rather than assuming.
  Future<void> _reconnect(String merchantId) async {
    setState(() => _reconnecting = true);
    String? message;
    try {
      await ref.read(authControllerProvider.notifier).signInWithInstagram();
      final me = await ref.refresh(meProvider.future);
      ref.invalidate(conversationsProvider);
      if (me.merchant.id != merchantId) {
        message = 'That Instagram account belongs to another shop. You are now in ${me.merchant.name}.';
      } else if (channelWorks(channelOf(me.channels, 'instagram'))) {
        message = 'Instagram is back.';
      } else {
        message = 'Instagram did not reconnect. Please try again.';
      }
    } on SignInCancelled {
      message = 'Reconnect cancelled. Instagram is still disconnected.';
    } on ApiException catch (error) {
      message = sxErrorMessage(error);
    } catch (_) {
      message = 'Instagram did not reconnect. Please try again.';
    }
    if (!mounted) return;
    setState(() => _reconnecting = false);
    showSxSnack(context, message, icon: TablerIcons.plug_connected);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final data = me.value;
    final instagram = data == null ? null : channelOf(data.channels, 'instagram');
    final broken = data != null && !channelWorks(instagram);
    return SxScaffold(
      floating: broken
          ? SxBottomCta(
              label: _reconnecting
                  ? 'Reconnecting…'
                  : (instagram == null ? 'Connect Instagram' : 'Reconnect Instagram'),
              icon: TablerIcons.refresh,
              loading: _reconnecting,
              onTap: () => _reconnect(data.merchant.id),
            )
          : null,
      body: Column(
        children: [
          const SxDetailHeader(title: 'Channels', meta: 'Where sellix answers', fallback: Routes.profile),
          Expanded(
            child: SxAsyncView<Me>(
              value: me,
              onRetry: () => ref
                ..invalidate(conversationsProvider)
                ..invalidate(meProvider),
              loading: const SxSkeletonList(count: 3, itemHeight: 120),
              builder: (context, me) => _list(me),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(Me me) {
    final instagram = channelOf(me.channels, 'instagram');
    final whatsapp = channelOf(me.channels, 'whatsapp');
    final works = channelWorks(instagram);
    return SxScrollList(
      onRefresh: () async {
        ref
          ..invalidate(conversationsProvider)
          ..invalidate(meProvider);
        await ref.read(meProvider.future);
      },
      children: [
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              if (!works && instagram != null)
                SxFadeUp(
                  child: const SxBanner(
                    tone: SxBannerTone.error,
                    icon: TablerIcons.plug_connected_x,
                    message: 'Instagram disconnected. sellix cannot read or answer DMs. Reconnect to fix it.',
                  ),
                ),
              SxFadeUp(child: _InstagramCard(channel: instagram)),
              SxFadeUp(index: 1, child: _WhatsAppCard(channel: whatsapp)),
              SxFadeUp(
                index: 2,
                child: SxCard(
                  child: Row(
                    spacing: SxSpace.s12,
                    children: [
                      const SxIconTile(child: SxBrandIcon(SxBrand.messenger)),
                      Expanded(child: _Titles(title: 'Facebook Messenger', subtitle: 'Later')),
                      const SxChip(label: 'Soon'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SxSpace.s4),
              SxFadeUp(
                index: 3,
                child: const SxAiNote('I only answer people who message you first. I never post or run ads.'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
        Text(subtitle, style: SxText.caption.copyWith(color: p.textSecondary)),
      ],
    );
  }
}

class _InstagramCard extends ConsumerWidget {
  const _InstagramCard({required this.channel});

  final Channel? channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final c = channel;
    final works = channelWorks(c);
    final conversations = ref.watch(conversationsProvider).value;
    DateTime? last;
    for (final chat in conversations ?? const <Conversation>[]) {
      final at = chat.lastMessageAt;
      if (chat.channel == 'instagram' && at != null && (last == null || at.isAfter(last))) last = at;
    }
    final subtitle = c == null ? 'Not connected' : '${c.username == null ? 'Instagram' : '@${c.username}'} · Business';
    return Container(
      padding: const EdgeInsets.all(SxSpace.card),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(SxRadius.card),
        border: c != null && !works ? Border.all(color: p.error, width: 1.5) : null,
      ),
      child: Column(
        children: [
          Row(
            spacing: SxSpace.s12,
            children: [
              const SxIconTile(child: SxBrandIcon(SxBrand.instagram)),
              Expanded(child: _Titles(title: 'Instagram', subtitle: subtitle)),
              if (works)
                const SxChip(label: 'Connected', tone: SxChipTone.positive, icon: TablerIcons.check)
              else
                const SxChip(label: 'Disconnected', tone: SxChipTone.error, icon: TablerIcons.alert_circle),
            ],
          ),
          if (c != null) ...[
            const SizedBox(height: SxSpace.s12),
            Divider(height: 1, thickness: 1, color: p.line),
            // BACKEND GAP: no per-channel message count, so the prototype's "Messages today" row is gone.
            SxKeyValue(
              label: 'Last message',
              value: last == null ? '—' : relativeTime(last.toLocal()),
            ),
            SxKeyValue(
              label: 'Access',
              divider: true,
              value: works ? 'Renews by itself' : (c.status == 'revoked' ? 'Removed' : 'Expired'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WhatsAppCard extends StatelessWidget {
  const _WhatsAppCard({required this.channel});

  final Channel? channel;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    final works = channelWorks(c);
    return SxCard(
      child: Row(
        spacing: SxSpace.s12,
        children: [
          const SxIconTile(child: SxBrandIcon(SxBrand.whatsapp)),
          Expanded(
            child: _Titles(
              title: 'WhatsApp Business',
              subtitle: works ? (c?.username ?? 'Connected') : 'Connecting WhatsApp is not available yet',
            ),
          ),
          if (works)
            const SxChip(label: 'Connected', tone: SxChipTone.positive, icon: TablerIcons.check)
          else
            // BACKEND GAP: no endpoint to connect WhatsApp, so the prototype's sheet would pretend.
            const SxButton(label: 'Connect', onTap: null),
        ],
      ),
    );
  }
}
