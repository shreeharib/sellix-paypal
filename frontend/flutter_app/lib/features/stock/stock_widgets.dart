import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

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
            // The stepper would refuse in silence, so the limits are checked in [_changed].
            min: -1 << 31,
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

/// "How long can you sell it?": one question, mapped to stock_mode and shelf_life_days.
class ShelfPicker extends StatefulWidget {
  const ShelfPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.suggestion,
  });

  final ShelfChoice value;
  final ValueChanged<ShelfChoice> onChanged;
  final String? errorText;
  final String? suggestion;

  @override
  State<ShelfPicker> createState() => _ShelfPickerState();
}

class _ShelfPickerState extends State<ShelfPicker> {
  late final _days = TextEditingController(text: '${widget.value.days ?? 5}');
  String? _why;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  void _pick(String c) {
    setState(() => _why = null);
    final days = int.tryParse(_days.text);
    widget.onChanged(ShelfChoice(c, days));
  }

  void _step(int d) {
    final next = (int.tryParse(_days.text) ?? 5) + d;
    if (next < 1 || next > 3650) {
      HapticFeedback.heavyImpact();
      setState(() {
        _why = next < 1
            ? 'One day is the shortest. That is the same as Same day.'
            : '3650 days is the longest. Choose Doesn’t expire instead.';
      });
      return;
    }
    setState(() => _why = null);
    _days.text = '$next';
    widget.onChanged(ShelfChoice('custom', next));
  }

  Widget _chips(List<(String, String)> options) => Wrap(
    spacing: SxSpace.s8,
    runSpacing: SxSpace.s8,
    children: [
      for (final (v, label) in options)
        SxPickChip(
          label: label,
          selected: widget.value.c == v,
          onTap: () => _pick(v),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final why = _why ?? widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'How long can you sell it?',
            children: [
              if (widget.suggestion != null)
                TextSpan(text: ' ${widget.suggestion}', style: TextStyle(color: p.textSecondary)),
            ],
          ),
          style: SxText.label.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: SxSpace.s8),
        _chips(ShelfChoice.quick),
        if (widget.value.c == 'custom')
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
                      widget.onChanged(ShelfChoice('custom', int.tryParse(v)));
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
        Text('Or no count at all', style: SxText.micro.copyWith(color: p.textSecondary)),
        const SizedBox(height: SxSpace.s8),
        _chips(ShelfChoice.noCount),
        const SizedBox(height: SxSpace.s12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(TablerIcons.info_circle, size: 16, color: p.textSecondary),
            const SizedBox(width: SxSpace.s8),
            Expanded(child: Text(widget.value.line, style: SxText.bodyS.copyWith(color: p.textPrimary))),
          ],
        ),
        if (why != null) WhyText(why),
      ],
    );
  }
}
