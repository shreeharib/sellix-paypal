import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';

/// Endless rotation (spinners in buttons and CTAs).
class SxSpin extends StatefulWidget {
  const SxSpin({super.key, required this.child, this.period = const Duration(milliseconds: 900)});

  final Widget child;
  final Duration period;

  @override
  State<SxSpin> createState() => _SxSpinState();
}

class _SxSpinState extends State<SxSpin> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

/// The live dot: a [size] px dot with a slow ring (DESIGN.md 9.6, 1600 ms).
class SxPulseDot extends StatefulWidget {
  const SxPulseDot({super.key, this.size = 7, this.color, this.pulse = true});

  final double size;
  final Color? color;
  final bool pulse;

  @override
  State<SxPulseDot> createState() => _SxPulseDotState();
}

class _SxPulseDotState extends State<SxPulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SxMotion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SxPulseDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.pulse && !MediaQuery.disableAnimationsOf(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.sx.signal;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final t = (_c.value / 0.7).clamp(0.0, 1.0);
              final e = SxMotion.curve.transform(t);
              return Transform.scale(
                scale: 1 + 1.8 * e,
                child: Opacity(opacity: _c.isAnimating ? 0.7 * (1 - e) : 0, child: child),
              );
            },
            child: dot,
          ),
          dot,
        ],
      ),
    );
  }
}

/// Entrance from the prototype's `.stg`: fade up 12 px, 260 ms, staggered 40 ms by [index].
class SxFadeUp extends StatefulWidget {
  const SxFadeUp({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<SxFadeUp> createState() => _SxFadeUpState();
}

class _SxFadeUpState extends State<SxFadeUp> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    Future.delayed(SxMotion.stagger * widget.index.clamp(0, 14), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: SxMotion.curve);
    return FadeTransition(
      opacity: a,
      child: AnimatedBuilder(
        animation: a,
        builder: (_, child) => Transform.translate(offset: Offset(0, 12 * (1 - a.value)), child: child),
        child: widget.child,
      ),
    );
  }
}

/// Number that counts up to [value] on first show and on change. Integer steps only:
/// pass minor units and a formatter, never a float price.
class SxCountUp extends StatelessWidget {
  const SxCountUp({
    super.key,
    required this.value,
    required this.style,
    this.format,
    this.duration = const Duration(milliseconds: 700),
  });

  final int value;
  final TextStyle style;
  final String Function(int value)? format;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final f = format ?? (int v) => '$v';
    if (MediaQuery.disableAnimationsOf(context)) return Text(f(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: duration,
      curve: SxMotion.curve,
      builder: (_, v, _) => Text(f(v.round()), style: style),
    );
  }
}
