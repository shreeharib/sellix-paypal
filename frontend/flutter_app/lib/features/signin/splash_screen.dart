import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Shows the brand while the saved session is checked. It never navigates: the router moves on as
/// soon as it knows where the merchant belongs.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1620));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (_c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [ms] to [ms] + [length] of the whole, as 0 to 1.
  double _at(int ms, int length, Curve curve) =>
      Interval(ms / 1620, (ms + length) / 1620, curve: curve).transform(_c.value);

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxScaffold(
      statusOnAnchor: true,
      safeTop: false,
      background: p.anchor,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final mark = _at(0, 520, SxMotion.spring);
          final tagline = _at(1200, 420, SxMotion.curve);
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: _at(0, 300, SxMotion.curve),
                      child: Transform.scale(
                        scale: 0.72 + 0.28 * mark,
                        child: const SxLogo(size: 112, surface: SxLogoSurface.anchor),
                      ),
                    ),
                    const SizedBox(height: SxSpace.s20),
                    Semantics(
                      label: 'sellix',
                      child: ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, letter) in 'sellix'.split('').indexed)
                              Builder(
                                builder: (context) {
                                  final v = _at(880 + i * 40, 380, SxMotion.curve);
                                  return Opacity(
                                    opacity: v,
                                    child: Transform.translate(
                                      offset: Offset(0, 14 * (1 - v)),
                                      child: Text(
                                        letter,
                                        style: SxText.titleL.copyWith(fontSize: 34, color: p.onAnchor),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: tagline,
                      child: Transform.translate(
                        offset: Offset(0, 4 * (1 - tagline)),
                        child: Text(
                          'Your DMs, run like a business.',
                          style: SxText.caption.copyWith(color: p.onAnchorSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 60,
                child: Opacity(opacity: _at(1100, 400, SxMotion.curve), child: const Center(child: SxPulseDot())),
              ),
            ],
          );
        },
      ),
    );
  }
}
