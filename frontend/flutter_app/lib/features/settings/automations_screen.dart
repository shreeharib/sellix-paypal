import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'automation_widgets.dart';
import 'automations_store.dart';
import 'saved_rules.dart';
import 'settings_providers.dart';

// BACKEND GAP: no automation endpoints. See automations_store.dart. The prototype's weekly hero
// (chats handled, replies, orders, recovered) and each card's number have no source, so they are gone.
class AutomationsScreen extends ConsumerWidget {
  const AutomationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automations = ref.watch(automationsProvider);
    return SxScaffold(
      floating: automations.hasValue
          ? SxBottomCta(
              label: 'New automation',
              icon: TablerIcons.plus,
              onTap: () => context.push(Routes.newauto),
            )
          : null,
      body: Column(
        children: [
          const SxDetailHeader(title: 'Automations', meta: 'What sellix does on its own', fallback: Routes.profile),
          Expanded(
            child: SxAsyncView<List<Automation>>(
              value: automations,
              onRetry: () => ref
                ..invalidate(shopProfileProvider)
                ..invalidate(meProvider),
              loading: const SxSkeletonList(topHeight: 160, itemHeight: 140),
              builder: (context, list) => _list(context, ref, list),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<Automation> all) {
    final visible = visibleAutomations(all);
    final optional = visible.where((a) => !a.locked).length;
    final agentOn = ref.watch(meProvider).value?.merchant.agentEnabled ?? true;
    final profile = ref.watch(shopProfileProvider);
    final rules = profile.hasValue ? parseSavedRules(profile.value?.contentMd).length : null;

    Widget group(AutomationGroup which, int base) {
      final items = visible.where((a) => a.group == which).toList();
      return Mx(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: SxSpace.s8,
          children: [
            for (final (i, a) in items.indexed)
              SxFadeUp(index: base + i, child: AutomationCard(automation: a)),
          ],
        ),
      );
    }

    return SxScrollList(
      onRefresh: () async {
        ref
          ..invalidate(shopProfileProvider)
          ..invalidate(meProvider);
        await ref.read(meProvider.future);
      },
      children: [
        const Mx(child: SxLocalOnlyNote()),
        const SizedBox(height: SxSpace.s12),
        SxFadeUp(
          child: SxHeroCard(
            status: SxLivePill(state: agentOn ? SxAgentState.live : SxAgentState.paused),
            label: 'Switched on, not active yet',
            value: '${chosenAutomations(visible)} of $optional',
          ),
        ),
        const SxSectionHeader(title: 'Always on'),
        group(AutomationGroup.core, 1),
        const SxSectionHeader(title: 'Grow sales'),
        group(AutomationGroup.grow, 6),
        SxSectionHeader(title: 'Your rules', link: 'See all', onLink: () => context.push(Routes.rules)),
        Mx(
          child: SxRowCard(
            icon: TablerIcons.bookmark,
            title: rules == null ? 'Saved answers' : '$rules saved answer${rules == 1 ? '' : 's'}',
            meta: 'sellix uses these instead of asking you',
            onTap: () => context.push(Routes.rules),
          ),
        ),
      ],
    );
  }
}
