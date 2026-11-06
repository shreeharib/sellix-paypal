import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'order_actions.dart';
import 'order_logic.dart';

/// One order: used in the Orders list and the customer's history.
class OrderRow extends StatelessWidget {
  const OrderRow({
    super.key,
    required this.order,
    required this.name,
    this.quick = false,
    this.compact = false,
  });

  final Order order;
  final String name;

  /// Shows the next step on the row, in the To do tab.
  final bool quick;

  /// Leaves the hint line out.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final look = lookOf(order);
    final closed = order.status == OrderStatus.expired || order.status == OrderStatus.cancelled;
    final due = dueText(order);
    final cta = quick ? orderCtaOf(order) : null;
    final hint = nextHint(order, name);
    return SxCard(
      onTap: () => context.push(Routes.order(order.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SxSpace.s8,
        children: [
          Row(
            spacing: SxSpace.s12,
            children: [
              SxIconTile(icon: closed ? TablerIcons.receipt_off : TablerIcons.package),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: SxSpace.s8,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                          ),
                        ),
                        Text(
                          money(order.totalMinor, order.currency),
                          style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      '#${order.number} · ${channelName(order.channel)} · ${itemsLine(order)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SxChip(label: look.label, tone: look.tone, icon: look.icon),
              ?payChipOf(order),
            ],
          ),
          if (due != null)
            Row(
              spacing: 6,
              children: [
                Icon(methodIcon(methodOf(order)), size: 16, color: p.textSecondary),
                Expanded(
                  child: Text(due, style: SxText.bodyS.copyWith(color: p.textSecondary)),
                ),
              ],
            ),
          if (cta != null)
            _QuickButton(
              label: cta.label,
              icon: cta.icon,
              onTap: () => runOrderNext(context, order, name),
            )
          else if (!compact && hint.isNotEmpty)
            Text(hint, style: SxText.caption.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}

/// The payment chip beside the state chip, or null when the state already says it.
SxChip? payChipOf(Order order) {
  if (isRefundDue(order)) return null;
  if (order.paymentStatus == 'partially_refunded') {
    return const SxChip(label: 'Part refunded', icon: TablerIcons.arrow_back_up);
  }
  if (order.status == OrderStatus.refunded) return null;
  if (order.paymentStatus == 'paid') {
    return const SxChip(label: 'Paid', tone: SxChipTone.positive, icon: TablerIcons.check);
  }
  if (order.status == OrderStatus.expired || order.status == OrderStatus.cancelled) {
    return const SxChip(label: 'Not paid');
  }
  return null;
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxPressable(
      small: true,
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: SxSheetScope.isOnSheet(context) ? p.card : p.tile,
          borderRadius: BorderRadius.circular(SxRadius.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: SxSpace.s8,
          children: [
            Icon(icon, size: 20, color: p.textPrimary),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: SxText.label.copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
