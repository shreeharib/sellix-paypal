import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_button.dart';
import 'sx_motion.dart';

/// DESIGN.md 9.15. Includes its screen margin (4 / 20 / 12).
class SxTakeoverStrip extends StatelessWidget {
  const SxTakeoverStrip({
    super.key,
    required this.sellixOn,
    required this.onToggle,
    this.sellixOnLabel = 'sellix is on this chat',
    this.youOnLabel = 'You are on this chat',
    this.takeOverLabel = 'Take over',
    this.giveBackLabel = 'Give back to sellix',
    this.loading = false,
  });

  final bool sellixOn;
  final VoidCallback? onToggle;
  final String sellixOnLabel;
  final String youOnLabel;
  final String takeOverLabel;
  final String giveBackLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      margin: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s4, SxSpace.screen, SxSpace.s12),
      padding: const EdgeInsets.fromLTRB(SxSpace.s16, 2, 6, 2),
      decoration: BoxDecoration(color: p.anchor, borderRadius: BorderRadius.circular(SxRadius.pill)),
      child: Row(
        children: [
          if (sellixOn) ...[const SxPulseDot(), const SizedBox(width: SxSpace.s8)],
          Expanded(
            child: Text(
              sellixOn ? sellixOnLabel : youOnLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SxText.caption.copyWith(color: p.onAnchor),
            ),
          ),
          const SizedBox(width: SxSpace.s8),
          Flexible(
            child: SxButton(
              label: sellixOn ? takeOverLabel : giveBackLabel,
              kind: sellixOn ? SxButtonKind.signal : SxButtonKind.ghostAnchor,
              loading: loading,
              onTap: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}
