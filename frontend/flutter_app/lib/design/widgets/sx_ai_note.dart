import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_sheet.dart';

/// DESIGN.md 9.10: what sellix did and why, in first person.
class SxAiNote extends StatelessWidget {
  const SxAiNote(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.s12, vertical: 10),
      decoration: BoxDecoration(
        color: SxSheetScope.isOnSheet(context) ? p.page : p.tile,
        borderRadius: BorderRadius.circular(SxRadius.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? TablerIcons.sparkles, size: 16, color: p.noteText),
          ),
          const SizedBox(width: SxSpace.s8),
          Expanded(child: Text(text, style: SxText.caption.copyWith(color: p.noteText))),
        ],
      ),
    );
  }
}
