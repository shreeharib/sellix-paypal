import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';
import 'sx_sheet.dart';

/// Minus, rolling count, plus (DESIGN.md 9.17). Zero shows in `textSecondary`.
class SxStepper extends StatelessWidget {
  const SxStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.itemName,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int? max;

  /// Spoken in the buttons' labels: "Less of Rose saree".
  final String? itemName;

  void _step(int d) {
    final next = value + d;
    if (next < min || (max != null && next > max!)) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final suffix = itemName == null ? '' : ' of $itemName';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(icon: TablerIcons.minus, label: 'Less$suffix', onTap: onChanged == null ? null : () => _step(-1)),
        // One node with the current count ("Count of Rose saree", "3"): the rolling text keeps
        // both the old and the new number on screen for a moment, so it isn't read itself.
        Semantics(
          container: true,
          liveRegion: true,
          label: 'Count$suffix',
          value: '$value',
          child: ExcludeSemantics(
            child: SizedBox(
              width: 38,
              height: 22,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: SxMotion.base,
                  switchInCurve: SxMotion.curve,
                  switchOutCurve: SxMotion.curve,
                  transitionBuilder: (child, a) => SlideTransition(
                    position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: Text(
                    '$value',
                    key: ValueKey(value),
                    textAlign: TextAlign.center,
                    style: SxText.counter.copyWith(height: 22 / 17, color: value == 0 ? p.textSecondary : p.textPrimary),
                  ),
                ),
              ),
            ),
          ),
        ),
        _StepButton(icon: TablerIcons.plus, label: 'More$suffix', onTap: onChanged == null ? null : () => _step(1)),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxPressable(
      small: true,
      haptic: false,
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        // 40 x 44 tap target around the 32 px circle.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: SxSheetScope.isOnSheet(context) ? p.page : p.tile,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: p.textPrimary),
        ),
      ),
    );
  }
}
