import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';

class SxSegment<T> {
  const SxSegment(this.value, this.label);

  final T value;
  final String label;
}

/// Segmented control with a sliding thumb (`.sx-seg`), equal-width segments.
class SxSegmented<T> extends StatelessWidget {
  const SxSegmented({super.key, required this.segments, required this.value, required this.onChanged});

  final List<SxSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final current = segments.indexWhere((s) => s.value == value);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(SxSpace.s4),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.pill)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth / segments.length;
          return Stack(
            children: [
              if (current >= 0)
                AnimatedPositioned(
                  duration: SxMotion.nav,
                  curve: SxMotion.move,
                  top: 0,
                  bottom: 0,
                  left: w * current,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(SxRadius.pill)),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < segments.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: i == current,
                        child: SxPressable(
                          small: true,
                          haptic: false,
                          onTap: i == current
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  onChanged(segments[i].value);
                                },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: SxMotion.nav,
                              curve: SxMotion.move,
                              style: SxText.label.copyWith(color: i == current ? p.onPrimary : p.textSecondary),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: SxSpace.s8),
                                child: Text(segments[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
