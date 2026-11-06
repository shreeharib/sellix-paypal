import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../design/design.dart';
import '../design/widgets/sx_snack.dart' show SxSnackHost;
import 'nav_badges.dart';

/// The five root tabs with the floating nav over them.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with SingleTickerProviderStateMixin {
  late final _tabIn = AnimationController(vsync: this, duration: SxMotion.base, value: 1);
  late final _curve = CurvedAnimation(parent: _tabIn, curve: SxMotion.curve);

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    if (old.shell.currentIndex != widget.shell.currentIndex && !MediaQuery.disableAnimationsOf(context)) {
      _tabIn.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _tabIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final badges = ref.watch(navBadgesProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.sx.page,
      body: Stack(
        children: [
          // Tab change: fade up 8 px in 200 ms.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _curve,
              builder: (_, child) => Opacity(
                opacity: _curve.value,
                child: Transform.translate(offset: Offset(0, 8 * (1 - _curve.value)), child: child),
              ),
              child: shell,
            ),
          ),
          Positioned(
            left: SxSpace.screen,
            right: SxSpace.screen,
            bottom: bottom + SxSpace.navGap,
            child: SxFloatingNav(
              currentIndex: shell.currentIndex,
              onTap: (i) {
                SxSnackHost.clearOnNavigation();
                shell.goBranch(i, initialLocation: i == shell.currentIndex);
              },
              items: [
                const SxNavItem(icon: TablerIcons.home, label: 'Home'),
                SxNavItem(
                  icon: TablerIcons.message_circle,
                  label: 'Chats',
                  badge: badges.chatsNeedYou,
                  liveDot: badges.chatsLive,
                  badgeWord: 'need you',
                ),
                const SxNavItem(icon: TablerIcons.package, label: 'Stock'),
                SxNavItem(
                  icon: TablerIcons.receipt,
                  label: 'Orders',
                  badge: badges.ordersToAct,
                  badgeWord: 'to handle',
                ),
                const SxNavItem(icon: TablerIcons.user, label: 'Profile'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
