import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';

/// Loading block with a moving shine (DESIGN.md 9.22). Match the real content's shape.
class SxSkeleton extends StatefulWidget {
  const SxSkeleton({super.key, this.width, this.height = 16, this.radius = SxSpace.s8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SxSkeleton> createState() => _SxSkeletonState();
}

class _SxSkeletonState extends State<SxSkeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final shine = p.card.withValues(alpha: 0.55);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.width ?? double.infinity,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final x = -1 + 2 * _c.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: p.skeleton,
                  gradient: LinearGradient(
                    begin: Alignment(x * 2 - 1, 0),
                    end: Alignment(x * 2 + 1, 0),
                    colors: [p.skeleton, shine, p.skeleton],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A list of card-shaped skeletons: the default loading state of [SxAsyncView].
class SxSkeletonList extends StatelessWidget {
  const SxSkeletonList({super.key, this.count = 5, this.itemHeight = 76, this.topHeight});

  final int count;
  final double itemHeight;

  /// Optional larger block on top, for a hero card.
  final double? topHeight;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen, vertical: SxSpace.s12),
      child: Column(
        children: [
          if (topHeight != null) ...[
            SxSkeleton(height: topHeight!, radius: SxRadius.hero),
            const SizedBox(height: SxSpace.stackGap),
          ],
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: SxSpace.listGap),
            SxSkeleton(height: itemHeight, radius: SxRadius.card),
          ],
        ],
      ),
    );
  }
}
