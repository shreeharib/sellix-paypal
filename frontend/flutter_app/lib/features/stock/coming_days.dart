import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:intl/intl.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../design/design.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

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

  List<UpcomingItem> _itemsOn(List<UpcomingDay> days, DateTime day) => [
    for (final d in days)
      if (daysBetween(d.date, day) == 0)
        for (final item in d.items)
          if (item.opening > 0) item,
  ];

  Future<void> _openSheet(List<UpcomingDay> days, String? weeklyOff) async {
    final tracked = widget.view.tracked.toList();
    if (tracked.isEmpty) {
      showSxSnack(context, 'No counted products yet. Add a product first.', icon: TablerIcons.info_circle);
      return;
    }
    final from = _day(_index);
    final saved = await showSxSheet<int>(
      context,
      title: 'Stock for ${_long(from)}',
      subtitle: _closed(from, weeklyOff)
          ? _closedNote(from)
          : 'How many can you sell that day? Zero means none.',
      builder: (_) => _ComingSheet(from: from, items: tracked, days: days),
    );
    if (saved == null || !mounted) return;
    ref.invalidate(upcomingProvider);
    HapticFeedback.mediumImpact();
    showSxSnack(
      context,
      saved == 1
          ? 'Stock set for ${_long(from)}.'
          : 'Stock set from ${_long(from)} to ${_long(addDays(from, saved - 1))}.',
      icon: TablerIcons.check,
    );
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
                        meta: 'Set ${item.opening}${item.held > 0 ? ' · On hold ${item.held}' : ''}',
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
                    onTap: () => _openSheet(days, weeklyOff),
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

class _ComingSheet extends ConsumerStatefulWidget {
  const _ComingSheet({required this.from, required this.items, required this.days});

  final DateTime from;
  final List<StockItem> items;
  final List<UpcomingDay> days;

  @override
  ConsumerState<_ComingSheet> createState() => _ComingSheetState();
}

class _ComingSheetState extends ConsumerState<_ComingSheet> {
  late final Map<String, int> _counts = {
    for (final item in widget.items) item.variantId: _on(widget.from, item)?.opening ?? 0,
  };
  int _range = 1;
  bool _saving = false;
  String? _error;

  UpcomingItem? _on(DateTime day, StockItem item) {
    for (final d in widget.days) {
      if (daysBetween(d.date, day) != 0) continue;
      for (final u in d.items) {
        if (u.variantId == item.variantId ||
            (u.variantId == null && u.product == item.name && u.variant == item.variant)) {
          return u;
        }
      }
    }
    return null;
  }

  /// One day's lines. A count below what orders hold on that day stays at the held number.
  List<StockLine> _linesFor(DateTime day) => [
    for (final item in widget.items)
      if ((_counts[item.variantId] ?? 0) > 0 || (_on(day, item)?.opening ?? 0) > 0)
        item.line(
          _counts[item.variantId]! > (_on(day, item)?.held ?? 0)
              ? _counts[item.variantId]!
              : (_on(day, item)?.held ?? 0),
        ),
  ];

  String _key(List<StockLine> lines) => lines.map((l) => '${l.label}:${l.quantity}').join('|');

  Future<void> _save() async {
    final had = widget.items.any((i) => (_on(widget.from, i)?.opening ?? 0) > 0);
    if (!had && _counts.values.every((v) => v == 0)) {
      HapticFeedback.heavyImpact();
      setState(() => _error = 'All counts are zero. Set a count for at least one product.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ref.read(sellixApiProvider);
    final days = [for (var i = 0; i < _range; i++) addDays(widget.from, i)];
    final perDay = [for (final d in days) _linesFor(d)];
    try {
      if (perDay.every((l) => _key(l) == _key(perDay.first))) {
        if (perDay.first.isNotEmpty) await api.setUpcomingStock(days.first, days.last, perDay.first);
      } else {
        for (final (i, lines) in perDay.indexed) {
          if (lines.isNotEmpty) await api.setUpcomingStock(days[i], days[i], lines);
        }
      }
      if (mounted) Navigator.of(context).pop(_range);
    } on Exception catch (error) {
      if (!mounted) return;
      ref.invalidate(upcomingProvider);
      setState(() {
        _saving = false;
        _error = sxErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s8,
      children: [
        for (final item in widget.items)
          Builder(
            builder: (_) {
              final held = _on(widget.from, item)?.held ?? 0;
              return WhyStockRow(
                title: item.label,
                meta: '${item.shelf}${held > 0 ? ' · On hold $held' : ''}',
                value: _counts[item.variantId]!,
                min: held,
                whyMin: held > 0
                    ? '$held on hold for this day. You can’t go below $held.'
                    : 'Zero means none. You can’t go below zero.',
                whyMax: 'The most you can set is $stepperMax.',
                onChanged: (v) => setState(() => _counts[item.variantId] = v),
              );
            },
          ),
        const SizedBox(height: SxSpace.s8),
        Text('Same count for', style: SxText.label.copyWith(color: p.textPrimary)),
        Wrap(
          spacing: SxSpace.s8,
          runSpacing: SxSpace.s8,
          children: [
            for (final (n, label) in const [(1, 'This day'), (3, 'Next 3 days'), (7, 'Next 7 days')])
              SxPickChip(
                label: label,
                selected: _range == n,
                onTap: () => setState(() => _range = n),
              ),
          ],
        ),
        if (_error != null) WhyText(_error!),
        const SizedBox(height: SxSpace.s16),
        SxButton(label: 'Save stock', fullWidth: true, loading: _saving, onTap: _saving ? null : _save),
      ],
    );
  }
}
