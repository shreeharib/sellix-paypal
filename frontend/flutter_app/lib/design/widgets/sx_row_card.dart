import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';
import 'sx_surfaces.dart';

/// DESIGN.md 9.8: card with icon tile, title over meta, chevron.
class SxRowCard extends StatelessWidget {
  const SxRowCard({
    super.key,
    required this.title,
    this.meta,
    this.metaWidget,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = true,
    this.outlined = false,
  });

  final String title;
  final String? meta;
  final Widget? metaWidget;
  final IconData? icon;

  /// Replaces the icon tile.
  final Widget? leading;

  /// Replaces the chevron.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  /// Transparent with a 1.5 px `lineStrong` edge, for "add" rows.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final lead = leading ?? (icon == null ? null : SxIconTile(icon: icon));
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: 14),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : p.card,
        borderRadius: BorderRadius.circular(SxRadius.card),
        border: outlined ? Border.all(color: p.lineStrong, width: 1.5) : null,
      ),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: SxSpace.s12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                if (metaWidget != null)
                  DefaultTextStyle.merge(style: SxText.caption.copyWith(color: p.textSecondary), child: metaWidget!)
                else if (meta != null)
                  Text(meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(left: SxSpace.s12), child: trailing)
          else if (chevron && onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: SxSpace.s12),
              child: Icon(TablerIcons.chevron_right, size: 20, color: p.textSecondary),
            ),
        ],
      ),
    );
    return onTap == null ? card : SxPressable(onTap: onTap, child: card);
  }
}
