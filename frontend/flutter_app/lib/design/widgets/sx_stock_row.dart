import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';
import 'sx_stepper.dart';

/// DESIGN.md 9.17: tile, name over price or chip, stepper.
class SxStockRow extends StatelessWidget {
  const SxStockRow({
    super.key,
    required this.leading,
    required this.title,
    required this.value,
    required this.onChanged,
    this.price,
    this.chip,
    this.min = 0,
    this.max,
    this.onTap,
  });

  /// 44 px tile, see `SxIconTile`.
  final Widget leading;
  final String title;
  final String? price;

  /// Replaces [price]: "Sold out", "New".
  final Widget? chip;
  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int? max;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final info = Row(
      children: [
        leading,
        const SizedBox(width: SxSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
              if (chip != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: chip)
              else if (price != null)
                Text(price!, style: SxText.caption.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.card)),
      child: Row(
        children: [
          Expanded(child: onTap == null ? info : SxPressable(onTap: onTap, child: info)),
          const SizedBox(width: SxSpace.s8),
          SxStepper(value: value, onChanged: onChanged, min: min, max: max, itemName: title),
        ],
      ),
    );
  }
}
