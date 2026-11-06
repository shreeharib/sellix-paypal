import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_motion.dart';
import 'sx_pressable.dart';

enum SxButtonKind { primary, secondary, signal, option, optionRecommended, ghostAnchor }

/// DESIGN.md 9.1. Label starts with a verb. A null [onTap] dims the button: use it only for
/// a BACKEND GAP, with the reason shown next to it.
class SxButton extends StatefulWidget {
  const SxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = SxButtonKind.primary,
    this.icon,
    this.fullWidth = false,
    this.loading = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final SxButtonKind kind;
  final IconData? icon;
  final bool fullWidth;

  /// Swaps the icon for a spinner and ignores taps.
  final bool loading;
  final String? semanticLabel;

  @override
  State<SxButton> createState() => _SxButtonState();
}

class _SxButtonState extends State<SxButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final kind = widget.kind;
    final primaryBg = _down ? p.primaryPressed : p.primary;
    final (Color bg, Color fg, Color? border) = switch (kind) {
      SxButtonKind.primary || SxButtonKind.optionRecommended => (primaryBg, p.onPrimary, null),
      SxButtonKind.secondary => (Colors.transparent, p.textPrimary, p.lineStrong),
      SxButtonKind.signal => (p.signal, p.onSignal, null),
      SxButtonKind.option => (p.card, p.textPrimary, null),
      SxButtonKind.ghostAnchor => (Colors.transparent, p.onAnchor, p.anchorLine),
    };
    final compact = kind == SxButtonKind.signal || kind == SxButtonKind.ghostAnchor;
    final isOption = kind == SxButtonKind.option || kind == SxButtonKind.optionRecommended;
    final full = widget.fullWidth || isOption;
    final style = SxText.label.copyWith(color: fg);
    final Widget? glyph = widget.loading
        ? SxSpin(child: Icon(TablerIcons.loader_2, size: 18, color: fg))
        : widget.icon == null
            ? null
            : Icon(widget.icon, size: 18, color: fg);

    final content = Text.rich(
      TextSpan(children: [
        if (glyph != null)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsets.only(right: SxSpace.s8), child: glyph),
          ),
        TextSpan(text: widget.label),
      ]),
      style: style,
      textAlign: isOption ? TextAlign.start : TextAlign.center,
    );

    final drawn = AnimatedContainer(
      duration: SxMotion.fast,
      curve: SxMotion.curve,
      constraints: BoxConstraints(minHeight: compact ? 36 : 44),
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SxRadius.pill),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Align(
        alignment: isOption ? AlignmentDirectional.centerStart : Alignment.center,
        widthFactor: full ? null : 1,
        heightFactor: 1,
        child: content,
      ),
    );

    return Opacity(
      opacity: widget.onTap == null ? 0.5 : 1,
      child: SxPressable(
        onTap: widget.loading ? null : widget.onTap,
        semanticLabel: widget.semanticLabel,
        onDownChanged: (v) => setState(() => _down = v),
        // A control drawn at 36 keeps its 44 px tap target.
        child: compact ? Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: drawn) : drawn,
      ),
    );
  }
}

/// Two buttons sharing a row at equal width: secondary on the left, primary on the right.
class SxButtonRow extends StatelessWidget {
  const SxButtonRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: SxSpace.s8),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// 44 px circle holding one icon. Always pass a [semanticLabel].
class SxIconButton extends StatelessWidget {
  const SxIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.dot = false,
    this.ghost = false,
    this.onAnchor = false,
    this.child,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  /// 8 px attention dot for unread items.
  final bool dot;

  /// Transparent background.
  final bool ghost;

  /// For anchor surfaces: `anchorRaised` circle with `onAnchor` icon.
  final bool onAnchor;

  /// Replaces [icon], for brand icons.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final bg = ghost ? Colors.transparent : (onAnchor ? p.anchorRaised : p.card);
    final fg = onAnchor ? p.onAnchor : p.textPrimary;
    return SxPressable(
      small: true,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            child ?? Icon(icon, size: 20, color: fg),
            if (dot)
              Positioned(
                top: 11,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: p.attention,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: bg == Colors.transparent ? p.page : bg, spreadRadius: 2)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Back icon button. Pops when it can; opened from a deep link it goes to [fallback]
/// (the prototype's `parent`).
class SxBackButton extends StatelessWidget {
  const SxBackButton({super.key, this.fallback = '/home', this.onTap, this.onAnchor = false});

  final String fallback;
  final VoidCallback? onTap;
  final bool onAnchor;

  @override
  Widget build(BuildContext context) {
    return SxIconButton(
      icon: TablerIcons.arrow_left,
      semanticLabel: 'Back',
      onAnchor: onAnchor,
      onTap: onTap ??
          () {
            final router = GoRouter.of(context);
            if (router.canPop()) {
              router.pop();
            } else {
              router.go(fallback);
            }
          },
    );
  }
}

/// Text link with a 44 px tap area ("See all", "Edit").
class SxLinkButton extends StatelessWidget {
  const SxLinkButton({super.key, required this.label, required this.onTap, this.icon, this.color});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.sx.textPrimary;
    return SxPressable(
      small: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text.rich(
            TextSpan(children: [
              if (icon != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(icon, size: 16, color: fg),
                  ),
                ),
              TextSpan(text: label),
            ]),
            style: SxText.label.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}
