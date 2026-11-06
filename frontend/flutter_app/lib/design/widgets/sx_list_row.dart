import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';
import 'sx_sheet.dart';
import 'sx_surfaces.dart';

/// Grouped settings list (`.sx-group`): one card, hairlines between its rows.
class SxGroup extends StatelessWidget {
  const SxGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SxRadius.card),
      child: ColoredBox(
        color: SxSheetScope.isOnSheet(context) ? p.page : p.card,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 72, end: SxSpace.card),
                  child: Divider(height: 1, thickness: 1, color: p.line),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A row inside [SxGroup]: min height 60, 40 px tile, title over subtitle, value, chevron.
class SxListRow extends StatelessWidget {
  const SxListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron,
    this.danger = false,
  });

  final String title;
  final String? subtitle;

  /// Right-aligned `caption`.
  final String? value;
  final IconData? icon;

  /// Replaces the icon tile, e.g. `SxBrandIcon`.
  final Widget? leading;

  /// Replaces the value and chevron.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Default: shown when [onTap] is set.
  final bool? chevron;

  /// `errorText` title, for "Sign out" and the like.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final lead = leading ??
        (icon == null
            ? null
            : SxIconTile(
                icon: icon,
                size: 40,
                radius: SxSpace.s12,
                background: SxSheetScope.isOnSheet(context) ? p.card : null,
                foreground: danger ? p.errorText : null,
              ));
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: SxSpace.s12),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: SxSpace.s12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SxText.bodyStrong.copyWith(color: danger ? p.errorText : p.textPrimary)),
                  if (subtitle != null) Text(subtitle!, style: SxText.caption.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            if (trailing != null)
              Padding(padding: const EdgeInsets.only(left: SxSpace.s12), child: trailing)
            else ...[
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: SxSpace.s12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                    child: Text(value!,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.caption.copyWith(color: p.textSecondary)),
                  ),
                ),
              if (chevron ?? onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: SxSpace.s8),
                  child: Icon(TablerIcons.chevron_right, size: 20, color: p.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
    return onTap == null ? row : SxPressable(onTap: onTap, child: row);
  }
}

/// iOS-style toggle, 50 x 30. [signal] uses green for "sellix is doing this".
class SxToggle extends StatelessWidget {
  const SxToggle({super.key, required this.value, required this.onChanged, this.signal = false, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool signal;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: SxPressable(
        small: true,
        haptic: false,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onChanged!(!value);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: AnimatedContainer(
            duration: SxMotion.base,
            curve: SxMotion.curve,
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? (signal ? p.signal : p.primary) : p.lineStrong,
              borderRadius: BorderRadius.circular(SxRadius.pill),
            ),
            child: AnimatedAlign(
              duration: SxMotion.slow,
              curve: SxMotion.spring,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: p.card, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [SxListRow] with an [SxToggle]. Tapping anywhere toggles it.
class SxSwitchRow extends StatelessWidget {
  const SxSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.leading,
    this.signal = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool signal;

  @override
  Widget build(BuildContext context) {
    return SxListRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      leading: leading,
      trailing: SxToggle(value: value, onChanged: onChanged, signal: signal, semanticLabel: title),
    );
  }
}

/// Round (or [square]) check mark, 24 px, spring in.
class SxCheck extends StatelessWidget {
  const SxCheck({super.key, required this.on, this.square = false});

  final bool on;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return AnimatedContainer(
      duration: SxMotion.base,
      curve: SxMotion.curve,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: on ? p.primary : Colors.transparent,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(SxSpace.s8) : null,
        border: on ? null : Border.all(color: p.lineStrong, width: 1.5),
      ),
      child: AnimatedScale(
        scale: on ? 1 : 0,
        duration: SxMotion.slow,
        curve: SxMotion.spring,
        child: Icon(TablerIcons.check, size: 15, color: p.onPrimary),
      ),
    );
  }
}

/// Selectable card (`.sx-choice`), radius 20. Pass [check] to show a mark on the right;
/// the sheet variant of the prototype's menus leaves it off and just uses [onTap].
class SxChoiceCard extends StatelessWidget {
  const SxChoiceCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.leading,
    this.selected = false,
    this.check = false,
    this.squareCheck = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
  final bool check;
  final bool squareCheck;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final bg = SxSheetScope.isOnSheet(context) ? p.page : p.card;
    return SxPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SxMotion.base,
        curve: SxMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SxRadius.bubble),
          border: Border.all(color: selected ? p.textPrimary : bg, width: 1.5),
        ),
        child: Row(
          children: [
            if (leading != null)
              ...[leading!, const SizedBox(width: SxSpace.s12)]
            else if (icon != null)
              ...[Icon(icon, size: 20, color: p.textPrimary), const SizedBox(width: SxSpace.s12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                  if (subtitle != null) Text(subtitle!, style: SxText.caption.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            if (check) ...[const SizedBox(width: SxSpace.s12), SxCheck(on: selected, square: squareCheck)],
          ],
        ),
      ),
    );
  }
}
