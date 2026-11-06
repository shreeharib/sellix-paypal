import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'sign_in_flow.dart';

/// Explains the real reason sign-in failed, from the message the server sent back.
class AuthErrorScreen extends ConsumerStatefulWidget {
  const AuthErrorScreen({super.key});

  @override
  ConsumerState<AuthErrorScreen> createState() => _AuthErrorScreenState();
}

class _AuthErrorScreenState extends ConsumerState<AuthErrorScreen> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && _shake.value == 0) {
      Future<void>.delayed(SxMotion.slow, () {
        if (mounted) _shake.forward();
      });
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final message = ref.watch(signInFlowProvider).error ?? 'Something went wrong. Please try again.';
    final lower = message.toLowerCase();
    // Matches the wording in backend/app/modules/channels/service.py. If that changes, the merchant
    // still reads the server's own message, under the general title.
    final notAllowed = lower.contains('professional') || lower.contains('didn\'t allow') || lower.contains('didn’t allow');
    final linked = lower.contains('another shop');
    final title = notAllowed
        ? 'Instagram did not allow this account'
        : linked
        ? 'This account is on another shop'
        : 'Instagram was not connected';
    return SxScaffold(
      floating: SxBottomCta(
        label: 'Try again',
        icon: TablerIcons.refresh,
        onTap: () => context.go(Routes.iglogin),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SxDetailHeader(title: '', fallback: Routes.welcome),
          Expanded(
            child: SxScrollList(
              padding: EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s12, SxSpace.screen, sxBottomInset(context)),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      final t = _shake.value;
                      return Transform.translate(offset: Offset(6 * (1 - t) * math.sin(t * 6 * math.pi), 0), child: child);
                    },
                    child: SxIconTile(
                      icon: TablerIcons.user_x,
                      size: 56,
                      radius: 18,
                      background: p.errorSoft,
                      foreground: p.errorText,
                    ),
                  ),
                ),
                const SizedBox(height: SxSpace.s20),
                Text(title, style: SxText.titleL.copyWith(color: p.textPrimary)),
                const SizedBox(height: SxSpace.s8),
                Text(message, style: SxText.bodyS.copyWith(color: p.textSecondary)),
                if (notAllowed) ...[
                  const SizedBox(height: SxSpace.s24),
                  SxCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: SxSpace.s12,
                      children: [
                        Text('Switch in one minute', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                        for (final (i, step) in const [
                          'Open Instagram and go to Settings',
                          'Tap “Account type and tools”',
                          'Tap “Switch to professional account”',
                        ].indexed)
                          Row(
                            children: [
                              SxIconTile(
                                size: 28,
                                radius: SxRadius.pill,
                                child: Text('${i + 1}', style: SxText.label.copyWith(color: p.textPrimary)),
                              ),
                              const SizedBox(width: SxSpace.s12),
                              Expanded(child: Text(step, style: SxText.bodyS.copyWith(color: p.textPrimary))),
                            ],
                          ),
                        const SxAiNote('Your posts, followers and DMs stay the same.'),
                      ],
                    ),
                  ),
                ],
                if (notAllowed || linked) ...[
                  const SizedBox(height: SxSpace.s16),
                  Center(
                    child: SxLinkButton(label: 'Use another account', onTap: () => context.go(Routes.iglogin)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
