import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../sx_theme.dart';
import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_motion.dart';
import 'sx_pressable.dart';

/// Screen primary action (DESIGN.md 9.1), 60 high. Put it in `SxScaffold(floating: ...)`.
/// Never together with the nav bar.
class SxBottomCta extends StatefulWidget {
  const SxBottomCta({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.done = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// Trailing icon in the signal circle. Default: arrow-right.
  final IconData? icon;

  /// Spins the circle and ignores taps.
  final bool loading;

  /// Shows a check in the circle.
  final bool done;

  @override
  State<SxBottomCta> createState() => _SxBottomCtaState();
}

class _SxBottomCtaState extends State<SxBottomCta> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final Widget glyph = widget.loading
        ? SxSpin(child: Icon(TablerIcons.loader_2, size: 20, color: p.onSignal))
        : Icon(widget.done ? TablerIcons.check : (widget.icon ?? TablerIcons.arrow_right), size: 20, color: p.onSignal);
    return Opacity(
      opacity: widget.onTap == null ? 0.5 : 1,
      child: SxPressable(
        onTap: widget.loading ? null : widget.onTap,
        semanticLabel: widget.label,
        onDownChanged: (v) => setState(() => _down = v),
        child: AnimatedContainer(
          duration: SxMotion.fast,
          curve: SxMotion.curve,
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.only(left: 26, right: 6, top: 6, bottom: 6),
          decoration: sxFloating(p, _down ? p.primaryPressed : p.primary),
          child: Row(
            children: [
              Expanded(child: Text(widget.label, style: SxText.labelL.copyWith(color: p.onPrimary))),
              const SizedBox(width: SxSpace.s8),
              AnimatedScale(
                scale: widget.done ? 1.08 : 1,
                duration: SxMotion.base,
                curve: SxMotion.curve,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: p.signal, shape: BoxShape.circle),
                  child: glyph,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
