import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_motion.dart';
import 'sx_pressable.dart';
import 'sx_sheet.dart';

enum SxChipTone { neutral, attention, positive, error }

/// Status chip (DESIGN.md 9.2): `micro` text, padding 5 x 10.
class SxChip extends StatelessWidget {
  const SxChip({
    super.key,
    required this.label,
    this.tone = SxChipTone.neutral,
    this.icon,
    this.dot = false,
    this.pulse = false,
  });

  final String label;
  final SxChipTone tone;
  final IconData? icon;

  /// 6 px signal dot before the label; [pulse] makes it the live dot.
  final bool dot;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final onSheet = SxSheetScope.isOnSheet(context);
    final (Color bg, Color fg) = switch (tone) {
      SxChipTone.neutral => (onSheet ? p.page : p.card, p.textPrimary),
      SxChipTone.attention => (p.attentionSoft, p.attentionText),
      SxChipTone.positive => (p.successSoft, p.successText),
      SxChipTone.error => (p.errorSoft, p.errorText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SxRadius.pill),
        border: tone == SxChipTone.neutral && !onSheet ? Border.all(color: p.line) : null,
      ),
      // Text.rich, not a Row with Flexible: chips often sit directly in a Row, which gives them unbounded width.
      child: Text.rich(
        TextSpan(children: [
          if (dot)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SxPulseDot(size: 6, pulse: pulse),
              ),
            ),
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(icon, size: 14, color: fg),
              ),
            ),
          TextSpan(text: label),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SxText.micro.copyWith(color: fg),
      ),
    );
  }
}

/// Count badge. Renders nothing at zero unless [showZero].
class SxBadge extends StatelessWidget {
  const SxBadge({super.key, required this.count, this.size = 22, this.showZero = false});

  final int count;

  /// 22 by default, 20 in chips and rows, 18 in the nav.
  final double size;
  final bool showZero;

  @override
  Widget build(BuildContext context) {
    if (count == 0 && !showZero) return const SizedBox.shrink();
    final p = context.sx;
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size >= 22 ? 7 : 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.attention, borderRadius: BorderRadius.circular(SxRadius.pill)),
      child: Text('$count', style: SxText.micro.copyWith(color: p.onAttention, fontWeight: FontWeight.w700)),
    );
  }
}

enum SxAgentState { live, paused, waiting }

/// Agent status pill (DESIGN.md 9.6). Always `livePill`; only the dot changes.
class SxLivePill extends StatelessWidget {
  const SxLivePill({super.key, required this.state, this.onTap, this.label});

  final SxAgentState state;
  final VoidCallback? onTap;

  /// Overrides "Agent live" / "Agent paused" / "Waiting for stock".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final text = label ??
        switch (state) {
          SxAgentState.live => 'Agent live',
          SxAgentState.paused => 'Agent paused',
          SxAgentState.waiting => 'Waiting for stock',
        };
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: p.livePill, borderRadius: BorderRadius.circular(SxRadius.pill)),
      child: Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: switch (state) {
                SxAgentState.live => const SxPulseDot(),
                SxAgentState.paused => SxPulseDot(color: p.attention, pulse: false),
                SxAgentState.waiting => SxPulseDot(color: p.textTertiary, pulse: false),
              },
            ),
          ),
          TextSpan(text: text),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SxText.micro.copyWith(color: p.onLivePill),
      ),
    );
    if (onTap == null) return Semantics(label: 'Agent status: $text', child: ExcludeSemantics(child: pill));
    return SxPressable(
      small: true,
      onTap: onTap,
      semanticLabel: 'Agent status: $text',
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: pill),
    );
  }
}

/// Selectable filter chip, 36 high with a 44 px tap target.
class SxFilterChip extends StatelessWidget {
  const SxFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? badge;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final bg = selected ? p.primary : (SxSheetScope.isOnSheet(context) ? p.page : p.card);
    final fg = selected ? p.onPrimary : p.textPrimary;
    return SxPressable(
      small: true,
      haptic: false,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: AnimatedContainer(
          duration: SxMotion.fast,
          curve: SxMotion.curve,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(SxRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label, style: SxText.label.copyWith(color: fg)),
              if ((badge ?? 0) > 0) ...[const SizedBox(width: 6), SxBadge(count: badge!, size: 20)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal scroller of filter chips with the 20 px screen margin.
class SxFilterChips extends StatelessWidget {
  const SxFilterChips({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: SxSpace.s8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Multi-select chip used in onboarding and forms: 40 high, check slides in when selected.
class SxPickChip extends StatelessWidget {
  const SxPickChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final bg = selected ? p.primary : (SxSheetScope.isOnSheet(context) ? p.page : p.card);
    final fg = selected ? p.onPrimary : p.textPrimary;
    return SxPressable(
      small: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: AnimatedContainer(
          duration: SxMotion.base,
          curve: SxMotion.curve,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.s16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(SxRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label, style: SxText.label.copyWith(color: fg)),
              AnimatedSize(
                duration: SxMotion.base,
                curve: SxMotion.spring,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(TablerIcons.check, size: 16, color: fg),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
