import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_button.dart';

class SxEscalationOption {
  const SxEscalationOption({required this.label, required this.onTap, this.recommended = false});

  final String label;
  final VoidCallback? onTap;
  final bool recommended;
}

/// DESIGN.md 9.12. Recommended option first; the last option is always "Write my own reply".
class SxEscalationCard extends StatelessWidget {
  const SxEscalationCard({
    super.key,
    required this.body,
    required this.options,
    this.title = 'sellix paused and asks you',
    this.icon,
  });

  final String title;
  final String body;
  final List<SxEscalationOption> options;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      padding: const EdgeInsets.all(SxSpace.card),
      decoration: BoxDecoration(
        color: p.attentionSoft,
        borderRadius: BorderRadius.circular(SxRadius.card),
        border: Border.all(color: p.attentionLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon ?? TablerIcons.hand_stop, size: 18, color: p.attentionText),
              const SizedBox(width: SxSpace.s8),
              Expanded(child: Text(title, style: SxText.label.copyWith(color: p.attentionText))),
            ],
          ),
          const SizedBox(height: SxSpace.s8),
          Text(body, style: SxText.bodyS.copyWith(color: p.attentionTextStrong)),
          const SizedBox(height: 14),
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(height: SxSpace.s8),
            SxButton(
              label: options[i].label,
              onTap: options[i].onTap,
              kind: options[i].recommended ? SxButtonKind.optionRecommended : SxButtonKind.option,
            ),
          ],
        ],
      ),
    );
  }
}
