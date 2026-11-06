import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import '../orders/orders_providers.dart';
import '../stock/stock_providers.dart';
import 'home_insights.dart';
import 'home_providers.dart';
import 'home_widgets.dart';

class InsightsData {
  const InsightsData({
    required this.today,
    required this.orders,
    required this.conversations,
    required this.questions,
    required this.shopName,
  });

  final Today today;
  final List<Order> orders;
  final List<Conversation> conversations;

  /// Open, answered and closed, up to the backend's 100 of each.
  final List<Question> questions;
  final String shopName;
}

final insightsDataProvider = FutureProvider.autoDispose<InsightsData>((ref) async {
  final today = ref.watch(todayProvider.future);
  final orders = ref.watch(ordersProvider.future);
  final chats = ref.watch(conversationsProvider.future);
  final open = ref.watch(openQuestionsProvider.future);
  final answered = ref.watch(answeredQuestionsProvider.future);
  final closed = ref.watch(closedQuestionsProvider.future);
  final me = ref.watch(homeMeProvider.future);
  final loaded = await Future.wait<Object>([today, orders, chats, open, answered, closed, me]);
  return InsightsData(
    today: loaded[0] as Today,
    orders: loaded[1] as List<Order>,
    conversations: loaded[2] as List<Conversation>,
    questions: [
      ...loaded[3] as List<Question>,
      ...loaded[4] as List<Question>,
      ...loaded[5] as List<Question>,
    ],
    shopName: (loaded[6] as Me).merchant.name,
  );
});

void _invalidateAll(ProviderContainer container) {
  container
    ..invalidate(todayProvider)
    ..invalidate(ordersProvider)
    ..invalidate(conversationsProvider)
    ..invalidate(openQuestionsProvider)
    ..invalidate(answeredQuestionsProvider)
    ..invalidate(closedQuestionsProvider)
    ..invalidate(homeMeProvider);
}

/// Sales insights.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  var _period = InsightPeriod.week;
  var _tipOff = false;

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final value = ref.watch(insightsDataProvider);
    return SxScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxDetailHeader(title: 'Sales', meta: value.value?.shopName, fallback: Routes.home),
          Expanded(
            child: SxAsyncView<InsightsData>(
              value: value,
              onRetry: () => _invalidateAll(container),
              loading: const SxSkeletonList(topHeight: 200),
              isEmpty: (data) => data.orders.isEmpty,
              empty: const SxEmptyState(
                icon: TablerIcons.chart_bar,
                title: 'No sales yet',
                body: 'Your sales show here once customers order.',
              ),
              builder: (context, data) => _body(context, container, data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ProviderContainer container, InsightsData data) {
    final report = computeInsights(
      period: _period,
      orders: data.orders,
      conversations: data.conversations,
      questions: data.questions,
      businessDate: data.today.businessDate,
      now: DateTime.now(),
    );
    final soldOut = [
      for (final row in data.today.stock)
        if (row.isTracked && row.made > 0 && row.available == 0) row,
    ];
    final periodWord = switch (_period) {
      InsightPeriod.today => 'Today',
      InsightPeriod.week => 'This week',
      InsightPeriod.month => 'This month',
    };
    return SxScrollList(
      bottomInset: false,
      onRefresh: () async {
        _invalidateAll(container);
        try {
          await container.read(insightsDataProvider.future);
        } on Object {
          // SxAsyncView reports a failed reload.
        }
      },
      children: [
        HomeMargin(
          child: SxSegmented<InsightPeriod>(
            segments: const [
              SxSegment(InsightPeriod.today, 'Today'),
              SxSegment(InsightPeriod.week, 'This week'),
              SxSegment(InsightPeriod.month, 'This month'),
            ],
            value: _period,
            onChanged: (period) => setState(() => _period = period),
          ),
        ),
        const SizedBox(height: SxSpace.s12),
        _hero(report, periodWord),
        if (report.windowCutsPeriod)
          HomeMargin(
            top: SxSpace.s12,
            child: SxBanner(
              tone: SxBannerTone.neutral,
              message: 'Counted from your latest $ordersWindow orders. Older ones in this period aren’t included.',
            ),
          ),
        HomeMargin(top: SxSpace.s12, child: _BarsCard(key: ValueKey(_period), report: report)),
        if (soldOut.isNotEmpty && !_tipOff) ...[
          const SxSectionHeader(title: 'What to stock tomorrow'),
          HomeMargin(child: _tip(context, soldOut)),
        ],
        const SxSectionHeader(title: 'Best sellers'),
        HomeMargin(child: _bestSellers(report)),
        const SxSectionHeader(title: 'Missed sales'),
        // BACKEND GAP: requests after a sell-out or before stock was set aren't counted anywhere.
        const HomeMargin(
          child: SxCard(child: _Muted('Not tracked yet. sellix doesn’t count these requests so far.')),
        ),
        const SxSectionHeader(title: 'Busy hours'),
        HomeMargin(child: _busy(report)),
        const SxSectionHeader(title: 'From chat to paid'),
        HomeMargin(child: _funnel(report)),
        const SxSectionHeader(title: 'Channels and customers'),
        HomeMargin(child: _channels(report)),
        SxSectionHeader(title: 'sellix ${periodWord.toLowerCase()}'),
        HomeMargin(child: _sellix(report)),
      ],
    );
  }

  Widget _hero(InsightReport report, String label) {
    final average = report.averageMinor;
    final alone = report.handledAlonePercent;
    return SxHeroCard(
      label: label,
      value: money(report.totalMinor, report.currency),
      valueWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) => SxCountUp(
              value: report.totalMinor,
              duration: const Duration(milliseconds: 500),
              style: SxText.display.copyWith(color: context.sx.onAnchor),
              format: (minor) => money(minor, report.currency),
            ),
          ),
          if (report.otherTotals.isNotEmpty)
            Builder(
              builder: (context) => Text(
                'Plus ${[for (final e in report.otherTotals.entries) money(e.value, e.key)].join(', ')}',
                style: SxText.caption.copyWith(color: context.sx.onAnchorSecondary),
              ),
            ),
        ],
      ),
      change: report.trend?.text,
      changeUp: report.trend?.up ?? true,
      stats: [
        SxHeroStat(value: '${report.orderCount}', label: 'Orders'),
        SxHeroStat(value: average == null ? '–' : money(average, report.currency), label: 'Avg order'),
        SxHeroStat(value: alone == null ? '–' : '$alone%', label: 'sellix alone'),
      ],
    );
  }

  Widget _tip(BuildContext context, List<StockRow> soldOut) {
    final first = soldOut.first;
    final more = soldOut.length > 1 ? ' ${soldOut.length - 1} more sold out too.' : '';
    // BACKEND GAP: no daily closing report or recommendation, so this states what happened today
    // and opens Stock instead of the prototype's suggested quantity and "Use for tomorrow".
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          SxAiNote('${first.label} sold out today after ${first.made}.$more Think about making more tomorrow.'),
          SxButtonRow(
            children: [
              SxButton(
                label: 'Not now',
                kind: SxButtonKind.secondary,
                onTap: () => setState(() => _tipOff = true),
              ),
              SxButton(label: 'Open stock', onTap: () => context.go(Routes.stock)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bestSellers(InsightReport report) {
    if (report.bestSellers.isEmpty) {
      return const SxCard(child: _Muted('No paid orders in this period.'));
    }
    final top = report.bestSellers.first.quantity;
    return SxCard(
      child: Column(
        spacing: SxSpace.s12,
        children: [
          for (final item in report.bestSellers)
            _MeterRow(
              leading: const SxIconTile(icon: TablerIcons.package, size: 36),
              title: item.label,
              value: '${item.quantity}',
              fraction: item.quantity / top,
            ),
        ],
      ),
    );
  }

  Widget _busy(InsightReport report) {
    final top = report.busyHours.fold(0, (a, b) => a > b ? a : b);
    return Builder(
      builder: (context) {
        final p = context.sx;
        return SxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 3,
                children: [
                  for (final count in report.busyHours)
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: count == 0
                                ? p.tile
                                : p.primary.withValues(alpha: 0.15 + 0.85 * count / top),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: SxSpace.s8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in const ['9 AM', '2 PM', '8 PM'])
                    Text(label, style: SxText.micro.copyWith(color: p.textSecondary)),
                ],
              ),
              if (report.peakNote != null) ...[
                const SizedBox(height: SxSpace.s12),
                SxAiNote(report.peakNote!),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _funnel(InsightReport report) {
    // BACKEND GAP: no funnel events. "Chats" counts chats whose latest message is in the period,
    // and the prototype's "Asked about a product" can't be told from any other chat.
    final steps = [
      ('Chats', report.chats),
      ('Confirmed an order', report.placed),
      ('Paid', report.orderCount),
    ];
    final top = steps.map((s) => s.$2).fold(0, (a, b) => a > b ? a : b);
    return SxCard(
      child: Column(
        spacing: 6,
        children: [
          for (final (label, count) in steps)
            _FunnelBar(label: label, count: count, fraction: top == 0 ? 0 : count / top),
        ],
      ),
    );
  }

  Widget _channels(InsightReport report) {
    final repeat = report.repeatPercent;
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          if (report.channels.isEmpty) const _Muted('No orders in this period.'),
          for (final share in report.channels)
            _MeterRow(
              leading: _channelTile(share.channel),
              title: channelName(share.channel),
              value: '${share.percent}%',
              fraction: share.percent / 100,
            ),
          // BACKEND GAP: no customer language on conversations, so "Top language" is left out.
          if (repeat != null) _Stat(value: '$repeat%', label: 'Repeat customers'),
        ],
      ),
    );
  }

  Widget _channelTile(String channel) {
    final brand = brandOfChannel(channel);
    return SxIconTile(
      size: 36,
      icon: TablerIcons.message_circle,
      child: brand == null ? null : SxBrandIcon(brand),
    );
  }

  Widget _sellix(InsightReport report) {
    final alone = report.handledAlonePercent;
    final answer = report.answerTime;
    return SxGroup(
      children: [
        SxListRow(
          icon: TablerIcons.sparkles,
          title: 'Handled alone',
          value: alone == null ? '–' : '$alone%',
        ),
        SxListRow(
          icon: TablerIcons.clock,
          title: 'Your answer time',
          value: answer == null ? '–' : shortDuration(answer),
        ),
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: SxText.bodyS.copyWith(color: context.sx.textSecondary));
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: SxText.stat.copyWith(color: p.textPrimary)),
        Text(label, style: SxText.micro.copyWith(color: p.textSecondary)),
      ],
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.leading, required this.title, required this.value, required this.fraction});

  final Widget leading;
  final String title;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Row(
      children: [
        leading,
        const SizedBox(width: SxSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s4,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                    ),
                  ),
                  Text(value, style: SxText.label.copyWith(color: p.textPrimary)),
                ],
              ),
              SxMeter(fraction: fraction),
            ],
          ),
        ),
      ],
    );
  }
}

class _FunnelBar extends StatelessWidget {
  const _FunnelBar({required this.label, required this.count, required this.fraction});

  final String label;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final style = SxText.label.copyWith(color: p.textPrimary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(SxSpace.s12),
      child: Container(
        height: 40,
        color: p.tile,
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: p.primary.withValues(alpha: 0.14)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SxSpace.s12),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: style)),
                  Text('$count', style: style),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bars with a value that follows the tapped bar.
class _BarsCard extends StatefulWidget {
  const _BarsCard({super.key, required this.report});

  final InsightReport report;

  @override
  State<_BarsCard> createState() => _BarsCardState();
}

class _BarsCardState extends State<_BarsCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final report = widget.report;
    final bars = report.bars;
    final on = _selected ?? bars.length - 1;
    final top = bars.fold(0, (a, b) => a > b.minor ? a : b.minor);
    final title = switch (report.period) {
      InsightPeriod.today => 'By hour',
      InsightPeriod.week => 'By day',
      InsightPeriod.month => 'By week',
    };
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
              Text(
                '${bars[on].label}: ${money(bars[on].minor, report.currency)}',
                style: SxText.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: SxSpace.s16),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: SxSpace.s8,
              children: [
                for (final (i, bar) in bars.indexed)
                  Expanded(
                    child: SxPressable(
                      small: true,
                      semanticLabel: '${bar.label}: ${money(bar.minor, report.currency)}',
                      onTap: () => setState(() => _selected = i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: top == 0 ? 0.04 : (bar.minor / top).clamp(0.04, 1.0)),
                                duration: const Duration(milliseconds: 500),
                                curve: SxMotion.curve,
                                builder: (_, height, _) => FractionallySizedBox(
                                  heightFactor: height,
                                  widthFactor: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: i == on ? p.primary : p.tile,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(10),
                                        bottom: Radius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bar.label,
                            maxLines: 1,
                            style: SxText.micro.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
