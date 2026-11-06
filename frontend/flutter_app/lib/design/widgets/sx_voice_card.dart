import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_motion.dart';
import 'sx_pressable.dart';

/// DESIGN.md 9.16. Only the look: the caller owns recording and transcription.
class SxVoiceCard extends StatelessWidget {
  const SxVoiceCard({
    super.key,
    required this.stateLabel,
    required this.onMic,
    this.stateIcon,
    this.transcript,
    this.placeholder,
    this.listening = false,
    this.micLabel = 'Start speaking',
  });

  /// "Listening", "Tap the mic and speak", "Got it".
  final String stateLabel;

  /// Shown instead of the pulse dot.
  final IconData? stateIcon;
  final String? transcript;
  final String? placeholder;
  final bool listening;
  final VoidCallback? onMic;
  final String micLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final hasText = transcript != null && transcript!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(SxSpace.hero),
      decoration: BoxDecoration(color: p.anchor, borderRadius: BorderRadius.circular(SxRadius.hero)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (stateIcon != null)
                Icon(stateIcon, size: 16, color: p.signalOnAnchor)
              else
                SxPulseDot(pulse: listening),
              const SizedBox(width: SxSpace.s8),
              Expanded(child: Text(stateLabel, style: SxText.caption.copyWith(color: p.signalOnAnchor, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: SxSpace.s12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 69),
            child: Text(
              hasText ? transcript! : (placeholder ?? ''),
              style: SxText.body.copyWith(
                fontSize: 16,
                height: 23 / 16,
                color: hasText ? p.onAnchor : p.onAnchorSecondary,
              ),
            ),
          ),
          const SizedBox(height: SxSpace.s16),
          Row(
            children: [
              Expanded(child: SxWaveform(active: listening)),
              const SizedBox(width: SxSpace.s12),
              _MicButton(listening: listening, onTap: onMic, label: micLabel),
            ],
          ),
        ],
      ),
    );
  }
}

/// Waveform bars: 3 px wide, radius 2. Moves while [active]; flat and silent otherwise.
class SxWaveform extends StatefulWidget {
  const SxWaveform({super.key, required this.active, this.bars = 40});

  final bool active;
  final int bars;

  @override
  State<SxWaveform> createState() => _SxWaveformState();
}

class _SxWaveformState extends State<SxWaveform> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  void _sync() {
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SxWaveform old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return ExcludeSemantics(
      child: ClipRect(
        child: SizedBox(
          height: 40,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: _WavePainter(
                t: _c.value,
                active: widget.active,
                bars: widget.bars,
                on: p.waveActive,
                off: p.waveSilent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.t, required this.active, required this.bars, required this.on, required this.off});

  final double t;
  final bool active;
  final int bars;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final mid = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final x = i * 6.0;
      if (x + 3 > size.width) break;
      final wobble = math.sin(t * 2 * math.pi * 4 + i * 0.5) * math.sin(t * 2 * math.pi + i * 0.13);
      final h = active ? 6 + wobble.abs() * 30 : 6.0;
      paint.color = active && wobble.abs() > 0.15 ? on : off;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h / 2, 3, h), const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.active != active || old.on != on;
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onTap, required this.label});

  final bool listening;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxPressable(
      small: true,
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (listening) ...[const _Ring(delay: 0), const _Ring(delay: 0.5)],
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: p.signal, shape: BoxShape.circle),
              child: Icon(listening ? TablerIcons.player_stop : TablerIcons.microphone, size: 24, color: p.onSignal),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatefulWidget {
  const _Ring({required this.delay});

  final double delay;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SxMotion.pulse)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.sx.signal;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = SxMotion.curve.transform((_c.value + widget.delay) % 1);
        return Transform.scale(
          scale: 1 + 0.55 * t,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.6 * (1 - t)), width: 2),
            ),
          ),
        );
      },
    );
  }
}
