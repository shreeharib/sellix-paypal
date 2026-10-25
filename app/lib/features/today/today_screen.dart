import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import 'stock_editor_sheet.dart';
import 'today_providers.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navToday)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStockEditor(context, today.asData?.value.stock ?? const []),
        icon: const Icon(Icons.edit_note),
        label: Text(l10n.todayUpdateStock),
      ),
      body: AsyncView(
        value: today,
        onRetry: () => ref.invalidate(todayProvider),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(todayProvider.future),
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, 96),
              children: [
                Text(
                  DateFormat.MMMMEEEEd(Localizations.localeOf(context).toString())
                      .format(data.businessDate),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Insets.md),
                _AgentSwitch(enabled: data.agentEnabled),
                const SizedBox(height: Insets.md),
                _Numbers(today: data),
                const SizedBox(height: Insets.lg),
                Text(l10n.todayStockTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: Insets.sm),
                if (data.stock.isEmpty)
                  MessageView(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.todayStockEmpty,
                    body: l10n.todayStockEmptyHint,
                  )
                else
                  for (final row in data.stock) ...[
                    _StockTile(row: row),
                    const SizedBox(height: Insets.sm),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentSwitch extends ConsumerStatefulWidget {
  const _AgentSwitch({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_AgentSwitch> createState() => _AgentSwitchState();
}

class _AgentSwitchState extends ConsumerState<_AgentSwitch> {
  bool _saving = false;

  Future<void> _toggle(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).updateMerchant(agentEnabled: enabled);
      ref.invalidate(todayProvider);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: widget.enabled ? colors.primaryContainer : colors.surfaceContainerHighest,
      child: SwitchListTile(
        value: widget.enabled,
        onChanged: _saving ? null : _toggle,
        secondary: Icon(widget.enabled ? Icons.smart_toy : Icons.pause_circle_outline),
        title: Text(l10n.todayAgentSwitchLabel),
        subtitle: Text(widget.enabled ? l10n.todayAgentOn : l10n.todayAgentOff),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Insets.radius)),
      ),
    );
  }
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.today});

  final Today today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final revenue = today.revenueMinorByCurrency.entries
        .map((entry) => formatMoney(entry.value, entry.key))
        .join(' + ');
    final tiles = [
      (l10n.todayOpenQuestions, '${today.openQuestions}', Icons.help_outline),
      (l10n.todayAwaitingPayment, '${today.ordersAwaitingPayment}', Icons.hourglass_top),
      (l10n.todayPaidOrders, '${today.ordersPaid}', Icons.check_circle_outline),
      (l10n.todayRevenue, revenue.isEmpty ? '0' : revenue, Icons.payments_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final width = (constraints.maxWidth - Insets.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final (label, value, icon) in tiles)
              SizedBox(width: width, child: _NumberTile(label: label, value: value, icon: icon)),
          ],
        );
      },
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: Insets.sm),
            Text(value, style: theme.textTheme.headlineSmall),
            Text(label, style: theme.textTheme.bodySmall, maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.row});

  final StockRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final soldOut = row.available == 0;
    return Card(
      child: ListTile(
        title: Text(row.label),
        subtitle: Text(
          '${formatMoney(row.priceMinor, row.currency)}  ·  '
          '${l10n.todayStockBreakdown(row.opening, row.held, row.sold)}',
        ),
        trailing: Text(
          soldOut ? l10n.todaySoldOut : l10n.todayLeft(row.available),
          style: theme.textTheme.titleMedium?.copyWith(
            color: soldOut ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
