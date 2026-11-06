import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_ai_note.dart';
import 'sx_avatar.dart';
import 'sx_brand_icon.dart';
import 'sx_button.dart';
import 'sx_chip.dart';

/// DESIGN.md 9.9. Button row: secondary left, primary right.
class SxNeedsYouCard extends StatelessWidget {
  const SxNeedsYouCard({
    super.key,
    required this.name,
    required this.reason,
    required this.message,
    this.meta,
    this.channel,
    this.reasonIcon,
    this.note,
    this.secondaryLabel,
    this.onSecondary,
    this.primaryLabel,
    this.onPrimary,
    this.extra,
  });

  final String name;

  /// Channel and time, e.g. "Instagram, 2 min ago".
  final String? meta;
  final SxBrand? channel;
  final String reason;
  final IconData? reasonIcon;

  /// The customer's message; the quotes are added here.
  final String message;

  /// sellix's note, first person.
  final String? note;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      padding: const EdgeInsets.all(SxSpace.card),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SxCustomerAvatar(name: name, needsYou: true, channel: channel),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                    if (meta != null)
                      Text(meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxText.micro.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: SxSpace.s8),
              Flexible(child: SxChip(label: reason, tone: SxChipTone.attention, icon: reasonIcon)),
            ],
          ),
          const SizedBox(height: SxSpace.s12),
          Text('“$message”', style: SxText.bodyS.copyWith(color: p.textPrimary)),
          if (note != null) ...[const SizedBox(height: 10), SxAiNote(note!)],
          if (secondaryLabel != null || primaryLabel != null) ...[
            const SizedBox(height: SxSpace.s12),
            SxButtonRow(
              children: [
                if (secondaryLabel != null)
                  SxButton(label: secondaryLabel!, kind: SxButtonKind.secondary, onTap: onSecondary),
                if (primaryLabel != null) SxButton(label: primaryLabel!, onTap: onPrimary),
              ],
            ),
          ],
          ?extra,
        ],
      ),
    );
  }
}
