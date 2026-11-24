import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import 'order_actions.dart';
import 'order_logic.dart';
import 'order_row.dart';
import 'orders_providers.dart';

/// One order. [orderId] comes from the route; the order is fetched by id, so any order opens.
class OrderScreen extends ConsumerWidget {
  const OrderScreen(this.orderId, {super.key});

  final String orderId;

  Future<void> _reload(WidgetRef ref) {
    ref
      ..invalidate(orderTimelineProvider(orderId))
      ..invalidate(orderPaymentsProvider(orderId))
      ..invalidate(conversationsProvider)
      ..invalidate(ordersProvider);
    return ref.refresh(orderProvider(orderId).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(orderProvider(orderId));
    final order = value.value;
    // The latest orders only count this customer's paid orders; the order itself never waits on them.
    final recent = ref.watch(ordersProvider).value;
    final payments = ref.watch(orderPaymentsProvider(orderId)).value;
    final handles = handlesById(ref.watch(conversationsProvider).value ?? const []);
    final name = order == null ? unknownCustomer : customerNameOf(order, handles);
    final cta = order == null ? null : orderCtaOf(order);
    final events = ref.watch(orderTimelineProvider(orderId));
    return SxScaffold(
      floating: cta == null
          ? null
          : SxBottomCta(
              label: cta.label,
              icon: cta.icon,
              onTap: () => runOrderNext(context, order!, name),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxDetailHeader(
            title: order == null ? 'Order' : 'Order #${order.number}',
            meta: order == null
                ? null
                : '${dayLabel(order.createdAt)}, ${formatTime(order.createdAt)} · '
                      'via ${channelName(order.channel)}',
            fallback: Routes.orders,
            trailing: order == null
                ? null
                : SxIconButton(
                    icon: TablerIcons.dots_vertical,
                    semanticLabel: 'Order actions',
                    onTap: () => showOrderMenu(
                      context,
                      order,
                      name,
                      lastChange: events.value?.lastOrNull?.createdAt,
                      payments: payments,
                    ),
                  ),
          ),
          Expanded(
            child: SxAsyncView<Order?>(
              value: value,
              onRetry: () => ref.invalidate(orderProvider(orderId)),
              loading: const SxSkeletonList(topHeight: 160),
              isEmpty: (o) => o == null,
              empty: const SxEmptyState(
                icon: TablerIcons.receipt_off,
                title: 'Order not found',
                body: 'It may have been deleted, or it belongs to another shop.',
              ),
              builder: (context, found) => SxScrollList(
                onRefresh: () => _reload(ref),
                children: [
                  _OrderBody(order: found!, name: name, orderCount: _paidCount(recent ?? [found], found)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static int _paidCount(List<Order> orders, Order order) => order.conversationId == null
      ? 0
      : orders.where((o) => o.conversationId == order.conversationId && countsAsSale(o)).length;
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.order, required this.name, required this.orderCount});

  final Order order;
  final String name;
  final int orderCount;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final look = lookOf(order);
    final conversation = order.conversationId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s4, SxSpace.screen, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxFadeUp(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: SxSpace.s4,
              children: [
                Wrap(
                  spacing: SxSpace.s12,
                  runSpacing: SxSpace.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      money(order.totalMinor, order.currency),
                      style: SxText.display.copyWith(color: p.textPrimary),
                    ),
                    SxChip(label: look.label, tone: look.tone, icon: look.icon),
                  ],
                ),
                Text(nextHint(order, name), style: SxText.bodyS.copyWith(color: p.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: SxSpace.s16),
          SxFadeUp(index: 1, child: SxCard(child: _Timeline(order: order, name: name))),
          const SizedBox(height: SxSpace.s8),
          SxFadeUp(index: 2, child: SxCard(child: _ItemsCard(order: order))),
          const SizedBox(height: SxSpace.s8),
          SxFadeUp(
            index: 3,
            child: SxCard(
              onTap: conversation == null ? null : () => context.push(Routes.customer(conversation)),
              child: Row(
                spacing: SxSpace.s12,
                children: [
                  SxCustomerAvatar(name: name, channel: channelBrand(order.channel)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                        ),
                        Text(
                          conversation == null
                              ? 'No chat linked to this order'
                              : '$orderCount paid order${orderCount == 1 ? '' : 's'}',
                          style: SxText.caption.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (conversation != null)
                    SxButton(
                      label: 'Open chat',
                      icon: TablerIcons.message_circle,
                      kind: SxButtonKind.secondary,
                      onTap: () => context.push(Routes.chat(conversation)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SxSpace.s8),
          SxFadeUp(index: 4, child: SxCard(child: _PayCard(order: order, name: name))),
          const SizedBox(height: SxSpace.s8),
          SxFadeUp(index: 5, child: SxCard(child: _DeliveryCard(order: order))),
        ],
      ),
    );
  }
}

/// The order's own path with when each step happened, from `GET /orders/{id}/timeline`.
///
/// The server logs status changes only, as `triggered_by: system` from a database trigger, so "by
/// you" shows only when it really says so. "Placed" and "Paid" fall back to the order's own dates.
class _Timeline extends ConsumerWidget {
  const _Timeline({required this.order, required this.name});

  final Order order;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(orderTimelineProvider(order.id));
    final events = timeline.value ?? const <OrderTimelineEvent>[];
    final method = methodOf(order);
    final stages = stagesOf(method);
    final closed = isClosed(order);
    var index = stageIndexOf(order.status, method);
    if (closed) {
      for (final event in events) {
        final from = event.fromStatus;
        if (from != null) {
          final reached = stageIndexOf(from, method);
          if (reached > index) index = reached;
        }
      }
    }
    final atEnd = index == stages.length - 1;
    final next = nextStepOf(order);

    List<String> linesFor(int stage) {
      final lines = <String>[
        if (stage == 0) '${formatDateTime(order.createdAt)} · via ${channelName(order.channel)}',
      ];
      for (final event in events) {
        if (_endStatuses.contains(event.toStatus) || !isPaidStage(event.toStatus)) continue;
        if (stageIndexOf(event.toStatus, method) == stage) lines.add(_eventLine(event));
      }
      final paidAt = order.paidAt;
      if (stage == 0 && paidAt != null && !events.any((e) => e.toStatus == OrderStatus.paid)) {
        lines.add('${formatDateTime(paidAt)} · Paid');
      }
      return lines;
    }

    final rows = <_TimelineRow>[
      for (final (k, stage) in stages.indexed)
        if (!closed || k <= index)
          _TimelineRow(
            label: stage.label,
            state: k < index || atEnd || closed
                ? _DotState.done
                : (k == index ? _DotState.now : _DotState.todo),
            lines: [
              ...linesFor(k),
              if (k == index + 1 && next != null) 'Next: tap “${next.label}”',
              if (k == index + 1 && next == null && !isPaid(order)) 'Starts after payment',
            ],
          ),
      if (closed)
        _TimelineRow(
          label: lookOf(order).label == 'Refund due' ? 'Cancelled' : lookOf(order).label,
          state: _DotState.done,
          lines: [
            for (final event in events)
              if (_endStatuses.contains(event.toStatus)) _eventLine(event),
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) _TimelineStep(row: row, last: i == rows.length - 1),
        if (timeline.hasError && !timeline.isLoading)
          Padding(
            padding: const EdgeInsets.only(top: SxSpace.s8),
            child: SxLinkButton(
              label: 'History did not load. Try again',
              icon: TablerIcons.refresh,
              onTap: () => ref.invalidate(orderTimelineProvider(order.id)),
            ),
          ),
      ],
    );
  }

  static const _endStatuses = {
    OrderStatus.cancelled,
    OrderStatus.expired,
    OrderStatus.refunded,
  };

  static bool isPaidStage(String status) =>
      status == OrderStatus.paid ||
      status == OrderStatus.confirmed ||
      status == OrderStatus.ready ||
      status == OrderStatus.delivered ||
      status == OrderStatus.completed;

  String _eventLine(OrderTimelineEvent event) {
    final who = switch (event.triggeredBy) {
      'merchant' => 'by you',
      'customer' => 'by $name',
      'agent' || 'sellix' => 'by sellix',
      _ => null,
    };
    final comment = event.comment?.trim();
    return [
      formatDateTime(event.createdAt),
      if (event.toStatus == OrderStatus.paid) 'Paid',
      ?who,
      if (comment != null && comment.isNotEmpty && comment != 'Order status updated') comment,
    ].join(' · ');
  }
}

enum _DotState { done, now, todo }

class _TimelineRow {
  const _TimelineRow({required this.label, required this.state, required this.lines});

  final String label;
  final _DotState state;
  final List<String> lines;
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({required this.row, required this.last});

  final _TimelineRow row;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final done = row.state == _DotState.done;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 2),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? p.primary : (SxSheetScope.isOnSheet(context) ? p.page : p.card),
                    border: done
                        ? null
                        : Border.all(
                            color: row.state == _DotState.now ? p.primary : p.lineStrong,
                            width: row.state == _DotState.now ? 4 : 2,
                          ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: done ? p.primary : p.line),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    row.label,
                    style: SxText.bodyStrong.copyWith(
                      color: row.state == _DotState.todo ? p.textSecondary : p.textPrimary,
                    ),
                  ),
                  for (final line in row.lines)
                    Text(line, style: SxText.caption.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              spacing: SxSpace.s12,
              children: [
                const SxIconTile(icon: TablerIcons.package),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                      Text(
                        '${item.quantity} × ${money(item.unitPriceMinor, order.currency)}',
                        style: SxText.caption.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  money(item.lineTotalMinor, order.currency),
                  style: SxText.label.copyWith(color: p.textPrimary),
                ),
              ],
            ),
          ),
        const SizedBox(height: SxSpace.s8),
        SxKeyValue(
          label: 'Total',
          value: money(order.totalMinor, order.currency),
          divider: true,
        ),
      ],
    );
  }
}

class _PayCard extends ConsumerWidget {
  const _PayCard({required this.order, required this.name});

  final Order order;
  final String name;

  Widget _head(BuildContext context, String sub, SxChip? chip) {
    final p = context.sx;
    return Row(
      spacing: SxSpace.s12,
      children: [
        const SxIconTile(icon: TablerIcons.wallet),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
              Text(sub, style: SxText.caption.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        ?chip,
      ],
    );
  }

  Widget _status(BuildContext context) {
    final amount = money(order.totalMinor, order.currency);
    if (isRefundDue(order)) {
      return _head(
        context,
        'This order is cancelled, but $amount has not gone back to $name.',
        const SxChip(label: 'Not refunded', tone: SxChipTone.attention),
      );
    }
    if (canMarkPaid(order)) {
      return _head(
        context,
        'You start on it after it is paid.',
        const SxChip(label: 'Waiting', icon: TablerIcons.clock),
      );
    }
    return switch (order.status) {
      OrderStatus.expired => _head(context, 'Not paid in time. Stock went back.', const SxChip(label: 'Not paid')),
      OrderStatus.cancelled => _head(context, 'No money was taken.', const SxChip(label: 'Not paid')),
      OrderStatus.refunded => _head(
        context,
        '$amount went back to $name.',
        const SxChip(label: 'Refunded', icon: TablerIcons.arrow_back_up),
      ),
      _ when !isPaid(order) => _head(context, 'Not paid yet.', const SxChip(label: 'Not paid')),
      _ => _head(
        context,
        order.paidAt == null ? 'Paid.' : 'Paid ${formatDateTime(order.paidAt!)}.',
        payChipOf(order),
      ),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final value = ref.watch(orderPaymentsProvider(order.id));
    final payments = value.value;
    final paid = payments?.paid;
    final link = isPaid(order) ? null : payments?.openLink;
    final refund = payments?.refund;
    final amount = money(order.totalMinor, order.currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        _status(context),
        if (canMarkPaid(order) && order.holdExpiresAt != null) _HoldNote(expires: order.holdExpiresAt!),
        if (paid != null)
          Column(
            children: [
              SxKeyValue(
                label: 'Paid by',
                valueWidget: Wrap(
                  spacing: SxSpace.s8,
                  runSpacing: SxSpace.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.end,
                  children: [
                    Text(paymentMethodLabel(paid), style: SxText.bodyS.copyWith(color: p.textPrimary)),
                    if (paid.testMode) const _TestChip(),
                  ],
                ),
              ),
              if (paid.testMode)
                SxKeyValue(label: 'Money', value: 'Test payment: no real money moved', divider: true),
              if (paid.providerPaymentId case final id? when id.isNotEmpty)
                SxKeyValue(
                  label: paid.provider == 'razorpay' ? 'Razorpay payment ID' : 'Reference',
                  divider: true,
                  valueWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: SxSpace.s4,
                    children: [
                      Flexible(
                        child: SelectableText(id, style: SxText.bodyS.copyWith(color: p.textPrimary)),
                      ),
                      SxIconButton(
                        icon: TablerIcons.copy,
                        semanticLabel: 'Copy payment ID',
                        ghost: true,
                        onTap: () => copyText(context, id, 'Payment ID'),
                      ),
                    ],
                  ),
                ),
              if (paid.paidAt != null)
                SxKeyValue(label: 'Paid at', value: formatDateTime(paid.paidAt!), divider: true),
              if (paid.feeMinor > 0)
                SxKeyValue(label: 'Razorpay fee', value: money(paid.feeMinor, paid.currency), divider: true),
              if (confirmedByHand(paid))
                SxKeyValue(label: 'Confirmed', value: 'By you, by hand', divider: true),
            ],
          ),
        if (link != null) ...[
          if (link.testMode) const Align(alignment: AlignmentDirectional.centerStart, child: _TestChip()),
          _OpenLink(link: link.link!),
        ],
        if (refund != null) _RefundLine(refund: refund, currency: order.currency, name: name),
        if (value.hasError && payments == null)
          Row(
            spacing: SxSpace.s8,
            children: [
              Expanded(
                child: Text(
                  'Payment details did not load.',
                  style: SxText.caption.copyWith(color: p.textSecondary),
                ),
              ),
              SxLinkButton(
                label: 'Try again',
                onTap: () => ref.invalidate(orderPaymentsProvider(order.id)),
              ),
            ],
          ),
        if (canMarkPaid(order))
          SxButtonRow(
            children: [
              SxButton(
                label: 'Mark as paid',
                icon: TablerIcons.check,
                kind: SxButtonKind.secondary,
                onTap: () => showMarkPaidSheet(context, order, name),
              ),
              SxButton(
                label: 'Cancel order',
                icon: TablerIcons.ban,
                kind: SxButtonKind.secondary,
                onTap: () => showCancelSheet(context, order, name),
              ),
            ],
          )
        else if ((payments?.refundable ?? false) && !isRefundDue(order) && refund?.status != 'pending')
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SxButton(
              label: 'Refund $amount',
              icon: TablerIcons.arrow_back_up,
              kind: SxButtonKind.secondary,
              onTap: () => showRefundSheet(context, order, name),
            ),
          ),
      ],
    );
  }
}

/// Marks a Razorpay test-mode payment or link: no real money.
class _TestChip extends StatelessWidget {
  const _TestChip();

  @override
  Widget build(BuildContext context) =>
      const SxChip(label: 'Test payment', tone: SxChipTone.attention, icon: TablerIcons.flask);
}

/// The open payment link, to copy or share while the order is unpaid.
class _OpenLink extends ConsumerWidget {
  const _OpenLink({required this.link});

  final String link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    return Container(
      padding: const EdgeInsets.fromLTRB(SxSpace.s12, SxSpace.s4, SxSpace.s4, SxSpace.s4),
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(SxRadius.tile)),
      child: Row(
        spacing: SxSpace.s4,
        children: [
          Icon(TablerIcons.link, size: 18, color: p.textSecondary),
          Expanded(
            child: Text(
              link,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SxText.bodyS.copyWith(color: p.textPrimary),
            ),
          ),
          SxIconButton(
            icon: TablerIcons.copy,
            semanticLabel: 'Copy payment link',
            ghost: true,
            onTap: () => copyText(context, link, 'Payment link'),
          ),
          SxIconButton(
            icon: TablerIcons.share,
            semanticLabel: 'Share payment link',
            ghost: true,
            onTap: () => shareText(context, link),
          ),
        ],
      ),
    );
  }
}

class _RefundLine extends StatelessWidget {
  const _RefundLine({required this.refund, required this.currency, required this.name});

  final OrderRefund refund;
  final String currency;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final amount = money(refund.amountMinor, currency);
    final (icon, text, color) = switch (refund.status) {
      'pending' => (
        TablerIcons.clock,
        'Refund of $amount started. Razorpay usually takes 5–7 days to send it back to $name.',
        p.textPrimary,
      ),
      'failed' => (TablerIcons.alert_triangle, 'The refund of $amount failed. No money moved.', p.errorText),
      _ => (TablerIcons.arrow_back_up, '$amount refunded ${formatDateTime(refund.createdAt)}.', p.textPrimary),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: SxSpace.s8,
        children: [
          Icon(icon, size: 20, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: SxText.bodyS.copyWith(color: color)),
                if (refund.reason?.trim().isNotEmpty ?? false)
                  Text('Reason: ${refund.reason!.trim()}', style: SxText.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A live count of the stock hold. The timer stops with the widget.
class _HoldNote extends StatefulWidget {
  const _HoldNote({required this.expires});

  final DateTime expires;

  @override
  State<_HoldNote> createState() => _HoldNoteState();
}

class _HoldNoteState extends State<_HoldNote> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final left = widget.expires.difference(DateTime.now());
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Row(
      spacing: SxSpace.s8,
      children: [
        Icon(TablerIcons.hourglass, size: 20, color: p.textSecondary),
        Expanded(
          child: Text(
            left.isNegative
                ? 'The stock hold ran out. It goes back on sale soon.'
                : 'Stock is held for ${left.inMinutes}:$seconds more',
            style: SxText.bodyS.copyWith(color: p.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.order});

  final Order order;

  Future<void> _openMap(BuildContext context, String address) async {
    final url = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address});
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showSxSnack(context, 'Could not open maps.', icon: TablerIcons.map_2, sellix: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final method = methodOf(order);
    final title = switch (method) {
      OrderMethod.pickup => 'Pickup at the shop',
      OrderMethod.localDelivery => 'Local delivery',
      OrderMethod.courier => 'Courier',
      OrderMethod.digital => 'Digital, sent in the DM',
    };
    final due = dueText(order);
    final needed = order.neededBy?.trim();
    final delivers = method == OrderMethod.localDelivery || method == OrderMethod.courier;
    final address = order.deliveryAddress?.trim();
    final note = order.customerNote?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s8,
      children: [
        Row(
          spacing: SxSpace.s12,
          children: [
            SxIconTile(icon: methodIcon(method)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                  if (due != null || (needed?.isNotEmpty ?? false))
                    Text(
                      due ?? 'Was for $needed',
                      style: SxText.caption.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
        // BACKEND GAP: no rider, ETA, carrier or tracking number on an order.
        if (delivers)
          (address == null || address.isEmpty)
              ? Text(
                  'No address on this order yet.',
                  style: SxText.caption.copyWith(color: p.textSecondary),
                )
              : Row(
                  spacing: SxSpace.s8,
                  children: [
                    Expanded(
                      child: Text(address, style: SxText.bodyS.copyWith(color: p.textPrimary)),
                    ),
                    SxIconButton(
                      icon: TablerIcons.copy,
                      semanticLabel: 'Copy address',
                      onTap: () => copyText(context, address, 'Address'),
                    ),
                    SxIconButton(
                      icon: TablerIcons.map_2,
                      semanticLabel: 'Open in maps',
                      onTap: () => _openMap(context, address),
                    ),
                  ],
                ),
        if (note != null && note.isNotEmpty)
          Row(
            spacing: SxSpace.s8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(TablerIcons.note, size: 20, color: p.textSecondary),
              Expanded(child: Text(note, style: SxText.bodyS.copyWith(color: p.textPrimary))),
            ],
          ),
      ],
    );
  }
}
