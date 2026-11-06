import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../design/design.dart';

const obStepCount = 4;

/// The answers as the server has them. A PUT replaces every answer, so each step changes this copy
/// and sends all of it.
class OnboardingDraft extends AsyncNotifier<Onboarding> {
  @override
  Future<Onboarding> build() async {
    await ref.watch(authControllerProvider.future);
    return ref.watch(sellixApiProvider).onboarding();
  }

  /// Saves one step. Throws on failure with the draft unchanged, so the step stays on screen.
  Future<void> save({
    String? shopName,
    required OnboardingAnswers Function(OnboardingAnswers answers) change,
    bool complete = false,
  }) async {
    final current = await future;
    final saved = await ref.read(sellixApiProvider).saveOnboarding(
      shopName: shopName ?? current.shopName,
      answers: change(current.answers),
      complete: complete,
    );
    state = AsyncData(saved);
  }
}

final onboardingDraftProvider = AsyncNotifierProvider<OnboardingDraft, Onboarding>(OnboardingDraft.new);

/// Trimmed text, or null so the answer is left out rather than saved empty.
String? obText(String text) {
  final t = text.trim();
  return t.isEmpty ? null : t;
}

/// Back, "Step 1 of 4", Skip, and the progress pills (prototype `obTop`).
class ObTop extends StatelessWidget {
  const ObTop({super.key, required this.step, required this.fraction, required this.fallback, this.onSkip});

  /// 0-based.
  final int step;
  final double fraction;
  final String fallback;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s4, SxSpace.screen, 0),
      child: Column(
        children: [
          Row(
            children: [
              SxBackButton(fallback: fallback),
              Expanded(
                child: Text(
                  'Step ${step + 1} of $obStepCount',
                  textAlign: TextAlign.center,
                  style: SxText.micro.copyWith(color: p.textSecondary),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44),
                child: onSkip == null ? null : SxLinkButton(label: 'Skip', onTap: onSkip, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: SxSpace.s8),
          SxStepsBar(total: obStepCount, current: step, fraction: fraction),
        ],
      ),
    );
  }
}

/// The "why we ask" line under a question.
class ObWhy extends StatelessWidget {
  const ObWhy(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.only(top: SxSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(TablerIcons.info_circle, size: 16, color: p.textSecondary),
          ),
          const SizedBox(width: SxSpace.s8),
          Expanded(child: Text(text, style: SxText.caption.copyWith(color: p.textSecondary))),
        ],
      ),
    );
  }
}

/// A small field label, as `SxField` draws its own.
class ObLabel extends StatelessWidget {
  const ObLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SxSpace.s8),
    child: Text(text, style: SxText.label.copyWith(color: context.sx.textPrimary)),
  );
}

/// A form step: header, loading and error states for the draft, then the form, with the CTA below.
class ObStepFrame extends ConsumerWidget {
  const ObStepFrame({
    super.key,
    required this.step,
    required this.fraction,
    required this.fallback,
    required this.title,
    required this.why,
    required this.children,
    required this.onContinue,
    required this.saving,
    this.onSkip,
    this.ctaLabel = 'Continue',
  });

  final int step;
  final double fraction;
  final String fallback;
  final String title;
  final String why;
  final List<Widget> children;

  /// Null until the draft has loaded.
  final VoidCallback? onContinue;
  final bool saving;
  final VoidCallback? onSkip;
  final String ctaLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final draft = ref.watch(onboardingDraftProvider);
    final ready = draft.hasValue;
    return SxScaffold(
      floating: ready ? SxBottomCta(label: ctaLabel, onTap: onContinue, loading: saving) : null,
      body: Column(
        children: [
          ObTop(step: step, fraction: fraction, fallback: fallback, onSkip: ready ? onSkip : null),
          Expanded(
            child: SxAsyncView<Onboarding>(
              value: draft,
              onRetry: () => ref.invalidate(onboardingDraftProvider),
              loading: const SxSkeletonList(topHeight: 120),
              builder: (context, _) => SxScrollList(
                padding: EdgeInsets.fromLTRB(
                  SxSpace.screen,
                  SxSpace.s20,
                  SxSpace.screen,
                  sxBottomInset(context) + SxSpace.s20,
                ),
                children: [
                  SxFadeUp(child: Text(title, style: SxText.titleL.copyWith(color: p.textPrimary))),
                  SxFadeUp(index: 1, child: ObWhy(why)),
                  ...children,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Saves a step and then moves on; on failure the merchant stays and is told why.
mixin ObSaving<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool saving = false;

  Future<void> saveThen(
    OnboardingAnswers Function(OnboardingAnswers answers) change,
    VoidCallback next, {
    String? shopName,
  }) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await ref.read(onboardingDraftProvider.notifier).save(shopName: shopName, change: change);
      if (mounted) next();
    } catch (error) {
      if (mounted) showSxSnack(context, sxErrorMessage(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
