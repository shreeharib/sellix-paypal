import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../today/today_providers.dart';

/// The tabs: a bottom bar on phones, a side rail on wide screens.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _select(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final openQuestions = ref.watch(todayProvider).asData?.value.openQuestions ?? 0;
    final destinations = [
      (Icons.today_outlined, Icons.today, l10n.navToday, 0),
      (Icons.help_outline, Icons.help, l10n.navAskMe, openQuestions),
      (Icons.receipt_long_outlined, Icons.receipt_long, l10n.navOrders, 0),
      (Icons.chat_bubble_outline, Icons.chat_bubble, l10n.navChats, 0),
      (Icons.settings_outlined, Icons.settings, l10n.navSettings, 0),
    ];

    Widget icon(IconData data, int badge) =>
        badge > 0 ? Badge.count(count: badge, child: Icon(data)) : Icon(data);

    if (MediaQuery.sizeOf(context).width >= Insets.wideLayout) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (outlined, filled, label, badge) in destinations)
                  NavigationRailDestination(
                    icon: icon(outlined, badge),
                    selectedIcon: icon(filled, badge),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final (outlined, filled, label, badge) in destinations)
            NavigationDestination(
              icon: icon(outlined, badge),
              selectedIcon: icon(filled, badge),
              label: label,
            ),
        ],
      ),
    );
  }
}
