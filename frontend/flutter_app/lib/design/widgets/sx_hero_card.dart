import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_brand_icon.dart';
import 'sx_pressable.dart';

class SxHeroStat {
  const SxHeroStat({required this.value, required this.label, this.attention = false});

  final String value;
  final String label;

  /// The "Need you" stat: `attentionOnAnchor` when it is above zero.
  final bool attention;
}

/// The one anchor block of Home (DESIGN.md 9.5). Includes its 20 px screen margin.
class SxHeroCard extends StatelessWidget {
  const SxHeroCard({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.status,
    this.channels = const [],
    this.change,
    this.changeUp = true,
    this.sparkline,
    this.stats = const [],
    this.onTap,
  });

  final String label;

  /// Money, already formatted with lib/core/format.dart.
  final String value;

  /// Replaces [value], for [SxCountUp] (style `SxText.display`).
  final Widget? valueWidget;

  /// Usually an [SxLivePill].
  final Widget? status;
  final List<SxBrand> channels;
  final String? change;
  final bool changeUp;

  /// Values for the sparkline. Needs at least two.
  final List<num>? sparkline;
  final List<SxHeroStat> stats;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      padding: const EdgeInsets.all(SxSpace.hero),
      decoration: BoxDecoration(color: p.anchor, borderRadius: BorderRadius.circular(SxRadius.hero)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: status)),
              for (final c in channels)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.livePill, shape: BoxShape.circle),
                    child: SxBrandIcon(c, size: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SxSpace.s20),
          Text(label, style: SxText.caption.copyWith(color: p.onAnchorSecondary)),
          valueWidget ?? Text(value, style: SxText.display.copyWith(color: p.onAnchor)),
          if (change != null)
            Text(change!, style: SxText.caption.copyWith(color: changeUp ? p.signalOnAnchor : p.onAnchorSecondary)),
          if (sparkline != null && sparkline!.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SxSparkline(values: sparkline!),
            ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(height: 1, color: p.anchorLine),
            const SizedBox(height: SxSpace.s16),
            Row(
              children: [
                for (final s in stats)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.value,
                            style: SxText.stat.copyWith(color: s.attention ? p.attentionOnAnchor : p.onAnchor)),
                        Text(s.label, style: SxText.micro.copyWith(color: p.onAnchorSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    return onTap == null ? card : SxPressable(onTap: onTap, child: card);
  }
}

/// Anchor card without the sales layout (`.sx-anchorcard`), e.g. "Set today's stock".
/// Has no margin of its own.
class SxAnchorCard extends StatelessWidget {
  const SxAnchorCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SxSpace.hero),
      decoration: BoxDecoration(color: context.sx.anchor, borderRadius: BorderRadius.circular(SxRadius.hero)),
      child: child,
    );
    return onTap == null ? card : SxPressable(onTap: onTap, child: card);
  }
}

/// Smooth line with a soft area, on anchor surfaces. 44 high, full width.
class SxSparkline extends StatelessWidget {
  const SxSparkline({super.key, required this.values, this.height = 44, this.color});

  final List<num> values;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color ?? context.sx.signalOnAnchor)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final mx = values.reduce((a, b) => a > b ? a : b);
    final mn = values.reduce((a, b) => a < b ? a : b);
    final range = mx == mn ? 1 : mx - mn;
    final dx = size.width / (values.length - 1);
    Offset at(int i) => Offset(i * dx, size.height - 4 - ((values[i] - mn) / range) * (size.height - 10));
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = at(i - 1), b = at(i), cx = (a.dx + b.dx) / 2;
      line.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color || old.values != values;
}
