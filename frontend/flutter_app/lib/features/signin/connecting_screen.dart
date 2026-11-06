import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'sign_in_flow.dart';

enum _Step { idle, instagram, shop, failed, done }

/// Runs the real sign-in. It lives here because the router leaves this screen alone when the
/// session arrives; anywhere else it would redirect before the shop is ready. Each row ticks only
/// when that part has really happened.
class ConnectingScreen extends ConsumerStatefulWidget {
  const ConnectingScreen({super.key});

  @override
  ConsumerState<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<ConnectingScreen> {
  _Step _step = _Step.idle;
  Me? _me;
  Object? _error;
  late final bool _requested;

  @override
  void initState() {
    super.initState();
    _requested = ref.read(signInFlowProvider).requested;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    ref.read(signInFlowProvider.notifier).takeRequest();
    final auth = await ref.read(authControllerProvider.future);
    if (!mounted) return;
    if (auth == AuthStatus.signedIn) return _setUp();
    // Opened with no sign-in under way, such as the phone restoring this page. Stay and offer it.
    if (!_requested) return;

    setState(() => _step = _Step.instagram);
    try {
      await ref.read(authControllerProvider.notifier).signInWithInstagram();
    } on SignInCancelled {
      if (!mounted) return;
      context.go(Routes.welcome);
      return;
    } catch (error) {
      if (!mounted) return;
      ref.read(signInFlowProvider.notifier).failed(sxErrorMessage(error));
      context.go(Routes.autherror);
      return;
    }
    if (mounted) await _setUp();
  }

  /// The session exists. A failure from here on is a network problem, not a sign-in problem, so it
  /// retries in place: the router would not allow the sign-in error screen any more.
  Future<void> _setUp() async {
    setState(() {
      _step = _Step.shop;
      _error = null;
    });
    HapticFeedback.selectionClick();
    final Me me;
    final bool completed;
    try {
      me = await ref.read(sellixApiProvider).me();
      if (!mounted) return;
      setState(() => _me = me);
      completed = await ref.read(onboardingCompletedProvider.future);
    } catch (error) {
      if (mounted) {
        setState(() {
          _step = _Step.failed;
          _error = error;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _step = _Step.done);
    await Future<void>.delayed(MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 500));
    if (!mounted) return;
    if (!completed) {
      context.go(Routes.connected);
      return;
    }
    // Sign in skips onboarding and opens Home.
    // Just before navigating: a snack this fresh belongs to the screen being opened.
    showSxSnack(context, 'Welcome back, ${me.merchant.name}.', icon: TablerIcons.check);
    context.go(Routes.home);
  }

  void _retry() {
    ref.invalidate(onboardingCompletedProvider);
    _setUp();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final me = _me;
    final handle = me?.channels.where((c) => c.channel == 'instagram').firstOrNull?.username;
    final dmsOn = me?.channels.any((c) => c.channel == 'instagram' && c.status == 'active') ?? false;
    if (_step == _Step.idle && !_requested && ref.read(authControllerProvider).value != AuthStatus.signedIn) {
      return _Interrupted(onTry: () => context.go(Routes.iglogin));
    }
    final waiting = _step == _Step.instagram || _step == _Step.idle;
    final signedIn = !waiting;
    return SxScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  me == null
                      ? const SxIconTile(size: 64, radius: SxRadius.pill, child: SxBrandIcon(SxBrand.instagram, size: 28))
                      : SxInitialsAvatar(name: me.merchant.name, size: 64),
                  const SizedBox(width: SxSpace.s12),
                  _TravellingDots(active: _step != _Step.failed),
                  const SizedBox(width: SxSpace.s12),
                  const SxLogo(size: 52, surface: SxLogoSurface.page),
                ],
              ),
              const SizedBox(height: SxSpace.s32),
              Text(
                waiting ? 'Waiting for Instagram' : 'Setting up your shop',
                textAlign: TextAlign.center,
                style: SxText.titleL.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: SxSpace.s8),
              Text(
                waiting ? 'Log in and allow sellix there, then come back here.' : (handle == null ? 'One moment.' : '@$handle'),
                textAlign: TextAlign.center,
                style: SxText.bodyS.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: SxSpace.s32),
              SxCard(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(
                  children: [
                    _CheckRow(
                      label: 'Checking it is a professional account',
                      state: signedIn ? _Row.done : _Row.doing,
                    ),
                    _CheckRow(
                      label: me != null && !dmsOn ? 'Your DMs are not connected yet' : 'Connecting your DMs',
                      state: me == null ? (signedIn ? _Row.doing : _Row.waiting) : (dmsOn ? _Row.done : _Row.waiting),
                    ),
                    _CheckRow(
                      label: me == null ? 'Creating your shop on sellix' : 'Creating ${me.merchant.name} on sellix',
                      state: me != null && _step != _Step.failed
                          ? _Row.done
                          : (signedIn && _step != _Step.failed ? _Row.doing : _Row.waiting),
                    ),
                  ],
                ),
              ),
              if (_step == _Step.failed) SxErrorState(error: _error, onRetry: _retry),
            ],
          ),
        ),
      ),
    );
  }
}

/// No sign-in is running and none can be resumed.
class _Interrupted extends StatelessWidget {
  const _Interrupted({required this.onTry});

  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    return SxScaffold(
      body: Center(
        child: SxEmptyState(
          icon: TablerIcons.brand_instagram,
          title: 'Instagram is not connected yet',
          body: 'The sign in stopped before it finished.',
          actionLabel: 'Connect Instagram',
          onAction: onTry,
        ),
      ),
    );
  }
}

enum _Row { waiting, doing, done }

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.state});

  final String label;
  final _Row state;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final done = state == _Row.done;
    final fg = state == _Row.waiting ? p.textTertiary : p.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SxSpace.s12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: SxMotion.base,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done ? p.primary : null,
              shape: BoxShape.circle,
              border: done ? null : Border.all(color: state == _Row.doing ? p.textPrimary : p.lineStrong, width: 2),
            ),
            child: done
                ? Icon(TablerIcons.check, size: 16, color: p.onPrimary)
                : state == _Row.doing
                ? SxSpin(child: Icon(TablerIcons.loader_2, size: 16, color: p.textPrimary))
                : null,
          ),
          const SizedBox(width: SxSpace.s12),
          Expanded(child: Text(label, style: SxText.bodyStrong.copyWith(color: fg))),
        ],
      ),
    );
  }
}

class _TravellingDots extends StatefulWidget {
  const _TravellingDots({required this.active});

  final bool active;

  @override
  State<_TravellingDots> createState() => _TravellingDotsState();
}

class _TravellingDotsState extends State<_TravellingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_TravellingDots old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.active && !MediaQuery.disableAnimationsOf(context);
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
    final p = context.sx;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final at = _c.isAnimating ? (_c.value * 4).floor() % 4 : -1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: i == at ? p.signal : p.lineStrong, shape: BoxShape.circle),
              ),
          ],
        );
      },
    );
  }
}
