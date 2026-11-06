import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/api/sellix_api.dart';
import '../../core/providers.dart';
import '../../design/design.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

/// Every stock change, with the prototype's sheets and snackbars.
///
/// Holds the provider container and the root overlay rather than the calling screen, because an
/// Undo snackbar outlives the screen that showed it.
class StockActions {
  StockActions(BuildContext context)
    : _container = ProviderScope.containerOf(context, listen: false),
      _nav = Navigator.of(context, rootNavigator: true);

  final ProviderContainer _container;
  final NavigatorState _nav;

  SellixApi get _api => _container.read(sellixApiProvider);

  /// A context inside the root overlay, found when needed so it is always a live one.
  BuildContext? _anchor() {
    final overlay = _nav.mounted ? _nav.overlay : null;
    if (overlay == null) return null;
    BuildContext? found;
    void walk(Element e) {
      if (found != null) return;
      if (Overlay.maybeOf(e, rootOverlay: true) != null) {
        found = e;
      } else {
        e.visitChildElements(walk);
      }
    }

    (overlay.context as Element).visitChildElements(walk);
    return found;
  }

  void _snack(String text, {IconData? icon, String? action, VoidCallback? onAction}) {
    final context = _anchor();
    if (context == null) return;
    showSxSnack(context, text, icon: icon, action: action, onAction: onAction);
  }

  /// A snackbar that stays correct after the calling screen has gone.
  void announce(String text, {IconData? icon}) => _snack(text, icon: icon);

  void refresh() {
    _container.invalidate(todayProvider);
    _container.invalidate(catalogProvider);
  }

  void _failed(Object error) {
    HapticFeedback.heavyImpact();
    _snack(sxErrorMessage(error), icon: TablerIcons.alert_circle);
    refresh();
  }

  /// Runs a write. False when it failed, already reported.
  Future<bool> _write(Future<void> Function() call) async {
    try {
      await call();
      refresh();
      return true;
    } on Exception catch (error) {
      _failed(error);
      return false;
    }
  }

  Future<void> restock(BuildContext context, StockItem item) async {
    final v = await _qtySheet(
      context,
      title: 'Add stock: ${item.label}',
      subtitle: 'How many more do you have to sell?',
      start: 0,
      min: 0,
      okMin: 1,
      verb: 'Add to stock',
      whyMin: 'Zero is the least here.',
      whyOk: 'Add at least 1, or close this.',
    );
    if (v == null) return;
    final hasRow = item.row != null;
    final ok = await _write(() async {
      if (hasRow) {
        await _api.restock(item.variantId, v);
      } else {
        await _api.setOpeningStock([item.line(v)]);
      }
    });
    if (!ok) return;
    HapticFeedback.mediumImpact();
    // There is no un-restock, but the same units can come off opening. That is the whole undo when
    // opening holds at least that many; otherwise no Undo is offered.
    final canUndo = !hasRow || item.opening >= v;
    _snack(
      '$v more added. sellix can sell them now.',
      icon: TablerIcons.check,
      action: canUndo ? 'Undo' : null,
      onAction: canUndo ? () => _undoRestock(item, v) : null,
    );
  }

  Future<void> _undoRestock(StockItem item, int v) async {
    await _write(() async {
      final today = await _api.today();
      final row = today.stock.where((r) => r.variantId == item.variantId).firstOrNull;
      final opening = (row?.opening ?? 0) - v;
      if (opening < 0) throw Exception('Can’t undo');
      await _api.setOpeningStock([item.line(opening)]);
    });
  }

  Future<void> counterSale(BuildContext context, StockItem item) async {
    final left = item.available;
    final v = await _qtySheet(
      context,
      title: 'Sold at shop',
      // BACKEND GAP: no endpoint lowers counter_sales, so a saved sale has no Undo.
      subtitle: '${item.label}. sellix stops selling these. You can’t undo this once saved.',
      start: 0,
      min: 0,
      okMin: 1,
      max: left,
      verb: 'Save sale',
      whyMax: 'Only $left left. You can’t sell more than you have. Add stock first.',
      whyMin: 'Zero is the least here.',
      whyOk: 'One is the least you can save.',
    );
    if (v == null) return;
    final ok = await _write(() => _api.recordCounterSale(item.variantId, v));
    if (!ok) return;
    HapticFeedback.mediumImpact();
    _snack('${plural(v, 'sale', 'sales')} at shop saved.', icon: TablerIcons.building_store);
  }

  Future<void> soldOut(BuildContext context, StockItem item) async {
    final left = item.available;
    // BACKEND GAP: POST /v1/today/sold-out books the unsold units as counter_sales and nothing lowers
    // them. So this has no Undo, needs a confirm the prototype didn't, and the row can't say
    // "Marked sold out, N not sold": those units read as Sold. Proposed: a separate field.
    final sure = await showSxConfirm(
      context,
      title: 'Mark ${item.label} sold out?',
      body:
          'The ${units(left)} left will count as sold at shop today. You can’t undo this. '
          'Add stock puts it back on sale.',
      confirmLabel: 'Sold out',
      confirmIcon: TablerIcons.ban,
    );
    if (!sure) return;
    final ok = await _write(() => _api.markSoldOut(item.variantId));
    if (!ok) return;
    HapticFeedback.mediumImpact();
    _snack('${item.label} is sold out. sellix tells customers and notes who asked.', icon: TablerIcons.ban);
  }

  Future<void> fixCount(BuildContext context, StockItem item) async {
    final min = item.minMade;
    final why = item.floor >= item.restocked
        ? (item.floor > 0 ? '${item.floorWhy}. Stock can’t go below ${item.floor}.' : 'Stock can’t go below zero.')
        : '${item.restocked} added today. Stock can’t go below ${item.restocked}.';
    final v = await _qtySheet(
      context,
      title: 'Fix count',
      subtitle: '${item.label}. Your full stock today.',
      start: item.made,
      min: min,
      verb: 'Save count',
      whyMin: why,
      quick: false,
    );
    if (v == null) return;
    final was = item.opening;
    final ok = await _write(() => _api.setOpeningStock([item.line(v - item.restocked)]));
    if (!ok) return;
    HapticFeedback.mediumImpact();
    _snack(
      'Stock is now $v.',
      icon: TablerIcons.check,
      action: 'Undo',
      onAction: () => _write(() => _api.setOpeningStock([item.line(was)])),
    );
  }

  /// "On sale today" off: the count comes down to what is already sold, so nothing is left to offer.
  Future<void> takeOffSale(StockItem item) async {
    if (item.held > 0) {
      HapticFeedback.heavyImpact();
      _snack('${item.held} on hold. Finish those orders, then take it off sale.', icon: TablerIcons.info_circle);
      return;
    }
    if (item.restocked > item.soldTotal) {
      // BACKEND GAP: restocked can't be lowered, and opening can't go below zero.
      _snack('${item.restocked} added today can’t be taken off. Use Sold out instead.', icon: TablerIcons.info_circle);
      return;
    }
    final was = item.opening;
    final ok = await _write(() => _api.setOpeningStock([item.line(item.soldTotal - item.restocked)]));
    if (!ok) return;
    _snack(
      '${item.label} is off sale today.',
      icon: TablerIcons.check,
      action: 'Undo',
      onAction: () => _write(() => _api.setOpeningStock([item.line(was)])),
    );
  }

  /// The opening to send when an item's stock type changes. Null: refused, with the reason.
  static String? shelfRefusal(StockItem item, ShelfChoice next) =>
      item.counted && next.isNoCount && item.held > 0
      ? '${item.held} on hold. Finish those orders, then change this.'
      : null;

  static int shelfOpening(StockItem item, ShelfChoice next) {
    final changesKind = item.counted == next.isNoCount;
    if (!changesKind) return item.opening;
    final kept = item.floor - item.restocked;
    return kept > 0 ? kept : 0;
  }

  Future<void> changeShelf(BuildContext context, StockItem item) async {
    final next = await showSxSheet<ShelfChoice>(
      context,
      title: item.label,
      builder: (sheet) => _ShelfSheet(item: item),
    );
    if (next == null || next.sameAs(ShelfChoice.of(item.stockMode, item.shelfLifeDays))) return;
    final wasCounted = item.counted;
    final ok = await _write(
      () => _api.setOpeningStock([item.line(shelfOpening(item, next), shelf: next)]),
    );
    if (!ok) return;
    HapticFeedback.mediumImpact();
    final text = 'Now: ${shelfLabel(next.stockMode, next.shelfLifeDays)}.';
    if (!wasCounted && !next.isNoCount) {
      offerAddStock(item, '$text Set a count so sellix can sell it.');
    } else {
      _snack(text, icon: TablerIcons.check);
    }
  }

  /// The prototype's nudge when a product starts being counted with nothing to sell. Opens from the
  /// root, as the screen that saved may have closed by the time it is tapped.
  void offerAddStock(StockItem item, String text) {
    _snack(
      text,
      icon: TablerIcons.check,
      action: 'Add stock',
      onAction: () {
        final context = _anchor();
        if (context != null) restock(context, item);
      },
    );
  }

  Future<void> leftovers(BuildContext context, YesterdayLeftoversResponse data) async {
    final log = _container.read(carriedLogProvider);
    final already = log.read(data.businessDate);
    final counts = await showSxSheet<Map<String, int>>(
      context,
      title: 'Left from yesterday',
      subtitle: data.leftovers.any((i) => i.keeps)
          ? 'Check the counts. sellix sells these today.'
          : 'Nothing carries to today.',
      builder: (sheet) => _LeftoversSheet(items: data.leftovers, already: already),
    );
    if (counts == null || counts.isEmpty) return;
    final send = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (value > 0) RolloverItem(variantId: key, rolloverQuantity: value),
    ];
    final ok = await _write(() async {
      if (send.isNotEmpty) await _api.applyRollover(send);
      await log.add(data.businessDate, counts);
    });
    _container.invalidate(leftoversProvider);
    if (!ok) return;
    HapticFeedback.mediumImpact();
    final moved = counts.values.fold(0, (a, b) => a + b);
    _snack('${units(moved)} carried to today.', icon: TablerIcons.check);
  }

  Future<int?> _qtySheet(
    BuildContext context, {
    required String title,
    required String subtitle,
    required int start,
    required int min,
    int? okMin,
    int max = stepperMax,
    required String verb,
    required String whyMin,
    String? whyMax,
    String? whyOk,
    bool quick = true,
  }) => showSxSheet<int>(
    context,
    title: title,
    subtitle: subtitle,
    builder: (sheet) => _QtySheet(
      start: start,
      min: min,
      okMin: okMin ?? min,
      max: max,
      verb: verb,
      whyMin: whyMin,
      whyMax: whyMax ?? 'The most you can set is $max.',
      whyOk: whyOk ?? whyMin,
      quick: quick,
    ),
  );
}

class _QtySheet extends StatefulWidget {
  const _QtySheet({
    required this.start,
    required this.min,
    required this.okMin,
    required this.max,
    required this.verb,
    required this.whyMin,
    required this.whyMax,
    required this.whyOk,
    required this.quick,
  });

  final int start;
  final int min;
  final int okMin;
  final int max;
  final String verb;
  final String whyMin;
  final String whyMax;
  final String whyOk;
  final bool quick;

  @override
  State<_QtySheet> createState() => _QtySheetState();
}

class _QtySheetState extends State<_QtySheet> {
  late int _v = widget.start.clamp(widget.min, widget.max < widget.min ? widget.min : widget.max);
  String? _why;
  int _shakes = 0;

  void _refuse(String why) {
    HapticFeedback.heavyImpact();
    setState(() {
      _why = why;
      _shakes++;
    });
  }

  void _set(int next) {
    if (next < widget.min) return _refuse(widget.whyMin);
    if (next > widget.max) return _refuse(widget.whyMax);
    HapticFeedback.selectionClick();
    setState(() {
      _v = next;
      _why = null;
    });
  }

  Widget _big(IconData icon, String label, int d) {
    final p = context.sx;
    return SxPressable(
      small: true,
      semanticLabel: label,
      onTap: () => _set(_v + d),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: p.tile, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: p.textPrimary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: SxSpace.s8),
        SxShake(
          trigger: _shakes,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: SxSpace.s16,
            children: [
              _big(TablerIcons.minus, 'Less', -1),
              SizedBox(
                width: 70,
                child: Text(
                  '$_v',
                  textAlign: TextAlign.center,
                  style: SxText.display.copyWith(color: _v == 0 ? p.textSecondary : p.textPrimary),
                ),
              ),
              _big(TablerIcons.plus, 'More', 1),
            ],
          ),
        ),
        if (_why != null) Center(child: WhyText(_why!)),
        if (widget.quick) ...[
          const SizedBox(height: SxSpace.s16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: SxSpace.s8,
            children: [
              for (final n in const [1, 3, 5, 10])
                SxPickChip(label: '+$n', selected: false, onTap: () => _set(_v + n)),
            ],
          ),
        ],
        const SizedBox(height: SxSpace.s24),
        SxButton(
          label: widget.verb,
          fullWidth: true,
          onTap: () {
            if (_v < widget.okMin) return _refuse(widget.whyOk);
            Navigator.of(context).pop(_v);
          },
        ),
      ],
    );
  }
}

class _ShelfSheet extends StatefulWidget {
  const _ShelfSheet({required this.item});

  final StockItem item;

  @override
  State<_ShelfSheet> createState() => _ShelfSheetState();
}

class _ShelfSheetState extends State<_ShelfSheet> {
  late var _value = ShelfChoice.of(widget.item.stockMode, widget.item.shelfLifeDays);
  String? _error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ShelfPicker(
        value: _value,
        errorText: _error,
        onChanged: (v) => setState(() {
          _value = v;
          _error = null;
        }),
      ),
      const SizedBox(height: SxSpace.s24),
      SxButton(
        label: 'Save',
        fullWidth: true,
        onTap: () {
          if (!_value.isValid) {
            setState(() => _error = 'Enter 1 to 3650 days. If it never ends, choose Doesn’t expire.');
            return;
          }
          final refusal = StockActions.shelfRefusal(widget.item, _value);
          if (refusal != null) {
            HapticFeedback.heavyImpact();
            setState(() => _error = refusal);
            return;
          }
          Navigator.of(context).pop(_value);
        },
      ),
    ],
  );
}

class _LeftoversSheet extends StatefulWidget {
  const _LeftoversSheet({required this.items, required this.already});

  final List<YesterdayLeftoverItem> items;
  final Map<String, int> already;

  @override
  State<_LeftoversSheet> createState() => _LeftoversSheetState();
}

class _LeftoversSheetState extends State<_LeftoversSheet> {
  late final _pending = [
    for (final item in widget.items)
      if (item.keeps && !widget.already.containsKey(item.variantId)) item,
  ];
  late final _counts = {for (final item in _pending) item.variantId: item.leftoverQuantity};

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final done = [
      for (final item in widget.items)
        if (item.keeps && widget.already.containsKey(item.variantId)) item,
    ];
    final ended = widget.items.where((i) => !i.keeps).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s8,
      children: [
        for (final item in _pending)
          WhyStockRow(
            title: itemName(item.product, item.variant),
            // BACKEND GAP: no batch date is stored, so "N days left" and "ended" after N days can't
            // be known, and a 3-day item keeps carrying past 3 days. Proposed: carried_since.
            meta: shelfLabel(item.stockMode, item.shelfLifeDays),
            value: _counts[item.variantId]!,
            max: item.leftoverQuantity,
            whyMin: 'Zero means none carried. You can’t go below zero.',
            whyMax: 'Only ${item.leftoverQuantity} left from yesterday. Add new pieces with Add stock.',
            onChanged: (v) => setState(() => _counts[item.variantId] = v),
          ),
        for (final item in done)
          SxRowCard(
            title: itemName(item.product, item.variant),
            meta: '${units(widget.already[item.variantId]!)} carried today',
            leading: const SxIconTile(icon: TablerIcons.circle_check),
            chevron: false,
          ),
        if (ended.isNotEmpty) ...[
          const SizedBox(height: SxSpace.s8),
          Text('Ended, not for sale', style: SxText.label.copyWith(color: p.textPrimary)),
          for (final item in ended)
            SxRowCard(
              title: itemName(item.product, item.variant),
              meta:
                  '${item.leftoverQuantity} left. ${shelfLabel(item.stockMode, item.shelfLifeDays)}, past its time.',
              leading: const SxIconTile(icon: TablerIcons.package),
              trailing: const SxChip(label: 'Ended', icon: TablerIcons.clock_off),
              chevron: false,
            ),
        ],
        const SizedBox(height: SxSpace.s16),
        SxButton(
          label: _pending.isNotEmpty ? 'Confirm counts' : 'Close',
          fullWidth: true,
          onTap: () => Navigator.of(context).pop(_counts),
        ),
      ],
    );
  }
}

/// "Left from yesterday", on the stock list and on today's list. Nothing shows when there are none
/// or the leftovers can't load: the rest of the screen doesn't depend on them.
class LeftoversRow extends ConsumerWidget {
  const LeftoversRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(leftoversProvider).value;
    if (data == null || data.leftovers.isEmpty) return const SizedBox.shrink();
    final carry = data.leftovers.where((i) => i.keeps).toList();
    final carried = ref.read(carriedLogProvider).read(data.businessDate);
    final pending = carry.where((i) => !carried.containsKey(i.variantId));
    final ended = data.leftovers.where((i) => !i.keeps).fold(0, (a, i) => a + i.leftoverQuantity);
    final done = carry.isNotEmpty && pending.isEmpty;
    final meta = [
      if (done)
        '${units(carried.values.fold(0, (a, b) => a + b))} carried, checked'
      else if (pending.isNotEmpty)
        '${units(pending.fold(0, (a, i) => a + i.leftoverQuantity))} to check',
      if (ended > 0) '$ended ended',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: SxSpace.listGap),
      child: SxRowCard(
        title: 'Left from yesterday',
        meta: meta,
        icon: done ? TablerIcons.circle_check : TablerIcons.history,
        onTap: () => StockActions(context).leftovers(context, data),
      ),
    );
  }
}
