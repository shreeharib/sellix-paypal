import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'home_providers.dart';

/// One list of everything sellix told you today.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final container = ProviderScope.containerOf(context, listen: false);
    final value = ref.watch(homeDataProvider);
    final read = ref.watch(notificationReadProvider);
    final data = value.value;
    if (data != null) pushNavBadges(context, ref, data);
    final rows = data == null ? const <NotificationRow>[] : buildNotifications(data, read);
    final unread = rows.where((row) => row.unread).toList();
    return SxScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxDetailHeader(
            title: 'Notifications',
            fallback: Routes.home,
            trailing: unread.isEmpty
                ? null
                : SxLinkButton(
                    label: 'Mark all read',
                    onTap: () =>
                        ref.read(notificationReadProvider.notifier).markRead(unread.map((row) => row.key)),
                  ),
          ),
          Expanded(
            child: SxAsyncView(
              value: value,
              onRetry: () => invalidateHomeSources(container),
              isEmpty: (_) => rows.isEmpty,
              empty: const SxEmptyState(
                icon: TablerIcons.bell,
                title: 'Nothing yet',
                body: 'New questions and orders show here.',
              ),
              builder: (context, _) => _List(rows: rows, isToday: data!.onToday),
            ),
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.rows, required this.isToday});

  final List<NotificationRow> rows;
  final bool Function(DateTime) isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final container = ProviderScope.containerOf(context, listen: false);
    // Rows with no time of their own (stock) belong to today.
    final today = rows.where((r) => r.time == null || isToday(r.time!)).toList();
    final earlier = rows.where((r) => r.time != null && !isToday(r.time!)).toList();
    Widget section(String label, List<NotificationRow> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen, vertical: SxSpace.s8),
          child: Text(label, style: SxText.micro.copyWith(color: p.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
          child: SxFadeUp(child: SxGroup(children: [for (final row in list) _Row(row: row)])),
        ),
      ],
    );
    return SxScrollList(
      bottomInset: false,
      onRefresh: () => refreshHome(container),
      children: [
        if (today.isNotEmpty) section('Today', today),
        if (earlier.isNotEmpty) section('Earlier', earlier),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.row});

  final NotificationRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final (tile, icon) = switch (row.tone) {
      NotificationTone.attention => (p.attentionSoft, p.attentionText),
      NotificationTone.positive => (p.successSoft, p.successText),
      NotificationTone.neutral => (null, null),
    };
    final time = row.time;
    return SxPressable(
      onTap: () {
        ref.read(notificationReadProvider.notifier).markRead([row.key]);
        if (row.isTab) {
          context.go(row.route);
        } else {
          context.push(row.route);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SxSpace.s16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SxIconTile(icon: row.icon, background: tile, foreground: icon),
            const SizedBox(width: SxSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                  Text(row.body, style: SxText.caption.copyWith(color: p.textSecondary)),
                  if (time != null)
                    Padding(
                      padding: const EdgeInsets.only(top: SxSpace.s4),
                      child: Text(relativeTime(time), style: SxText.micro.copyWith(color: p.textSecondary)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: SxSpace.s12),
            SizedBox(
              width: 8,
              child: row.unread
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Semantics(
                        label: 'Unread',
                        child: SxPulseDot(size: 8, color: p.attention, pulse: false),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
