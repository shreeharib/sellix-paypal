import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';

const _tiles = [
  TablerIcons.hanger,
  TablerIcons.diamond,
  TablerIcons.plant_2,
  TablerIcons.shoe,
  TablerIcons.gift,
  TablerIcons.droplet,
  TablerIcons.shopping_bag,
  TablerIcons.lamp,
];

/// What sellix does, in general words. No customer names, products or amounts: nobody has a shop yet.
const _notes = [
  (TablerIcons.shopping_bag, 'New order', 'sellix took it in the DM', 'Order'),
  (TablerIcons.language, 'sellix replied', 'In your customer’s language', 'Tamil'),
  (TablerIcons.credit_card, 'Paid by PayPal', 'sellix marked the order paid', 'Paid'),
];

enum _Mode { up, into }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.up;

  void _instagram() {
    HapticFeedback.mediumImpact();
    // Signing back in needs no introduction. A new shop first hears what connecting does.
    context.push(_mode == _Mode.up ? Routes.welcome : Routes.iglogin);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final verb = _mode == _Mode.up ? 'Sign up' : 'Sign in';
    return SxScaffold(
      statusOnAnchor: true,
      safeTop: false,
      background: p.card,
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            const Expanded(child: _Hero()),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.74),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(SxRadius.sheet)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    SxSpace.screen,
                    18,
                    SxSpace.screen,
                    SxSpace.s16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SxSegmented<_Mode>(
                        segments: const [SxSegment(_Mode.up, 'Create account'), SxSegment(_Mode.into, 'Sign in')],
                        value: _mode,
                        onChanged: (v) => setState(() => _mode = v),
                      ),
                      const SizedBox(height: SxSpace.s16),
                      _AuthButton(
                        label: '$verb with Instagram',
                        leading: const SxBrandIcon(SxBrand.instagram),
                        primary: true,
                        onTap: _instagram,
                      ),
                      // BACKEND GAP: the API signs in with Instagram only (ADR 0004). No Google, Apple or email.
                      const SizedBox(height: 10),
                      _AuthButton(label: '$verb with Google', leading: const SxBrandIcon(SxBrand.google), onTap: null),
                      const SizedBox(height: 10),
                      _AuthButton(
                        label: '$verb with Apple',
                        leading: SxBrandIcon(SxBrand.apple, color: p.textPrimary),
                        onTap: null,
                      ),
                      const SizedBox(height: 10),
                      _AuthButton(
                        label: '$verb with email',
                        leading: Icon(TablerIcons.mail, size: 20, color: p.textPrimary),
                        onTap: null,
                      ),
                      const SizedBox(height: SxSpace.s12),
                      Text(
                        'Google, Apple and email are not available yet. Use Instagram for now.',
                        textAlign: TextAlign.center,
                        style: SxText.caption.copyWith(color: p.textSecondary),
                      ),
                      const SizedBox(height: SxSpace.s8),
                      // BACKEND GAP: no Terms or Privacy policy URL to link to.
                      Text(
                        'By continuing, you agree to sellix’s Terms and Privacy policy.',
                        textAlign: TextAlign.center,
                        style: SxText.caption.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.label, required this.leading, required this.onTap, this.primary = false});

  final String label;
  final Widget leading;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final fg = primary ? p.onPrimary : p.textPrimary;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: SxPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.s16, vertical: SxSpace.s8),
          decoration: BoxDecoration(
            color: primary ? p.primary : null,
            border: primary ? null : Border.all(color: p.lineStrong),
            borderRadius: BorderRadius.circular(SxRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 10),
              Flexible(child: Text(label, style: SxText.labelL.copyWith(color: fg))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final top = MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: ColoredBox(
        color: p.anchor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tall = constraints.maxHeight >= 330;
            return Stack(
              children: [
                Positioned(
                  left: -40,
                  right: -40,
                  top: -30,
                  bottom: -60,
                  child: ExcludeSemantics(
                    child: Transform.rotate(
                      angle: -0.14,
                      child: GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: SxSpace.s12,
                        crossAxisSpacing: SxSpace.s12,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (var i = 0; i < 28; i++)
                            Container(
                              decoration: BoxDecoration(
                                color: p.livePill.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(SxRadius.card),
                              ),
                              child: Icon(_tiles[i % _tiles.length], size: 34, color: p.livePill.withValues(alpha: 0.42)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.22, 0.42, 0.78],
                        colors: [
                          p.anchor.withValues(alpha: 0.55),
                          p.anchor.withValues(alpha: 0),
                          p.anchor.withValues(alpha: 0),
                          p.anchor,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: SxSpace.screen,
                  top: top + SxSpace.s12,
                  child: Row(
                    children: [
                      const SxLogo(size: 34, surface: SxLogoSurface.photo),
                      const SizedBox(width: SxSpace.s8),
                      Text('sellix', style: SxText.titleM.copyWith(color: p.livePill)),
                    ],
                  ),
                ),
                if (tall)
                  Positioned(
                    left: SxSpace.screen,
                    right: SxSpace.screen,
                    top: top + 64,
                    child: const _NoteCycle(),
                  ),
                Positioned(
                  left: SxSpace.screen,
                  right: SxSpace.screen,
                  bottom: SxSpace.s40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You run the shop.\nWe handle your DM',
                        style: SxText.titleL.copyWith(fontSize: 34, height: 38 / 34, color: p.onAnchor),
                      ),
                      if (tall) ...[
                        const SizedBox(height: 10),
                        Text(
                          'sellix replies, takes orders and collects payment while you run your shop.',
                          style: SxText.body.copyWith(color: p.onAnchorSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One card at a time, changing every 2.8 s. A still card with reduced motion.
class _NoteCycle extends StatefulWidget {
  const _NoteCycle();

  @override
  State<_NoteCycle> createState() => _NoteCycleState();
}

class _NoteCycleState extends State<_NoteCycle> {
  Timer? _timer;
  int _at = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) => setState(() => _at++));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final (icon, title, body, tag) = _notes[_at % _notes.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: SxMotion.spring,
      switchOutCurve: SxMotion.curve,
      child: Container(
        key: ValueKey(_at),
        padding: const EdgeInsets.fromLTRB(10, 10, SxSpace.s12, 10),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22)),
        child: Row(
          children: [
            SxIconTile(icon: icon),
            const SizedBox(width: SxSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxText.label.copyWith(color: p.textPrimary)),
                  Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxText.caption.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: SxSpace.s8),
            SxChip(label: tag, tone: SxChipTone.positive),
          ],
        ),
      ),
    );
  }
}
