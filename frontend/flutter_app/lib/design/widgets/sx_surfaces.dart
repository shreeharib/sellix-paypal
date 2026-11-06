import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';
import 'sx_sheet.dart';

/// Plain `card` surface, radius 24, padding 16. On a sheet it uses `page`.
class SxCard extends StatelessWidget {
  const SxCard({super.key, required this.child, this.padding, this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final card = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(SxSpace.card),
      decoration: BoxDecoration(
        color: color ?? (SxSheetScope.isOnSheet(context) ? p.page : p.card),
        borderRadius: BorderRadius.circular(SxRadius.card),
      ),
      child: child,
    );
    return onTap == null ? card : SxPressable(onTap: onTap, child: card);
  }
}

/// `tile` square holding an icon. Also the product placeholder: real products have
/// no bundled photos, so use this instead of assets/images.
class SxIconTile extends StatelessWidget {
  const SxIconTile({super.key, this.icon, this.child, this.size = 44, this.radius, this.background, this.foreground});

  final IconData? icon;

  /// Replaces [icon], for brand icons.
  final Widget? child;
  final double size;

  /// Default: `SxRadius.tile` (14).
  final double? radius;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? p.tile,
        borderRadius: BorderRadius.circular(radius ?? SxRadius.tile),
      ),
      child: child ?? Icon(icon, size: size * 0.45, color: foreground ?? p.textPrimary),
    );
  }
}

enum SxBannerTone { attention, error, neutral }

/// Inline banner (`.sx-banner-att`, `.sx-banner-err`).
class SxBanner extends StatelessWidget {
  const SxBanner({super.key, required this.message, this.tone = SxBannerTone.attention, this.icon, this.action});

  final String message;
  final SxBannerTone tone;
  final IconData? icon;

  /// Below the message, usually an `SxLinkButton`.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final (Color bg, Color fg, Color? line, IconData glyph) = switch (tone) {
      SxBannerTone.attention => (p.attentionSoft, p.attentionTextStrong, p.attentionLine, TablerIcons.alert_triangle),
      SxBannerTone.error => (p.errorSoft, p.errorText, null, TablerIcons.alert_circle),
      SxBannerTone.neutral => (p.tile, p.noteText, null, TablerIcons.info_circle),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: SxSpace.s12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SxRadius.bubble),
        border: line == null ? null : Border.all(color: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? glyph, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: SxText.bodyS.copyWith(color: fg)),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The honest note for a feature with no endpoint (see the shared brief, "Real data only").
class SxLocalOnlyNote extends StatelessWidget {
  const SxLocalOnlyNote({super.key, this.message = 'Saved on this phone only, not active yet.'});

  final String message;

  @override
  Widget build(BuildContext context) =>
      SxBanner(message: message, tone: SxBannerTone.neutral, icon: TablerIcons.device_mobile);
}

/// Label on the left, value on the right (`.kv`). Set [divider] on all rows but the first.
class SxKeyValue extends StatelessWidget {
  const SxKeyValue({super.key, required this.label, this.value, this.valueWidget, this.divider = false});

  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: p.line)) : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: SxText.bodyS.copyWith(color: p.textSecondary))),
          const SizedBox(width: SxSpace.s12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: valueWidget ??
                  Text(value ?? '', textAlign: TextAlign.end, style: SxText.label.copyWith(color: p.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Onboarding progress pills. [current] is zero-based; [fraction] is how far into it.
class SxStepsBar extends StatelessWidget {
  const SxStepsBar({super.key, required this.total, required this.current, this.fraction = 0.5});

  final int total;
  final int current;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SxRadius.pill),
                child: Container(
                  height: 4,
                  color: p.lineStrong,
                  alignment: AlignmentDirectional.centerStart,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: i < current ? 1.0 : (i == current ? fraction : 0.0)),
                    duration: SxMotion.slow,
                    curve: SxMotion.curve,
                    builder: (_, v, _) => FractionallySizedBox(
                      widthFactor: v,
                      heightFactor: 1,
                      child: ColoredBox(color: p.primary),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 8 px progress bar (`.meter`). [fraction] from 0 to 1.
class SxMeter extends StatelessWidget {
  const SxMeter({super.key, required this.fraction, this.height = 8, this.color, this.background});

  final double fraction;
  final double height;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SxRadius.pill),
      child: Container(
        height: height,
        color: background ?? p.tile,
        alignment: AlignmentDirectional.centerStart,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 700),
          curve: SxMotion.curve,
          builder: (_, v, _) => FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: ColoredBox(color: color ?? p.primary),
          ),
        ),
      ),
    );
  }
}

/// 32 px chip with a 44 px target, for picking a time.
class SxTimeChip extends StatelessWidget {
  const SxTimeChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxPressable(
      small: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.s8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SxSheetScope.isOnSheet(context) ? p.page : p.tile,
            borderRadius: BorderRadius.circular(SxRadius.pill),
          ),
          child: Text(label, style: SxText.caption.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
