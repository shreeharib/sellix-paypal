import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_common.dart';

/// Finishes onboarding on the server, then reports what is really true: stock set or not, which
/// channels are connected. Saving again is harmless, so a retry just repeats it.
final _finishProvider = FutureProvider.autoDispose<(Onboarding, Today)>((ref) async {
  final notifier = ref.read(onboardingDraftProvider.notifier);
  await notifier.save(change: (a) => a, complete: true);
  final today = await ref.read(sellixApiProvider).today();
  return (ref.read(onboardingDraftProvider).requireValue, today);
});

class ObLiveScreen extends ConsumerStatefulWidget {
  const ObLiveScreen({super.key});

  @override
  ConsumerState<ObLiveScreen> createState() => _ObLiveScreenState();
}

class _ObLiveScreenState extends ConsumerState<ObLiveScreen> {
  bool _leaving = false;

  /// The redirect sends a shop it thinks is unfinished back to step 1, so refresh first.
  Future<void> _openHome() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      final done = await ref.refresh(onboardingCompletedProvider.future);
      if (!mounted) return;
      if (done) {
        context.go(Routes.home);
      } else {
        showSxSnack(context, 'sellix could not finish your setup. Please try again.');
      }
    } catch (error) {
      if (mounted) showSxSnack(context, sxErrorMessage(error));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finish = ref.watch(_finishProvider);
    return SxScaffold(
      floating: finish.hasValue ? SxBottomCta(label: 'Open home', loading: _leaving, onTap: _openHome) : null,
      body: SxAsyncView<(Onboarding, Today)>(
        value: finish,
        onRetry: () {
          if (ref.read(onboardingDraftProvider).hasError) ref.invalidate(onboardingDraftProvider);
          ref.invalidate(_finishProvider);
        },
        loading: const Center(child: _Ring(animate: false)),
        builder: (context, data) => _LiveBody(onboarding: data.$1, today: data.$2),
      ),
    );
  }
}

class _LiveBody extends StatefulWidget {
  const _LiveBody({required this.onboarding, required this.today});

  final Onboarding onboarding;
  final Today today;

  @override
  State<_LiveBody> createState() => _LiveBodyState();
}

class _LiveBodyState extends State<_LiveBody> {
  bool get _hasStock => widget.today.stock.any((s) => s.available > 0 || s.stockMode == StockMode.unlimited || s.stockMode == StockMode.madeToOrder);
  bool get _live => _hasStock && widget.today.agentEnabled;

  bool _channelOn(String name) => widget.onboarding.channels.any((c) => c.channel == name && c.status == 'active');

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  String get _headline {
    if (!_hasStock) return 'Customer messages wait until you set today’s stock.';
    if (!widget.today.agentEnabled) return 'sellix is switched off. Turn it on from Home.';
    final instagram = _channelOn('instagram');
    final whatsapp = _channelOn('whatsapp');
    if (!instagram && !whatsapp) return 'It starts answering once Instagram is connected.';
    final names = [if (instagram) 'Instagram', if (whatsapp) 'WhatsApp'];
    return 'It is answering your ${names.join(' and ')} DMs now.';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final live = _live;
    return Stack(
      children: [
        SxScrollList(
          padding: EdgeInsets.fromLTRB(SxSpace.screen, 64, SxSpace.screen, sxBottomInset(context) + SxSpace.s20),
          children: [
            const Center(child: _Ring(animate: true)),
            const SizedBox(height: SxSpace.s24),
            SxFadeUp(
              child: Text(
                live ? 'sellix is live' : (_hasStock ? 'sellix is off' : 'sellix is waiting for stock'),
                textAlign: TextAlign.center,
                style: SxText.titleL.copyWith(color: p.textPrimary),
              ),
            ),
            const SizedBox(height: SxSpace.s8),
            SxFadeUp(
              index: 1,
              child: Text(_headline, textAlign: TextAlign.center, style: SxText.bodyS.copyWith(color: p.textSecondary)),
            ),
            const SizedBox(height: SxSpace.s32),
            SxFadeUp(
              index: 2,
              child: SxCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: SxSpace.s12,
                  children: [
                    Text(live ? 'What happens now' : 'What happens next', style: SxText.label.copyWith(color: p.textPrimary)),
                    if (!_hasStock)
                      const _Point(TablerIcons.package, 'Set today’s stock from Home. You can type it or add products one by one.'),
                    _Point(TablerIcons.message_chatbot, '${live ? 'sellix replies' : 'Then sellix replies'}, takes orders and sends payment links.'),
                    const _Point(TablerIcons.hand_stop, 'When it is not sure, it pauses that chat and asks you.'),
                    // BACKEND GAP: no morning stock reminder, so the prototype's "at 8:00 AM it asks" is not promised.
                    const _Point(TablerIcons.calendar, 'Set the stock each morning, so sellix knows what you can sell.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (live) const Positioned.fill(child: IgnorePointer(child: _Confetti())),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: p.textPrimary),
        const SizedBox(width: SxSpace.s12),
        Expanded(child: Text(text, style: SxText.bodyS.copyWith(color: p.textPrimary))),
      ],
    );
  }
}

/// The ring draws in 900 ms, then the mark springs in. Still while [animate] is false.
class _Ring extends StatefulWidget {
  const _Ring({required this.animate});

  final bool animate;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final ring = const Interval(0, 0.75, curve: SxMotion.curve).transform(_c.value);
        final core = const Interval(0.58, 1, curve: SxMotion.spring).transform(_c.value);
        return SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(
            painter: _RingPainter(value: ring, track: p.line, progress: p.signal),
            child: Center(
              child: Transform.scale(
                scale: core,
                child: Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.anchor, shape: BoxShape.circle),
                  child: const SxLogo(size: 50, surface: SxLogoSurface.anchor),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.track, required this.progress});

  final double value;
  final Color track;
  final Color progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      paint..color = progress,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.track != track || old.progress != progress;
}

/// A little confetti when the shop really goes live. Plays once; none with reduced motion.
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_c.isAnimating && _c.value == 0) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _c.isAnimating
          ? CustomPaint(
              painter: _ConfettiPainter(_c.value, [p.signal, p.success, p.attention, p.primary]),
              size: Size.infinite,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.t, this.colors);

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 30; i++) {
      final x = random.nextDouble() * size.width;
      final drift = (random.nextDouble() - 0.5) * 120;
      final turn = random.nextDouble() * 4 * math.pi;
      final speed = 0.6 + random.nextDouble() * 0.4;
      final w = 6 + random.nextDouble() * 6;
      final h = 8 + random.nextDouble() * 10;
      final progress = Curves.easeOut.transform((t / speed).clamp(0.0, 1.0));
      canvas
        ..save()
        ..translate(x + drift * progress, -20 + (size.height + 40) * progress)
        ..rotate(turn * progress)
        ..drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: h), paint..color = colors[i % colors.length])
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
