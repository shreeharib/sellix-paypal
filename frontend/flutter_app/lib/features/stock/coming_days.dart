import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'stock_model.dart';
import 'stock_providers.dart';

String _long(DateTime d) => DateFormat('EEE, d MMM').format(d);
String _weekday(DateTime d) => DateFormat('EEE').format(d);

/// The shop's weekly off is free text from onboarding ("Sundays"), and the only closed data there is.
/// BACKEND GAP: one-off closed dates aren't stored anywhere.
bool _closed(DateTime d, String? weeklyOff) =>
    weeklyOff != null &&
    weeklyOff.toLowerCase().contains(DateFormat('EEEE').format(d).toLowerCase());

String _closedNote(DateTime d) => 'You are closed on ${_long(d)}. Set stock only if you will still sell that day.';

class ComingDays extends ConsumerStatefulWidget {
  const ComingDays({super.key, required this.view});

  final StockView view;

  @override
  ConsumerState<ComingDays> createState() => _ComingDaysState();
}

class _ComingDaysState extends ConsumerState<ComingDays> {
  int _index = 1;

  DateTime _day(int i) => addDays(widget.view.today.businessDate, i);

  String _meta(UpcomingItem item) => [
    'Set ${item.opening}',
    if (item.held > 0) 'On hold ${item.held}',
    if (item.availableOn != null) 'Only this day',
    if (item.orderByDate != null) 'Order by ${DateFormat('d MMM').format(item.orderByDate!)}',
  ].join(' · ');

  List<UpcomingItem> _itemsOn(List<UpcomingDay> days, DateTime day) => [
    for (final d in days)
      if (daysBetween(d.date, day) == 0)
        for (final item in d.items)
          if (item.opening > 0) item,
  ];

  Future<void> _openDay(DateTime day) async {
    final saved = await context.push<String>(Routes.stockFor(day));
    if (!mounted) return;
    ref.invalidate(upcomingProvider);
    if (saved == null) return;
    HapticFeedback.mediumImpact();
    showSxSnack(context, saved, icon: TablerIcons.check);
  }

  @override
  Widget build(BuildContext context) {
    final weeklyOff = ref.watch(shopAnswersProvider).value?.weeklyOff;
    return SxAsyncView<List<UpcomingDay>>(
      value: ref.watch(upcomingProvider),
      onRetry: () => ref.invalidate(upcomingProvider),
      loading: const SxSkeleton(height: 120),
      builder: (context, days) {
        final selected = _day(_index);
        final items = _itemsOn(days, selected);
        final wd = _weekday(selected);
        final p = context.sx;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SxFilterChips(
              children: [
                for (var i = 1; i <= 14; i++)
                  Builder(
                    builder: (_) {
                      final d = _day(i);
                      final n = _itemsOn(days, d).length;
                      return SxFilterChip(
                        label:
                            '${DateFormat('EEE d').format(d)}'
                            '${_closed(d, weeklyOff) ? ' · Closed' : ''}'
                            '${n > 0 ? ' · $n' : ''}',
                        selected: i == _index,
                        onTap: () => setState(() => _index = i),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: SxSpace.s12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: SxSpace.listGap,
                children: [
                  if (_closed(selected, weeklyOff))
                    SxCard(child: Text(_closedNote(selected), style: SxText.bodyS.copyWith(color: p.textPrimary))),
                  if (items.isEmpty)
                    SxCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nothing set for ${_long(selected)}',
                              style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                          const SizedBox(height: SxSpace.s4),
                          Text(
                            'Set a count and customers can order ahead for this day.',
                            style: SxText.caption.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final item in items)
                      SxRowCard(
                        title: itemName(item.product, item.variant),
                        meta: _meta(item),
                        leading: const SxIconTile(icon: TablerIcons.package),
                        chevron: false,
                        trailing: Column(
                          children: [
                            Text('${item.available}', style: SxText.counter.copyWith(color: p.textPrimary)),
                            Text('free', style: SxText.micro.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ),
                  SxButton(
                    label: items.isEmpty ? 'Set $wd stock' : 'Change $wd stock',
                    kind: SxButtonKind.secondary,
                    icon: TablerIcons.calendar_plus,
                    fullWidth: true,
                    onTap: () => _openDay(selected),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
