import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'sign_in_flow.dart';
import 'welcome_screen.dart';

/// What Instagram will ask, just before the browser opens. The account and the "Allow" button are
/// on instagram.com itself (PKCE), never drawn here.
class IgLoginScreen extends ConsumerWidget {
  const IgLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    return SxScaffold(
      body: SxScrollList(
        bottomInset: false,
        padding: const EdgeInsets.fromLTRB(SxSpace.screen, 28, SxSpace.screen, SxSpace.s32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SxIconTile(size: 56, radius: SxRadius.pill, child: SxBrandIcon(SxBrand.instagram, size: 24)),
              const SizedBox(width: SxSpace.s12),
              Icon(TablerIcons.dots, size: 20, color: p.textTertiary),
              const SizedBox(width: SxSpace.s12),
              const SxLogo(size: 48, surface: SxLogoSurface.page),
            ],
          ),
          const SizedBox(height: SxSpace.s16),
          Text(
            'sellix wants to connect to your Instagram account',
            textAlign: TextAlign.center,
            style: SxText.titleM.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: SxSpace.s8),
          Text(
            'Instagram opens next. You log in and allow it there.',
            textAlign: TextAlign.center,
            style: SxText.bodyS.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: SxSpace.s20),
          SxFadeUp(child: Text('sellix will be able to', style: SxText.label.copyWith(color: p.textPrimary))),
          const SizedBox(height: SxSpace.s8),
          const SxFadeUp(
            index: 1,
            child: SxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PermissionLine(TablerIcons.message, 'Manage and reply to messages'),
                  PermissionLine(TablerIcons.message_2, 'Read and reply to comments'),
                  PermissionLine(TablerIcons.id_badge_2, 'See your profile name and photo'),
                ],
              ),
            ),
          ),
          const SizedBox(height: SxSpace.s12),
          Text(
            'You can remove access any time in Instagram settings.',
            style: SxText.caption.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: SxSpace.s24),
          SxButtonRow(
            children: [
              SxButton(
                label: 'Cancel',
                kind: SxButtonKind.secondary,
                onTap: () => context.canPop() ? context.pop() : context.go(Routes.welcome),
              ),
              SxButton(
                label: 'Continue',
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ref.read(signInFlowProvider.notifier).request();
                  context.go(Routes.connecting);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
