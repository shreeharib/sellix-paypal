import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../stock/stock_providers.dart';
import 'home_insights.dart';
import 'home_providers.dart';
import 'home_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String _greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(homeDataProvider);
    final read = ref.watch(notificationReadProvider);
    final data = value.value;
    if (data != null) pushNavBadges(context, ref, data);
    final container = ProviderScope.containerOf(context, listen: false);
    return SxScaffold(
      body: Column(
        children: [
          SxRootHeader(
            // BACKEND GAP: the API has the shop's name but no owner name to greet by.
            greeting: _greeting(DateTime.now()),
            shopName: data?.me.merchant.name ?? '',
            onAvatarTap: () => context.go(Routes.profile),
            onBellTap: () => context.push(Routes.notifications),
            unread: data != null && buildNotifications(data, read).any((row) => row.unread),
          ),
          Expanded(
            child: SxAsyncView<HomeData>(
              value: value,
              onRetry: () => invalidateHomeSources(container),
              loading: const SxSkeletonList(topHeight: 220),
              builder: (context, data) => _HomeBody(data: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final container = ProviderScope.containerOf(context, listen: false);
    final noticeOff = ref.watch(noticeOffProvider);
    final open = data.openQuestions;
    final toAct = data.ordersToAct;
    final topOrders = toAct.take(2).toList();
    final recent = [
      for (final order in data.orders)
        if (data.onToday(order.createdAt) && !topOrders.contains(order)) order,
    ].take(3).toList();
    final soldOut = data.soldOutRows;
    final showNotice =
        data.stockSet && soldOut.isNotEmpty && noticeOff != businessDateString(data.today.businessDate);
    final live = data.liveChats;
    return SxScrollList(
      onRefresh: () => refreshHome(container),
      children: [
        SxFadeUp(child: data.stockSet ? _Hero(data: data) : _StockAnchor(data: data)),
        HomeMargin(
          top: SxSpace.s12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              if (data.stockSet)
                // BACKEND GAP: Today has no "stock set at" time, so the row says only that it is set.
                SxRowCard(
                  icon: TablerIcons.package,
                  title: 'Stock set',
                  meta: '${data.stockLeft} left · ${soldOut.length} sold out',
                  onTap: () => context.go(Routes.stock),
                )
              else if (!data.newShop)
                ?_yesterdayCard(context),
              ?_setupCard(context),
            ],
          ),
        ),
        if (data.newShop)
          const HomeMargin(
            top: SxSpace.s12,
            child: SxFadeUp(
              child: SxCard(
                child: _TitleBody(
                  title: 'No chats or orders yet',
                  body: 'sellix starts answering when you set today’s stock.',
                ),
              ),
            ),
          )
        else ...[
          SxSectionHeader(
            title: 'Needs you',
            badge: open.length,
            link: 'See all',
            onLink: () => context.push(Routes.needs),
          ),
          HomeMargin(
            child: AnimatedSize(
              duration: SxMotion.base,
              curve: SxMotion.move,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: SxSpace.s8,
                children: [
                  for (final (i, q) in open.take(3).indexed)
                    SxFadeUp(
                      key: ValueKey(q.id),
                      index: i,
                      child: QuestionCard(question: q, data: data),
                    ),
                  if (open.isEmpty) const SxFadeUp(child: AllClearCard()),
                ],
              ),
            ),
          ),
          if (toAct.isNotEmpty) ...[
            SxSectionHeader(
              title: 'Orders to handle',
              badge: toAct.length,
              link: 'See all',
              onLink: () => context.go(Routes.orders),
            ),
            HomeMargin(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: SxSpace.s8,
                children: [for (final order in topOrders) HomeOrderRow(order: order, data: data)],
              ),
            ),
          ],
          if (showNotice) HomeMargin(top: SxSpace.s12, child: _SoldOutNotice(data: data, row: soldOut.first)),
          if (live.isNotEmpty) ...[
            SxSectionHeader(title: 'Live chats', link: 'See all', onLink: () => context.go(Routes.chats)),
            HomeMargin(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: SxSpace.s8,
                children: [for (final chat in live) HomeChatRow(chat: chat, data: data)],
              ),
            ),
          ],
          if (recent.isNotEmpty) ...[
            SxSectionHeader(title: 'Recent orders', link: 'See all', onLink: () => context.go(Routes.orders)),
            HomeMargin(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: SxSpace.s8,
                children: [for (final order in recent) HomeOrderRow(order: order, data: data)],
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// Yesterday's real sales on a morning with no stock yet. Hidden when there were none.
  Widget? _yesterdayCard(BuildContext context) {
    final today = data.today.businessDate;
    final yesterday = addDays(today, -1);
    if (!ordersReach(data.orders, yesterday)) return null;
    final totals = salesBetween(data.orders, yesterday, today);
    if (totals.isEmpty) return null;
    final currency = leadCurrency(totals, 'INR');
    final count = data.orders.where((o) {
      return isSale(o) && daysBetween(saleTime(o).toLocal(), yesterday) == 0;
    }).length;
    return SxFadeUp(
      child: SxRowCard(
        icon: TablerIcons.chart_line,
        title: 'Yesterday: ${money(totals[currency]!, currency)}',
        meta: '$count ${count == 1 ? 'order' : 'orders'}',
        onTap: () => context.push(Routes.insights),
      ),
    );
  }

  /// Setup steps left, in words. Five in all; three are done by the time you reach Home.
  Widget? _setupCard(BuildContext context) {
    final needsStock = data.newShop;
    final todo = [if (needsStock) 'set today’s stock', if (!data.whatsappConnected) 'add WhatsApp'];
    if (todo.isEmpty) return null;
    final done = 5 - todo.length;
    final p = context.sx;
    return SxFadeUp(
      child: SxRowCard(
        leading: needsStock
            ? const SxIconTile(icon: TablerIcons.package)
            : const SxIconTile(child: SxBrandIcon(SxBrand.whatsapp)),
        title: 'Finish setup: ${todo.join(' and ')}',
        metaWidget: Padding(
          padding: const EdgeInsets.only(top: SxSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SxSpace.s4,
            children: [
              SxMeter(fraction: done / 5),
              Text('$done of 5 done', style: SxText.micro.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        onTap: () => context.push(needsStock ? Routes.morning : Routes.channels),
      ),
    );
  }
}

class _TitleBody extends StatelessWidget {
  const _TitleBody({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: SxSpace.s4,
      children: [
        Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
        Text(body, style: SxText.caption.copyWith(color: p.textSecondary)),
      ],
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final today = data.today;
    final revenue = today.revenueMinorByCurrency;
    final fallback = today.stock.isNotEmpty ? today.stock.first.currency : 'INR';
    final currency = leadCurrency(revenue, fallback);
    final sales = revenue[currency] ?? 0;
    final others = [
      for (final entry in revenue.entries)
        if (entry.key != currency) money(entry.value, entry.key),
    ];
    final trend = homeTrend(data.orders, sales, currency, today.businessDate);
    final bars = hourlyBars(data.orders, currency, today.businessDate, DateTime.now());
    final hasCurve = bars.length >= 2 && bars.any((b) => b.minor > 0);
    return SxHeroCard(
      label: 'Today’s sales',
      value: money(sales, currency),
      valueWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxCountUp(
            value: sales,
            style: SxText.display.copyWith(color: p.onAnchor),
            format: (minor) => money(minor, currency),
          ),
          if (others.isNotEmpty)
            Text(
              'Plus ${others.join(', ')}',
              style: SxText.caption.copyWith(color: p.onAnchorSecondary),
            ),
        ],
      ),
      status: _AgentPill(data: data),
      channels: [SxBrand.instagram, if (data.whatsappConnected) SxBrand.whatsapp],
      change: trend?.text,
      changeUp: trend?.up ?? true,
      sparkline: hasCurve ? [for (final bar in bars) bar.minor] : null,
      stats: [
        SxHeroStat(value: '${today.ordersPaid}', label: 'Orders'),
        SxHeroStat(value: '${data.chatsToday}', label: 'Chats today'),
        SxHeroStat(value: '${data.openQuestions.length}', label: 'Need you', attention: data.openQuestions.isNotEmpty),
      ],
      onTap: () => context.push(Routes.insights),
    );
  }
}

/// Morning, stock not set: the anchor card that asks for it.
class _StockAnchor extends StatelessWidget {
  const _StockAnchor({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    void openMorning() => context.push(Routes.morning);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: SxAnchorCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: _AgentPill(data: data)),
                const SizedBox(width: SxSpace.s8),
                Text(formatDate(data.today.businessDate), style: SxText.micro.copyWith(color: p.onAnchorSecondary)),
              ],
            ),
            const SizedBox(height: 18),
            Text('What’s in stock today?', style: SxText.titleL.copyWith(color: p.onAnchor)),
            const SizedBox(height: SxSpace.s8),
            Text(
              'Say it in any language. sellix makes the list. Chats wait until you confirm.',
              style: SxText.caption.copyWith(color: p.onAnchorSecondary),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: SxWaveform(active: true, bars: 34)),
                const SizedBox(width: SxSpace.s12),
                SxIconButton(
                  icon: TablerIcons.microphone,
                  semanticLabel: 'Speak today’s stock',
                  onAnchor: true,
                  onTap: openMorning,
                ),
              ],
            ),
            const SizedBox(height: SxSpace.s16),
            Wrap(
              spacing: SxSpace.s8,
              runSpacing: SxSpace.s8,
              children: [
                // BACKEND GAP: no endpoint copies yesterday's stock list, so this stays off.
                if (!data.newShop)
                  const SxButton(
                    label: 'Same as yesterday',
                    icon: TablerIcons.copy,
                    kind: SxButtonKind.ghostAnchor,
                    onTap: null,
                  ),
                SxButton(
                  label: 'Type it',
                  icon: TablerIcons.keyboard,
                  kind: SxButtonKind.ghostAnchor,
                  onTap: openMorning,
                ),
              ],
            ),
            if (!data.newShop)
              Padding(
                padding: const EdgeInsets.only(top: SxSpace.s8),
                child: Text(
                  'Copying yesterday’s list isn’t ready yet.',
                  style: SxText.micro.copyWith(color: p.onAnchorSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Agent live": tap to pause or resume.
class _AgentPill extends ConsumerWidget {
  const _AgentPill({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SxLivePill(state: data.agentState, onTap: () => _agentSheet(context, data.agentState));
  }
}

Future<void> _setAgent(BuildContext context, bool enabled) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(sellixApiProvider).updateMerchant(agentEnabled: enabled);
  container.invalidate(todayProvider);
}

Future<void> _agentSheet(BuildContext context, SxAgentState state) async {
  final choice = await showSxSheet<String>(
    context,
    title: switch (state) {
      SxAgentState.live => 'Pause sellix?',
      SxAgentState.paused => 'sellix is paused',
      SxAgentState.waiting => 'sellix is waiting for stock',
    },
    subtitle: switch (state) {
      SxAgentState.live => 'Messages are still saved. Nobody replies until you turn sellix back on.',
      SxAgentState.paused => 'Messages are saved. Customers get no reply.',
      SxAgentState.waiting => 'Set today’s stock and sellix starts selling.',
    },
    builder: (sheet) {
      void pick(String value) => Navigator.of(sheet).pop(value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: switch (state) {
          SxAgentState.live => [
            // BACKEND GAP: `agent_enabled` is on or off, with no pause-until time.
            const SxChoiceCard(
              title: 'For 1 hour',
              subtitle: 'Timed pause isn’t ready yet',
              icon: TablerIcons.clock,
              onTap: null,
            ),
            const SxChoiceCard(
              title: 'Until tomorrow morning',
              subtitle: 'Timed pause isn’t ready yet',
              icon: TablerIcons.moon,
              onTap: null,
            ),
            SxChoiceCard(
              title: 'Until you turn it on',
              subtitle: 'You answer every chat yourself',
              icon: TablerIcons.player_pause,
              onTap: () => pick('pause'),
            ),
          ],
          SxAgentState.paused => [
            SxButton(
              label: 'Turn sellix on',
              icon: TablerIcons.player_play,
              fullWidth: true,
              onTap: () => pick('resume'),
            ),
          ],
          SxAgentState.waiting => [
            SxButton(
              label: 'Set today’s stock',
              icon: TablerIcons.microphone,
              fullWidth: true,
              onTap: () => pick('stock'),
            ),
          ],
        },
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'stock') {
    await context.push(Routes.morning);
    return;
  }
  final pausing = choice == 'pause';
  try {
    await _setAgent(context, !pausing);
  } catch (error) {
    if (context.mounted) showSxSnack(context, sxErrorMessage(error));
    return;
  }
  if (!context.mounted) return;
  if (pausing) {
    showSxSnack(
      context,
      'sellix is paused. Messages are saved.',
      icon: TablerIcons.player_pause,
      action: 'Undo',
      onAction: () async {
        if (!context.mounted) return;
        try {
          await _setAgent(context, true);
        } catch (error) {
          if (context.mounted) showSxSnack(context, sxErrorMessage(error));
        }
      },
    );
  } else {
    showSxSnack(context, 'sellix is live again.', icon: TablerIcons.check);
  }
}

/// "sellix noticed". Only what we can show is true: the item sold out.
// BACKEND GAP: no sold-out time or count of people who asked after it, and no way to DM them.
class _SoldOutNotice extends ConsumerStatefulWidget {
  const _SoldOutNotice({required this.data, required this.row});

  final HomeData data;
  final StockRow row;

  @override
  ConsumerState<_SoldOutNotice> createState() => _SoldOutNoticeState();
}

class _SoldOutNoticeState extends ConsumerState<_SoldOutNotice> {
  static const _batch = 6;
  var _busy = false;

  Future<void> _restock() async {
    final label = widget.row.label;
    // BACKEND GAP: restock can't be reversed, so this asks first instead of the prototype's Undo.
    final sure = await showSxConfirm(
      context,
      title: 'Add $_batch more?',
      body: '$label goes back on sale right away.',
      confirmLabel: 'Add $_batch more',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(sellixApiProvider).restock(widget.row.variantId, _batch);
      container.invalidate(todayProvider);
      if (mounted) showSxSnack(context, '$_batch $label added.', icon: TablerIcons.check);
    } catch (error) {
      if (mounted) showSxSnack(context, sxErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxFadeUp(
      child: SxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(TablerIcons.bulb, size: 20, color: p.textPrimary),
                const SizedBox(width: SxSpace.s8),
                Text('sellix noticed', style: SxText.label.copyWith(color: p.textPrimary)),
              ],
            ),
            const SizedBox(height: SxSpace.s8),
            Text('${widget.row.label} sold out today.', style: SxText.bodyS.copyWith(color: p.textPrimary)),
            const SizedBox(height: SxSpace.s12),
            SxButtonRow(
              children: [
                SxButton(
                  label: 'Not now',
                  kind: SxButtonKind.secondary,
                  onTap: () =>
                      ref.read(noticeOffProvider.notifier).turnOff(widget.data.today.businessDate),
                ),
                SxButton(label: 'Add $_batch more', loading: _busy, onTap: _busy ? null : _restock),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
