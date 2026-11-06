import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';

enum SxBubbleSender { customer, sellix, merchant }

const _tail = Radius.circular(SxRadius.tail);
const _round = Radius.circular(SxRadius.bubble);

/// Chat bubble (DESIGN.md 9.11). Lines up on its own side; max width 75% of the screen.
class SxBubble extends StatelessWidget {
  const SxBubble({
    super.key,
    required this.text,
    required this.sender,
    this.time,
    this.showWho = true,
  });

  final String text;
  final SxBubbleSender sender;
  final String? time;

  /// The "sellix" / "You" label on outgoing bubbles.
  final bool showWho;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final isCustomer = sender == SxBubbleSender.customer;
    final fg = isCustomer ? p.textPrimary : p.onBubbleAi;
    return Align(
      alignment: isCustomer ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isCustomer ? p.bubbleCustomer : p.bubbleAi,
            borderRadius: isCustomer
                ? const BorderRadiusDirectional.only(
                    topStart: _round, topEnd: _round, bottomEnd: _round, bottomStart: _tail)
                : const BorderRadiusDirectional.only(
                    topStart: _round, topEnd: _round, bottomStart: _round, bottomEnd: _tail),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showWho && sender == SxBubbleSender.sellix)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(TablerIcons.sparkles, size: 12, color: p.signalOnAnchor),
                      const SizedBox(width: SxSpace.s4),
                      Text('sellix', style: SxText.micro.copyWith(color: p.signalOnAnchor)),
                    ],
                  ),
                ),
              if (showWho && sender == SxBubbleSender.merchant)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('You', style: SxText.micro.copyWith(color: p.onAnchorSecondary)),
                ),
              Text(text, style: SxText.body.copyWith(color: fg)),
              if (time != null)
                Padding(
                  padding: const EdgeInsets.only(top: SxSpace.s4),
                  child: Text(time!, style: SxText.micro.copyWith(color: fg.withValues(alpha: 0.6))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small link under a bubble ("Show in English").
class SxBubbleLink extends StatelessWidget {
  const SxBubbleLink({super.key, required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SxPressable(
        small: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: SxSpace.s4, right: SxSpace.s8, top: 14, bottom: 14),
          child: Text(label, style: SxText.micro.copyWith(color: active ? p.textPrimary : p.textSecondary)),
        ),
      ),
    );
  }
}

class SxDateSeparator extends StatelessWidget {
  const SxDateSeparator(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(label, style: SxText.micro.copyWith(color: context.sx.textSecondary)),
      );
}

/// Centered event pill in a chat ("Payment received").
class SxSystemEvent extends StatelessWidget {
  const SxSystemEvent(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SxSpace.s12, vertical: 5),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.pill)),
        child: Text.rich(
          TextSpan(children: [
            if (icon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(icon, size: 14, color: p.textSecondary),
                ),
              ),
            TextSpan(text: label),
          ]),
          textAlign: TextAlign.center,
          style: SxText.micro.copyWith(color: p.textSecondary),
        ),
      ),
    );
  }
}

/// Three bouncing dots. Use only for a real in-flight reply, never a fake demo.
class SxTypingBubble extends StatefulWidget {
  const SxTypingBubble({super.key, this.customer = false});

  final bool customer;

  @override
  State<SxTypingBubble> createState() => _SxTypingBubbleState();
}

class _SxTypingBubbleState extends State<SxTypingBubble> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final customer = widget.customer;
    final dotColor = customer ? p.textPrimary : p.onBubbleAi;
    return Semantics(
      label: customer ? 'Customer is typing' : 'sellix is typing',
      child: Align(
        alignment: customer ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.s16, vertical: 14),
          decoration: BoxDecoration(
            color: customer ? p.bubbleCustomer : p.bubbleAi,
            borderRadius: customer
                ? const BorderRadiusDirectional.only(
                    topStart: _round, topEnd: _round, bottomEnd: _round, bottomStart: _tail)
                : const BorderRadiusDirectional.only(
                    topStart: _round, topEnd: _round, bottomStart: _round, bottomEnd: _tail),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: SxSpace.s4),
                  _dot(dotColor, (_c.value - i * 0.136) % 1),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color, double t) {
    // Keyframes: rest until 0, peak at 30%, rest again from 60%.
    final k = t < 0.3 ? t / 0.3 : (t < 0.6 ? (0.6 - t) / 0.3 : 0.0);
    return Transform.translate(
      offset: Offset(0, -3 * k),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.3 + 0.7 * k), shape: BoxShape.circle),
      ),
    );
  }
}

/// Product attachment in a chat (DESIGN.md 9.13). Lines up on the sender's side.
class SxAttachmentCard extends StatelessWidget {
  const SxAttachmentCard({
    super.key,
    required this.leading,
    required this.title,
    this.meta,
    this.outgoing = true,
    this.onTap,
  });

  /// 48 px tile, see `SxIconTile(size: 48)`.
  final Widget leading;
  final String title;
  final String? meta;
  final bool outgoing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final card = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.attach)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SxText.label.copyWith(color: p.textPrimary)),
                if (meta != null) Text(meta!, style: SxText.micro.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: outgoing ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: onTap == null ? card : SxPressable(onTap: onTap, child: card),
      ),
    );
  }
}
