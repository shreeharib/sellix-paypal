import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';

final _meProvider = FutureProvider.autoDispose<Me>((ref) => ref.watch(sellixApiProvider).me());

class ConnectedScreen extends ConsumerStatefulWidget {
  const ConnectedScreen({super.key});

  @override
  ConsumerState<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends ConsumerState<ConnectedScreen> {
  bool _busy = false;

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final completed = await ref.read(onboardingCompletedProvider.future);
      if (mounted) context.go(completed ? Routes.home : Routes.obShop);
    } catch (error) {
      if (mounted) {
        ref.invalidate(onboardingCompletedProvider);
        showSxSnack(context, sxErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(_meProvider);
    return SxScaffold(
      floating: me.hasValue ? SxBottomCta(label: 'Set up my shop', loading: _busy, onTap: _next) : null,
      body: SxAsyncView<Me>(
        value: me,
        onRetry: () => ref.invalidate(_meProvider),
        loading: const SxSkeletonList(topHeight: 160),
        builder: (context, data) => _Joined(me: data),
      ),
    );
  }
}

/// sellix and the shop join. The name comes from the Instagram account: the merchant confirms it in
/// the next step. Final state at once with reduced motion.
class _Joined extends StatefulWidget {
  const _Joined({required this.me});

  final Me me;

  @override
  State<_Joined> createState() => _JoinedState();
}

class _JoinedState extends State<_Joined> with SingleTickerProviderStateMixin {
  static const _total = 1600;
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _total));

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

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

  double _at(int ms, int length, [Curve curve = SxMotion.curve]) =>
      Interval(ms / _total, (ms + length) / _total, curve: curve).transform(_c.value);

  Widget _rise(int i, Widget child) {
    final v = _at(820 + i * 100, 260);
    return Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final shop = widget.me.merchant.name;
    final instagram = widget.me.channels.where((c) => c.channel == 'instagram').firstOrNull;
    final receiving = instagram?.status == 'active';
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final slide = _at(0, 420, SxMotion.move);
        final link = _at(340, 280);
        final check = _at(600, 340, SxMotion.spring);
        return SxScrollList(
          padding: EdgeInsets.fromLTRB(SxSpace.screen, 64, SxSpace.screen, sxBottomInset(context) + SxSpace.s20),
          children: [
            Semantics(
              label: 'sellix and $shop are connected',
              image: true,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 72,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: slide,
                        child: Transform.translate(
                          offset: Offset(-64 * (1 - slide), 0),
                          child: const SxIconTile(size: 72, radius: SxRadius.pill, child: SxLogo(size: 52, surface: SxLogoSurface.card)),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        height: 28,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scaleX: link,
                              child: Container(height: 2, color: p.lineStrong),
                            ),
                            Transform.scale(
                              scale: check,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(color: p.signal, shape: BoxShape.circle),
                                child: Icon(TablerIcons.check, size: 16, color: p.onSignal),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Opacity(
                        opacity: slide,
                        child: Transform.translate(
                          offset: Offset(64 * (1 - slide), 0),
                          child: SxInitialsAvatar(name: shop, size: 72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: SxSpace.s24),
            _rise(
              0,
              Text('sellix × $shop', textAlign: TextAlign.center, style: SxText.titleL.copyWith(color: p.textPrimary)),
            ),
            const SizedBox(height: SxSpace.s8),
            _rise(
              1,
              Text('Integrated with sellix', textAlign: TextAlign.center, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
            ),
            if (instagram?.username != null) ...[
              const SizedBox(height: SxSpace.s4),
              _rise(
                2,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SxBrandIcon(SxBrand.instagram, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '@${instagram!.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.bodyS.copyWith(color: p.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: SxSpace.s12),
            _rise(
              3,
              Center(
                child: receiving
                    ? const SxChip(label: 'Receiving messages', dot: true, pulse: true)
                    : const SxChip(label: 'Instagram is not receiving messages yet', tone: SxChipTone.attention),
              ),
            ),
            const SizedBox(height: SxSpace.s32),
            _rise(
              4,
              SxCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Next: teach sellix your shop', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                    const SizedBox(height: SxSpace.s4),
                    Text(
                      '4 short steps, about 3 minutes. Only your shop’s name and what you sell are needed now. Finish the rest later in Profile.',
                      style: SxText.caption.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: SxSpace.s12),
                    const SxStepsBar(total: 4, current: 0, fraction: 0),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
