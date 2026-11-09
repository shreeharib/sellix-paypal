import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../design/design.dart';
import 'stock_model.dart';

/// Shakes its child each time [trigger] changes: a refused tap.
class SxShake extends StatefulWidget {
  const SxShake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<SxShake> createState() => _SxShakeState();
}

class _SxShakeState extends State<SxShake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SxMotion.slow);

  @override
  void didUpdateWidget(SxShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(
      offset: Offset(math.sin(_c.value * math.pi * 6) * 5 * (1 - _c.value), 0),
      child: child,
    ),
    child: widget.child,
  );
}

class WhyText extends StatelessWidget {
  const WhyText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: SxSpace.s8),
    child: Semantics(
      liveRegion: true,
      child: Text(message, style: SxText.caption.copyWith(color: context.sx.errorText)),
    ),
  );
}

/// [SxStockRow] whose refused tap shakes and explains itself in the row.
class WhyStockRow extends StatefulWidget {
  const WhyStockRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.whyMin,
    required this.whyMax,
    this.meta,
    this.chip,
    this.min = 0,
    this.max = stepperMax,
    this.externalWhy,
  });

  final String title;
  final String? meta;
  final Widget? chip;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String whyMin;
  final String whyMax;

  /// A refusal from outside the row: Confirm found this count too low.
  final String? externalWhy;

  @override
  State<WhyStockRow> createState() => _WhyStockRowState();
}

class _WhyStockRowState extends State<WhyStockRow> {
  String? _why;
  int _shakes = 0;

  void _changed(int next) {
    if (next < widget.min || next > widget.max) {
      HapticFeedback.heavyImpact();
      setState(() {
        _why = next < widget.min ? widget.whyMin : widget.whyMax;
        _shakes++;
      });
      return;
    }
    setState(() => _why = null);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final why = _why ?? widget.externalWhy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SxShake(
          trigger: _shakes,
          child: SxStockRow(
            leading: const SxIconTile(icon: TablerIcons.package),
            title: widget.title,
            price: widget.meta,
            chip: widget.chip,
            value: widget.value,
            // The stepper would refuse in silence, so the limits are checked in [_changed]: it lets
            // one step below [min] through. Not `-1 << 31`: on the web Dart's shifts are unsigned,
            // so that was +2147483648 and every "+" was refused with no message (9 Nov bug).
            min: widget.min - 1,
            onChanged: _changed,
          ),
        ),
        if (why != null) WhyText(why),
      ],
    );
  }
}

/// The share of a day's stock sold (solid) and held (muted).
class LedgerBar extends StatelessWidget {
  const LedgerBar({super.key, required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final total = math.max(1, item.made);
    return ClipRRect(
      borderRadius: BorderRadius.circular(SxRadius.pill),
      child: Container(
        height: 4,
        color: p.tile,
        child: LayoutBuilder(
          builder: (_, box) => Row(
            children: [
              Container(width: box.maxWidth * math.min(item.soldTotal, total) / total, color: p.primary),
              Container(width: box.maxWidth * math.min(item.held, total) / total, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// "How do you stock this?" and, only for fresh batches, "How long can you sell it?".
///
/// What it offers comes from the shop type's [ProductSchema]. The answer is a [ShelfChoice], which
/// maps to `stock_mode` and `shelf_life_days` (days only for fresh batches). With one mode on offer
/// the first question is not asked.
class StockTypeQuestion extends StatefulWidget {
  const StockTypeQuestion({
    super.key,
    required this.schema,
    required this.value,
    required this.onChanged,
    this.keepMode,
    this.dailyStart,
    this.errorText,
  });

  final ProductSchema schema;
  final ShelfChoice value;
  final ValueChanged<ShelfChoice> onChanged;

  /// A product's current mode. It is listed even when its shop type doesn't offer it, so that
  /// editing a product never shows or changes it to something else.
  final String? keepMode;

  /// Where fresh batches start when the owner picks them: the shop's usual shelf life.
  final ShelfChoice? dailyStart;
  final String? errorText;

  /// False when there is nothing to ask: one mode on offer, and it doesn't ask a shelf life.
  static bool isNeeded(ProductSchema schema, ShelfChoice value, {String? keepMode}) {
    final modes = stockModesFor(schema, keepMode);
    return modes.length > 1 || _asksShelfLife(modes, value);
  }

  static bool _asksShelfLife(List<StockModeOption> modes, ShelfChoice value) =>
      value.stockMode == StockMode.daily &&
      modes.any((m) => m.id == StockMode.daily && m.asksShelfLife);

  @override
  State<StockTypeQuestion> createState() => _StockTypeQuestionState();
}

class _StockTypeQuestionState extends State<StockTypeQuestion> {
  late final _days = TextEditingController(text: '${_dailyDays(widget.value) ?? 5}');
  late bool _custom = _isCustom(widget.value);
  ShelfChoice? _lastDaily;
  bool _lastCustom = false;
  String? _why;

  @override
  void initState() {
    super.initState();
    if (widget.value.stockMode == StockMode.daily) {
      _lastDaily = widget.value;
      _lastCustom = _custom;
    }
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  int? _dailyDays(ShelfChoice v) => v.stockMode == StockMode.daily ? v.shelfLifeDays : null;

  List<ShelfLifeOption> get _lives => shelfLifeFor(widget.schema);

  bool _isCustom(ShelfChoice v) =>
      v.stockMode == StockMode.daily && !_lives.any((o) => o.days == v.shelfLifeDays);

  void _emit(ShelfChoice v) {
    if (v.stockMode == StockMode.daily) {
      _lastDaily = v;
      _lastCustom = _custom;
    }
    widget.onChanged(v);
  }

  void _pickMode(StockModeOption mode) {
    if (mode.id != StockMode.daily) {
      setState(() => _why = null);
      return _emit(ShelfChoice.of(mode.id, null));
    }
    final start = _lastDaily ?? widget.dailyStart ?? ShelfChoice.of(StockMode.daily, _lives.first.days);
    setState(() {
      _why = null;
      _custom = _lastDaily != null ? _lastCustom : _isCustom(start);
      _days.text = '${_dailyDays(start) ?? 5}';
    });
    _emit(start);
  }

  void _pickDays(int days) {
    setState(() {
      _custom = false;
      _why = null;
    });
    _emit(ShelfChoice.of(StockMode.daily, days));
  }

  void _pickCustom() {
    final now = _dailyDays(widget.value);
    setState(() {
      _custom = true;
      _why = null;
      if (now != null) _days.text = '$now';
    });
    _emit(ShelfChoice('custom', int.tryParse(_days.text)));
  }

  void _step(int d) {
    final next = (int.tryParse(_days.text) ?? 5) + d;
    if (next < 1 || next > 3650) {
      HapticFeedback.heavyImpact();
      setState(() {
        _why = next < 1
            ? 'One day is the shortest. That is the same as Same day.'
            : '3650 days is the longest.';
      });
      return;
    }
    setState(() => _why = null);
    _days.text = '$next';
    _emit(ShelfChoice('custom', next));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final modes = stockModesFor(widget.schema, widget.keepMode);
    final value = widget.value;
    final asksShelfLife = StockTypeQuestion._asksShelfLife(modes, value);
    final why = _why ?? widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s16,
      children: [
        if (modes.length > 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              Text('How do you stock this?', style: SxText.label.copyWith(color: p.textPrimary)),
              for (final mode in modes)
                SxChoiceCard(
                  title: mode.label,
                  subtitle: mode.hint.isEmpty ? null : mode.hint,
                  selected: mode.id == value.stockMode,
                  check: true,
                  onTap: () => _pickMode(mode),
                ),
            ],
          ),
        if (asksShelfLife)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How long can you sell it?', style: SxText.label.copyWith(color: p.textPrimary)),
              const SizedBox(height: SxSpace.s8),
              Wrap(
                spacing: SxSpace.s8,
                runSpacing: SxSpace.s8,
                children: [
                  for (final o in _lives)
                    SxPickChip(
                      label: o.label,
                      selected: !_custom && value.shelfLifeDays == o.days,
                      onTap: () => _pickDays(o.days),
                    ),
                  SxPickChip(label: 'Custom', selected: _custom, onTap: _pickCustom),
                ],
              ),
              if (_custom)
                Padding(
                  padding: const EdgeInsets.only(top: SxSpace.s12),
                  child: Row(
                    children: [
                      SxIconButton(icon: TablerIcons.minus, semanticLabel: 'One day less', onTap: () => _step(-1)),
                      const SizedBox(width: SxSpace.s8),
                      SizedBox(
                        width: 88,
                        child: SxField(
                          controller: _days,
                          hint: 'Days',
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 4,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (v) {
                            setState(() => _why = null);
                            _emit(ShelfChoice('custom', int.tryParse(v)));
                          },
                        ),
                      ),
                      const SizedBox(width: SxSpace.s8),
                      SxIconButton(icon: TablerIcons.plus, semanticLabel: 'One day more', onTap: () => _step(1)),
                      const SizedBox(width: SxSpace.s8),
                      Text('days', style: SxText.bodyS.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
              const SizedBox(height: SxSpace.s12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(TablerIcons.info_circle, size: 16, color: p.textSecondary),
                  const SizedBox(width: SxSpace.s8),
                  Expanded(child: Text(value.line, style: SxText.bodyS.copyWith(color: p.textPrimary))),
                ],
              ),
            ],
          ),
        if (why != null) WhyText(why),
      ],
    );
  }
}
