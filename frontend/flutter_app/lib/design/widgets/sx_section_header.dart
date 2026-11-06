import 'package:flutter/material.dart';

import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_button.dart';
import 'sx_chip.dart';

/// DESIGN.md 9.7: `titleM`, optional count badge, optional link. Padding 24 / 12 / 22.
class SxSectionHeader extends StatelessWidget {
  const SxSectionHeader({super.key, required this.title, this.badge, this.link, this.onLink});

  final String title;
  final int? badge;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final hasLink = link != null;
    return Padding(
      // The link's 44 px target takes up the header's own vertical padding.
      padding: EdgeInsets.fromLTRB(22, hasLink ? 12 : 24, 22, hasLink ? 0 : 12),
      child: Row(
        children: [
          Flexible(child: Text(title, style: SxText.titleM.copyWith(color: context.sx.textPrimary))),
          if ((badge ?? 0) > 0) ...[const SizedBox(width: 8), SxBadge(count: badge!)],
          const Spacer(),
          if (hasLink) SxLinkButton(label: link!, onTap: onLink),
        ],
      ),
    );
  }
}
