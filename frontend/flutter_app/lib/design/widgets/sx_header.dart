import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_avatar.dart';
import 'sx_button.dart';

/// Root tab header (DESIGN.md 9.4): avatar, greeting over shop name, bell with unread dot.
class SxRootHeader extends StatelessWidget {
  const SxRootHeader({
    super.key,
    required this.greeting,
    required this.shopName,
    this.onAvatarTap,
    this.onBellTap,
    this.unread = false,
  });

  final String greeting;
  final String shopName;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBellTap;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return ConstrainedBox(
      // Grows with large text instead of clipping it.
      constraints: const BoxConstraints(minHeight: SxSpace.headerHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen, vertical: 2),
        child: Row(
          children: [
            SxAvatar(name: shopName, onTap: onAvatarTap),
            const SizedBox(width: SxSpace.s12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.caption.copyWith(color: p.textSecondary)),
                  Text(shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.titleM.copyWith(color: p.textPrimary)),
                ],
              ),
            ),
            const SizedBox(width: SxSpace.s12),
            SxIconButton(
              icon: TablerIcons.bell,
              semanticLabel: unread ? 'Notifications, unread items' : 'Notifications',
              dot: unread,
              onTap: onBellTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail header (DESIGN.md 9.4): back, title over meta, optional trailing icon button.
class SxDetailHeader extends StatelessWidget {
  const SxDetailHeader({
    super.key,
    required this.title,
    this.meta,
    this.metaWidget,
    this.trailing,
    this.fallback = '/home',
    this.onBack,
  });

  final String title;
  final String? meta;

  /// Replaces [meta], for a brand icon and text.
  final Widget? metaWidget;
  final Widget? trailing;

  /// Where back goes when nothing can be popped: pass the prototype's `parent` route.
  final String fallback;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return ConstrainedBox(
      // Grows with large text instead of clipping it.
      constraints: const BoxConstraints(minHeight: SxSpace.headerHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen, vertical: 2),
        child: Row(
          children: [
            SxBackButton(fallback: fallback, onTap: onBack),
            const SizedBox(width: SxSpace.s12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.titleM.copyWith(color: p.textPrimary)),
                  if (metaWidget != null)
                    DefaultTextStyle.merge(
                      style: SxText.caption.copyWith(color: p.textSecondary),
                      child: metaWidget!,
                    )
                  else if (meta != null && meta!.isNotEmpty)
                    Text(meta!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.caption.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: SxSpace.s12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Large page title (`UI.title`): `titleL`, optional caption and trailing widget.
class SxPageTitle extends StatelessWidget {
  const SxPageTitle({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s8, SxSpace.screen, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SxText.titleL.copyWith(color: p.textPrimary)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: SxSpace.s4),
                    child: Text(subtitle!, style: SxText.caption.copyWith(color: p.textSecondary)),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: SxSpace.s12), trailing!],
        ],
      ),
    );
  }
}
