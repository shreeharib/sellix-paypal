import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'coming_days.dart';
import 'stock_actions.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

enum _Tab { today, coming, catalogue }

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  _Tab _tab = _Tab.today;
  String? _open;

  Future<void> _reload() async {
    ref.invalidate(leftoversProvider);
    ref.invalidate(upcomingProvider);
    ref.invalidate(todayProvider);
    ref.invalidate(catalogProvider);
    await ref.read(stockViewProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final addProduct = SxIconButton(
      icon: TablerIcons.plus,
      semanticLabel: 'Add product',
      onTap: () => context.push(Routes.addproduct),
    );
    return SxScaffold(
      body: SxAsyncView<StockView>(
        value: ref.watch(stockViewProvider),
        onRetry: _reload,
        loading: const SxSkeletonList(topHeight: 200),
        builder: (context, view) => SxScrollList(
          onRefresh: _reload,
          children: [
            const SizedBox(height: SxSpace.s12),
            SxPageTitle(
              title: 'Stock',
              subtitle: DateFormat('EEEE, d MMMM').format(view.today.businessDate),
              trailing: addProduct,
            ),
            if (view.items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s16, SxSpace.screen, 0),
                child: SxEmptyState(
                  icon: TablerIcons.package,
                  title: 'Add your first product',
                  body: 'A name, a price and how long you can sell it. It takes a minute.',
                  actionLabel: 'Add product',
                  onAction: () => context.push(Routes.addproduct),
                ),
              )
            else ...[
              const SizedBox(height: SxSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
                child: _Summary(view: view),
              ),
              const SizedBox(height: SxSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
                child: SxSegmented<_Tab>(
                  segments: const [
                    SxSegment(_Tab.today, 'Today'),
                    SxSegment(_Tab.coming, 'Coming days'),
                    SxSegment(_Tab.catalogue, 'Catalogue'),
                  ],
                  value: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ),
              const SizedBox(height: SxSpace.s12),
              switch (_tab) {
                _Tab.today => _TodayList(
                  view: view,
                  open: _open,
                  onToggle: (id) => setState(() => _open = _open == id ? null : id),
                ),
                _Tab.coming => ComingDays(view: view),
                _Tab.catalogue => _Catalogue(view: view),
              },
            ],
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.view});

  final StockView view;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final live = view.live.toList();
    final agent = view.today.agentEnabled ? SxAgentState.live : SxAgentState.paused;
    if (live.isEmpty) {
      return SxAnchorCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SxLivePill(state: view.today.agentEnabled ? SxAgentState.waiting : SxAgentState.paused),
            const SizedBox(height: SxSpace.s16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set today’s stock', style: SxText.titleM.copyWith(color: p.onAnchor)),
                      const SizedBox(height: SxSpace.s4),
                      Text(
                        'sellix sells only what you put on today’s list.',
                        style: SxText.caption.copyWith(color: p.onAnchorSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SxSpace.s12),
                SxIconButton(
                  icon: TablerIcons.pencil,
                  semanticLabel: 'Set today’s stock',
                  onAnchor: true,
                  onTap: () => context.push(Routes.morning),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final tracked = view.tracked.toList();
    final sold = tracked.fold(0, (a, i) => a + i.soldTotal);
    final held = live.fold(0, (a, i) => a + i.held);
    final made = live.fold(0, (a, i) => a + i.made);
    final left = live.fold(0, (a, i) => a + i.available);
    final soldOut = live.where((i) => i.available == 0).length;
    final meter = made > sold + held ? made : sold + held;
    Widget dot(Color c) => Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.only(right: SxSpace.s4),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    final micro = SxText.micro.copyWith(color: p.onAnchorSecondary);
    return SxAnchorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BACKEND GAP: the ledger has no timestamp, so the prototype's "Set at 8:10 AM" is dropped.
          SxLivePill(state: agent),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SxCountUp(value: left, style: SxText.display.copyWith(color: p.onAnchor)),
              const SizedBox(width: SxSpace.s8),
              Expanded(
                child: Text(
                  'pieces left of $made',
                  style: SxText.bodyS.copyWith(color: p.onAnchorSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: SxSpace.s12),
          ClipRRect(
            borderRadius: BorderRadius.circular(SxRadius.pill),
            child: Container(
              height: 6,
              color: p.anchorLine,
              child: LayoutBuilder(
                builder: (_, box) => Row(
                  children: [
                    Container(width: meter == 0 ? 0 : box.maxWidth * sold / meter, color: p.onAnchor),
                    Container(width: meter == 0 ? 0 : box.maxWidth * held / meter, color: p.onAnchorSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: SxSpace.s8),
          Wrap(
            spacing: SxSpace.s16,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [dot(p.onAnchor), Text('Sold $sold', style: micro)]),
              Row(mainAxisSize: MainAxisSize.min, children: [dot(p.onAnchorSecondary), Text('On hold $held', style: micro)]),
              Text('$soldOut sold out', style: micro),
            ],
          ),
          const SizedBox(height: SxSpace.s16),
          Divider(height: 1, color: p.anchorLine),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tell sellix a change', style: SxText.label.copyWith(color: p.onAnchor)),
                    Text(
                      'Voice isn’t ready yet. Use the buttons on each item.',
                      style: SxText.caption.copyWith(color: p.onAnchorSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SxSpace.s12),
              // BACKEND GAP: no voice transcription, and no endpoint parses a spoken stock change.
              const SxIconButton(
                icon: TablerIcons.microphone_off,
                semanticLabel: 'Voice is not available yet',
                onAnchor: true,
                onTap: null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({required this.view, required this.open, required this.onToggle});

  final StockView view;
  final String? open;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final live = view.live.toList()
      ..sort((a, b) => (a.available == 0 ? 1 : 0) - (b.available == 0 ? 1 : 0));
    final noCount = view.noCount.toList();
    final carried = ProviderScope.containerOf(context, listen: false)
        .read(carriedLogProvider)
        .read(view.today.businessDate);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LeftoversRow(),
          for (final (i, item) in live.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: SxSpace.listGap),
              child: SxFadeUp(
                index: i,
                child: _StockRowCard(
                  item: item,
                  carried: carried[item.variantId] ?? 0,
                  open: open == item.variantId,
                  onToggle: () => onToggle(item.variantId),
                ),
              ),
            ),
          if (noCount.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: SxSpace.s8, bottom: SxSpace.s8),
              child: Text('No count needed', style: SxText.label.copyWith(color: p.textPrimary)),
            ),
            for (final item in noCount)
              Padding(
                padding: const EdgeInsets.only(bottom: SxSpace.listGap),
                child: SxRowCard(
                  title: item.label,
                  meta: '${item.priceLabel} · ${item.shelf}\n${noCountWhy(item.stockMode)}',
                  leading: const SxIconTile(icon: TablerIcons.package),
                  onTap: () => context.push(Routes.product(item.variantId)),
                ),
              ),
          ],
          SxRowCard(
            title: 'Redo today’s list',
            meta: 'Type or set the full stock again',
            icon: TablerIcons.refresh,
            outlined: true,
            onTap: () => context.push(Routes.morning),
          ),
        ],
      ),
    );
  }
}

class _StockRowCard extends StatelessWidget {
  const _StockRowCard({
    required this.item,
    required this.carried,
    required this.open,
    required this.onToggle,
  });

  final StockItem item;
  final int carried;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final left = item.available;
    final carryLine = carried > 0
        ? '$carried from yesterday. ${item.shelf}.'
        : ShelfChoice.of(item.stockMode, item.shelfLifeDays).line;
    return Container(
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxPressable(
            semanticLabel: '${item.label}, ${left > 0 ? '$left left' : 'sold out'}. Show actions',
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SxIconTile(icon: left > 0 ? TablerIcons.package : TablerIcons.package_off),
                  const SizedBox(width: SxSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                        ),
                        Text(
                          '${money(item.priceMinor, item.currency)} · ${item.shelf}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxText.caption.copyWith(color: p.textSecondary),
                        ),
                        Text(
                          'Stock ${item.made} · Sold ${item.soldTotal}'
                          '${item.held > 0 ? ' · On hold ${item.held}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxText.caption.copyWith(color: p.textSecondary),
                        ),
                        const SizedBox(height: SxSpace.s8),
                        LedgerBar(item: item),
                      ],
                    ),
                  ),
                  const SizedBox(width: SxSpace.s12),
                  if (left > 0)
                    Column(
                      children: [
                        Text('$left', style: SxText.counter.copyWith(color: p.textPrimary)),
                        Text('left', style: SxText.micro.copyWith(color: p.textSecondary)),
                      ],
                    )
                  else
                    const SxChip(label: 'Sold out', icon: TablerIcons.ban),
                  const SizedBox(width: SxSpace.s4),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: SxMotion.base,
                    child: Icon(TablerIcons.chevron_down, size: 18, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: SxMotion.base,
            curve: SxMotion.curve,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(TablerIcons.hourglass, size: 16, color: p.textSecondary),
                            const SizedBox(width: SxSpace.s8),
                            Expanded(
                              child: Text(carryLine, style: SxText.caption.copyWith(color: p.textSecondary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: SxSpace.s12),
                        Wrap(
                          spacing: SxSpace.s8,
                          runSpacing: SxSpace.s8,
                          children: [
                            SxButton(
                              label: 'Add stock',
                              kind: SxButtonKind.secondary,
                              icon: TablerIcons.plus,
                              onTap: () => StockActions(context).restock(context, item),
                            ),
                            if (left > 0)
                              SxButton(
                                label: 'Sold at shop',
                                kind: SxButtonKind.secondary,
                                icon: TablerIcons.building_store,
                                onTap: () => StockActions(context).counterSale(context, item),
                              ),
                            if (left > 0)
                              SxButton(
                                label: 'Sold out',
                                kind: SxButtonKind.secondary,
                                icon: TablerIcons.ban,
                                onTap: () => StockActions(context).soldOut(context, item),
                              ),
                          ],
                        ),
                        const SizedBox(height: SxSpace.s8),
                        Row(
                          spacing: SxSpace.s16,
                          children: [
                            SxLinkButton(
                              label: 'Fix count',
                              onTap: () => StockActions(context).fixCount(context, item),
                            ),
                            SxLinkButton(
                              label: 'See details',
                              onTap: () => context.push(Routes.product(item.variantId)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Catalogue extends StatelessWidget {
  const _Catalogue({required this.view});

  final StockView view;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: SxSpace.s12,
        mainAxisSpacing: SxSpace.s12,
        childAspectRatio: 0.82,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final item in view.items)
            SxCard(
              padding: const EdgeInsets.all(SxSpace.s12),
              onTap: () => context.push(Routes.product(item.variantId)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SxIconTile(icon: TablerIcons.package),
                  const SizedBox(height: SxSpace.s8),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                  ),
                  Text(
                    item.variant ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                  Text(
                    item.shelf,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.priceMinor > 0 ? money(item.priceMinor, item.currency) : 'Quote',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxText.label.copyWith(color: p.textPrimary),
                        ),
                      ),
                      if (item.live) const SxChip(label: 'Today', tone: SxChipTone.positive),
                    ],
                  ),
                ],
              ),
            ),
          SxCard(
            padding: const EdgeInsets.all(SxSpace.s12),
            onTap: () {
              HapticFeedback.selectionClick();
              context.push(Routes.addproduct);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SxIconTile(icon: TablerIcons.camera_plus),
                const SizedBox(height: SxSpace.s8),
                Text('Add product', style: SxText.label.copyWith(color: p.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
