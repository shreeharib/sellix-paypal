import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../l10n/app_localizations.dart';

/// Orders, filtered by status ('' = all).
final ordersProvider = FutureProvider.autoDispose.family<List<Order>, String>(
  (ref, status) => ref.watch(sellixApiProvider).orders(status: status.isEmpty ? null : status),
);

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final orders = ref.watch(ordersProvider(_status));
    final filters = [
      ('', l10n.ordersFilterAll),
      ('awaiting_payment', l10n.ordersStatusAwaiting),
      ('paid', l10n.ordersStatusPaid),
      ('expired', l10n.ordersStatusExpired),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navOrders)),
      body: ContentWidth(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
                children: [
                  for (final (value, label) in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.sm),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _status == value,
                        onSelected: (_) => setState(() => _status = value),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncView(
                value: orders,
                onRetry: () => ref.invalidate(ordersProvider(_status)),
                data: (items) => items.isEmpty
                    ? MessageView(
                        icon: Icons.receipt_long_outlined,
                        title: l10n.ordersEmpty,
                        body: l10n.ordersEmptyHint,
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.refresh(ordersProvider(_status).future),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Insets.md, 0, Insets.md, Insets.md),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Insets.sm),
                          itemBuilder: (context, index) => _OrderCard(order: items[index]),
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final details = [
      if (order.fulfilment == 'pickup') l10n.ordersPickup,
      if (order.fulfilment == 'delivery') l10n.ordersDelivery,
      if (order.neededBy != null) l10n.ordersNeededBy(order.neededBy!),
      if (order.status == 'awaiting_payment' && order.holdExpiresAt != null)
        l10n.ordersHeldUntil(formatTime(order.holdExpiresAt!, locale)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.ordersNumber(order.number), style: theme.textTheme.titleMedium)),
                _StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: Insets.sm),
            for (final item in order.items)
              Text('${item.quantity} × ${item.label}  ·  ${formatMoney(item.unitPriceMinor * item.quantity, order.currency)}'),
            const SizedBox(height: Insets.sm),
            Text(formatMoney(order.totalMinor, order.currency), style: theme.textTheme.titleLarge),
            if (details.isNotEmpty) ...[
              const SizedBox(height: Insets.xs),
              Text(
                details.join('  ·  '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (order.deliveryAddress != null) Text(order.deliveryAddress!, style: theme.textTheme.bodySmall),
            if (order.notes != null) Text(order.notes!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, background) = switch (status) {
      'awaiting_payment' => (_label(context.l10n, status), colors.tertiaryContainer),
      'paid' || 'completed' => (_label(context.l10n, status), colors.primaryContainer),
      _ => (_label(context.l10n, status), colors.surfaceContainerHighest),
    };
    return Chip(label: Text(label), backgroundColor: background, side: BorderSide.none);
  }

  static String _label(AppLocalizations l10n, String status) => switch (status) {
        'awaiting_payment' => l10n.ordersStatusAwaiting,
        'paid' => l10n.ordersStatusPaid,
        'expired' => l10n.ordersStatusExpired,
        'cancelled' => l10n.ordersStatusCancelled,
        'completed' => l10n.ordersStatusCompleted,
        'refunded' => l10n.ordersStatusRefunded,
        _ => status,
      };
}
