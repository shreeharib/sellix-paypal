/// Everything that changes an order, each behind the confirmation the prototype shows.
///
/// Every action reads the provider container once up front, so it finishes cleanly even if the
/// merchant leaves the screen while the call is running.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../stock/stock_providers.dart';
import 'order_logic.dart';
import 'orders_providers.dart';

ProviderContainer _containerOf(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false);

/// Orders, this order and its payments and history, and the stock counts a payment, cancel or
/// refund can change.
void _refresh(ProviderContainer container, String orderId) {
  container
    ..invalidate(ordersProvider)
    ..invalidate(orderProvider(orderId))
    ..invalidate(orderPaymentsProvider(orderId))
    ..invalidate(orderTimelineProvider(orderId))
    ..invalidate(todayProvider);
}

String _subtitle(Order order, String name) => '#${order.number} · $name · ${itemsLine(order)}';

/// The bottom button and quick row action: one thing to do for every state.
Future<void> runOrderNext(BuildContext context, Order order, String name) async {
  if (isRefundDue(order)) return showRefundSheet(context, order, name);
  if (canMarkPaid(order)) return showPaymentLinkSheet(context, order, name);
  final next = nextStepOf(order);
  if (next != null) return showAdvanceSheet(context, order, name, next);
  final conversation = order.conversationId;
  if (conversation != null) await context.push(Routes.chat(conversation));
}

/// The bottom button's label and icon, or null when there is nothing to offer.
({String label, IconData icon})? orderCtaOf(Order order) {
  if (isRefundDue(order)) {
    return (
      label: 'Refund ${money(order.totalMinor, order.currency)}',
      icon: TablerIcons.arrow_back_up,
    );
  }
  if (canMarkPaid(order)) return (label: 'Get payment link', icon: TablerIcons.link);
  final next = nextStepOf(order);
  if (next != null) return (label: next.label, icon: next.icon);
  if (order.conversationId != null) {
    return (label: 'Message customer', icon: TablerIcons.message_circle);
  }
  return null;
}

// ---------- Stage changes ----------

Future<void> showAdvanceSheet(
  BuildContext context,
  Order order,
  String name,
  NextStep next,
) async {
  final container = _containerOf(context);
  final api = container.read(sellixApiProvider);
  final result = await showSxSheet<Order>(
    context,
    title: next.question,
    subtitle: _subtitle(order, name),
    builder: (_) => OrderActionSheet<Order>(
      content: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          if (methodOf(order) == OrderMethod.digital)
            // BACKEND GAP: no link or file field for digital orders, so sellix can't send it.
            SxBanner(
              message: 'sellix does not send it for you yet. Send it to $name in chat first.',
              tone: SxBannerTone.neutral,
              icon: TablerIcons.send,
            ),
          _NoMessageNote(name),
        ],
      ),
      cancelLabel: 'Not yet',
      confirmLabel: next.label,
      confirmIcon: next.icon,
      run: () async {
        final updated = next.usesComplete
            ? await api.completeOrder(order.id)
            : await api.updateOrderStatus(order.id, next.targetStatus);
        _refresh(container, order.id);
        return updated;
      },
    ),
  );
  if (result == null || !context.mounted) return;
  final undo = next.undoStatus;
  showSxSnack(
    context,
    '${next.doneText}. No message sent.',
    icon: next.icon,
    sellix: false,
    action: undo == null ? null : 'Undo',
    onAction: undo == null
        ? null
        : () => _moveBack(context, container, order.id, undo, 'Undone. Nothing went to the customer.'),
  );
}

Future<void> _moveBack(
  BuildContext context,
  ProviderContainer container,
  String orderId,
  String status,
  String doneText,
) async {
  try {
    await container.read(sellixApiProvider).updateOrderStatus(orderId, status);
    _refresh(container, orderId);
    if (context.mounted) {
      showSxSnack(context, doneText, icon: TablerIcons.arrow_back_up, sellix: false);
    }
  } on Exception catch (error) {
    if (context.mounted) {
      showSxSnack(context, sxErrorMessage(error), icon: TablerIcons.alert_triangle, sellix: false);
    }
  }
}

Future<void> showGoBackSheet(BuildContext context, Order order, String name, String status) async {
  final method = methodOf(order);
  final stages = stagesOf(method);
  final from = stages[stageIndexOf(order.status, method)].label.toLowerCase();
  final to = stages[stageIndexOf(status, method)].label.toLowerCase();
  final container = _containerOf(context);
  final api = container.read(sellixApiProvider);
  final result = await showSxSheet<Order>(
    context,
    title: 'Go back to $to?',
    subtitle:
        '#${order.number} moves back from $from. sellix does not message $name. '
        'If the customer already got an update, tell them in chat.',
    builder: (_) => OrderActionSheet<Order>(
      cancelLabel: 'Keep it',
      confirmLabel: 'Go back',
      confirmIcon: TablerIcons.corner_up_left,
      run: () async {
        final updated = await api.updateOrderStatus(order.id, status);
        _refresh(container, order.id);
        return updated;
      },
    ),
  );
  if (result != null && context.mounted) {
    showSxSnack(context, 'Back to $to.', icon: TablerIcons.corner_up_left, sellix: false);
  }
}

// ---------- Payment ----------

Future<void> showMarkPaidSheet(BuildContext context, Order order, String name) async {
  final amount = money(order.totalMinor, order.currency);
  final container = _containerOf(context);
  final api = container.read(sellixApiProvider);
  var method = 'upi';
  final result = await showSxSheet<Order>(
    context,
    title: 'Did the $amount reach you?',
    subtitle: 'Check your bank or UPI app for $amount from $name. Only say yes if you see the money.',
    builder: (_) => OrderActionSheet<Order>(
      content: (_, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final (value, label) in const [('upi', 'UPI'), ('cash', 'Cash'), ('card', 'Card')])
                SxPickChip(
                  label: label,
                  selected: method == value,
                  onTap: () => setState(() => method = value),
                ),
            ],
          ),
          // The server always tells the customer after mark-paid. There's no way to turn it off.
          SxAiNote('sellix tells $name the payment came. This can’t be undone.'),
        ],
      ),
      cancelLabel: 'Not yet',
      confirmLabel: 'Yes, I got it',
      confirmIcon: TablerIcons.check,
      run: () async {
        final updated = await api.markOrderPaid(order.id, method: method);
        _refresh(container, order.id);
        return updated;
      },
    ),
  );
  if (result != null && context.mounted) {
    showSxSnack(
      context,
      'Payment confirmed. sellix is telling $name. Accept the order next.',
      icon: TablerIcons.check,
    );
  }
}

/// What the link sheet shows. `upiMissing` stops a link paying an address the shop never gave.
class _LinkResult {
  const _LinkResult(this.link, {this.upiMissing = false});

  final PaymentLinkResponse link;
  final bool upiMissing;
}

Future<_LinkResult> _loadLink(ProviderContainer container, Order order) async {
  final api = container.read(sellixApiProvider);
  final link = await api.paymentLink(order.id);
  if (link.paymentMethod != PaymentMethod.upi) return _LinkResult(link);
  // With no UPI ID saved, the server makes one up from the shop name (`<shopname>@upi`).
  final onboarding = await api.onboarding();
  final upi = onboarding.answers.upiId?.trim() ?? '';
  return _LinkResult(link, upiMissing: upi.isEmpty);
}

/// BACKEND GAP: no endpoint sends the link to the customer, so the prototype's "Resend link" can't
/// be real. The merchant gets the real link to copy, and the chat is one tap away.
Future<void> showPaymentLinkSheet(BuildContext context, Order order, String name) {
  final container = _containerOf(context);
  return showSxSheet<void>(
    context,
    title: 'Payment link',
    subtitle: '#${order.number} · $name · ${money(order.totalMinor, order.currency)}',
    builder: (sheet) => _PaymentLinkBody(load: () => _loadLink(container, order), order: order),
  );
}

class _PaymentLinkBody extends StatefulWidget {
  const _PaymentLinkBody({required this.load, required this.order});

  final Future<_LinkResult> Function() load;
  final Order order;

  @override
  State<_PaymentLinkBody> createState() => _PaymentLinkBodyState();
}

class _PaymentLinkBodyState extends State<_PaymentLinkBody> {
  late Future<_LinkResult> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LinkResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s12,
            children: [
              SxBanner(
                message: sxErrorMessage(snapshot.error),
                tone: SxBannerTone.error,
                icon: TablerIcons.alert_triangle,
              ),
              SxButton(
                label: 'Try again',
                kind: SxButtonKind.secondary,
                onTap: () => setState(() {
                  _future = widget.load();
                }),
              ),
            ],
          );
        }
        final result = snapshot.data;
        if (result == null) return const SxSkeleton(height: 56, radius: SxRadius.tile);
        if (result.upiMissing) {
          return SxBanner(
            message: 'Add your UPI ID first. Without it this link would not pay you.',
            tone: SxBannerTone.error,
            icon: TablerIcons.alert_triangle,
            action: SxLinkButton(
              label: 'Open payments',
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(Routes.payments);
              },
            ),
          );
        }
        final link = result.link.paymentLink;
        final conversation = widget.order.conversationId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: SxSpace.s12,
          children: [
            SxCard(
              child: Row(
                spacing: SxSpace.s8,
                children: [
                  Icon(TablerIcons.link, size: 20, color: context.sx.textSecondary),
                  Expanded(
                    child: Text(
                      link,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.bodyS.copyWith(color: context.sx.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'sellix does not send this for you here. Copy it and paste it in the chat.',
              style: SxText.caption.copyWith(color: context.sx.textSecondary),
            ),
            SxButtonRow(
              children: [
                SxButton(
                  label: 'Open chat',
                  icon: TablerIcons.message_circle,
                  kind: SxButtonKind.secondary,
                  onTap: conversation == null
                      ? null
                      : () {
                          final router = GoRouter.of(context);
                          Navigator.of(context).pop();
                          router.push(Routes.chat(conversation));
                        },
                ),
                SxButton(
                  label: 'Copy link',
                  icon: TablerIcons.copy,
                  onTap: () => copyText(context, link, 'Payment link'),
                ),
              ],
            ),
            SxLinkButton(
              label: 'Share link',
              icon: TablerIcons.share,
              onTap: () => shareText(context, link),
            ),
          ],
        );
      },
    );
  }
}

/// Opens the phone's share sheet. Tests replace it ([shareTextOverride]).
Future<void> shareText(BuildContext context, String text) async {
  final override = shareTextOverride;
  if (override != null) return override(text);
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } on Object {
    if (context.mounted) {
      showSxSnack(context, 'Could not open sharing. Copy the link instead.', icon: TablerIcons.share, sellix: false);
    }
  }
}

/// Set in tests to see what would be shared.
@visibleForTesting
Future<void> Function(String text)? shareTextOverride;

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    showSxSnack(
      context,
      '$what copied.',
      icon: TablerIcons.copy,
      sellix: false,
      duration: const Duration(milliseconds: 1800),
    );
  }
}

// ---------- Cancel ----------

const _cancelReasons = [
  'Customer changed mind',
  'Out of stock',
  'Cannot deliver there',
  'Customer did not pay',
  'Other',
];

/// Returned by the cancel sheet when the merchant picks the refund.
const _refundInstead = 'refund';

/// Stock wording is true to the server: `cancel_order` releases held stock for an unpaid order only.
Future<void> showCancelSheet(BuildContext context, Order order, String name) async {
  final amount = money(order.totalMinor, order.currency);
  final paid = isPaid(order);
  final container = _containerOf(context);
  final api = container.read(sellixApiProvider);
  String? reason;
  final result = await showSxSheet<Object>(
    context,
    title: 'Cancel this order?',
    subtitle: '#${order.number} · $name · $amount',
    builder: (sheet) => OrderActionSheet<Object>(
      content: (_, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          if (paid)
            SxBanner(
              message:
                  'Cancelling does not refund $name. The $amount stays with you until you make '
                  'a refund. Only Refund sends money back.',
              tone: SxBannerTone.error,
              icon: TablerIcons.alert_triangle,
              action: canRefund(order)
                  ? SxLinkButton(
                      label: 'Refund instead',
                      icon: TablerIcons.arrow_back_up,
                      onTap: () => Navigator.of(sheet).pop(_refundInstead),
                    )
                  : null,
            ),
          Text(
            'Why are you cancelling?',
            style: SxText.label.copyWith(color: sheet.sx.textPrimary),
          ),
          Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final option in _cancelReasons)
                SxPickChip(
                  label: option,
                  selected: reason == option,
                  onTap: () => setState(() => reason = option),
                ),
            ],
          ),
          SxCard(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: SxSpace.s4),
            child: Column(
              children: [
                SxKeyValue(
                  label: 'Stock',
                  value: paid
                      ? 'Stays counted as sold. Cancelling a paid order does not put it back on sale.'
                      : 'Goes back on sale.',
                ),
                SxKeyValue(
                  label: 'Money',
                  value: paid ? 'Not refunded. $amount stays with you.' : 'No money was taken.',
                  divider: true,
                ),
              ],
            ),
          ),
          _NoMessageNote(name),
        ],
      ),
      cancelLabel: 'Keep order',
      confirmLabel: paid ? 'Cancel, no refund' : 'Cancel order',
      confirmIcon: TablerIcons.ban,
      validate: () => reason == null ? 'Pick a reason first. It stays on the order.' : null,
      run: () async {
        final updated = await api.cancelOrder(order.id, reason: reason);
        _refresh(container, order.id);
        return updated;
      },
    ),
  );
  if (!context.mounted) return;
  if (result == _refundInstead) return showRefundSheet(context, order, name);
  if (result == null) return;
  showSxSnack(
    context,
    paid
        ? 'Order #${order.number} cancelled. $amount was not refunded.'
        : 'Order #${order.number} cancelled. No message sent.',
    icon: TablerIcons.ban,
    sellix: false,
  );
}

// ---------- Refund ----------

final _serverId = RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}');

/// The server's reason in merchant words. A 400 means nothing was refunded; a message that holds
/// internal ids is replaced, since the merchant can't use them.
String refundErrorText(Object error) {
  if (error is! ApiException || error.statusCode != 400) return sxErrorMessage(error);
  final text = error.message.trim();
  if (text.contains('already refunded')) return 'This order is already refunded.';
  if (text.isEmpty || _serverId.hasMatch(text)) return 'The refund didn’t go through. No money moved.';
  final sentence = RegExp(r'[.!?]$').hasMatch(text) ? text : '$text.';
  return sentence.contains('No money moved') ? sentence : '$sentence No money moved.';
}

/// What a refund does, by `refund_mode`.
String refundWords(String? mode, String amount, String name) => switch (mode) {
  RefundMode.razorpay => 'Razorpay sends $amount back to $name (usually 5–7 days).',
  RefundMode.manual => 'You return the money to $name yourself; sellix records the refund.',
  RefundMode.simulator => 'This was a test payment. No real money moves.',
  _ => 'sellix records a full refund of $amount.',
};

/// Full refunds only (`POST /orders/{id}/refund`). The wording follows how the order was paid: a
/// Razorpay payment goes back by itself; UPI or cash the merchant returns, and sellix records it.
Future<void> showRefundSheet(BuildContext context, Order order, String name) async {
  final amount = money(order.totalMinor, order.currency);
  final reached = isFinished(order);
  final canRestock = refundCanRestock(order);
  final container = _containerOf(context);
  final api = container.read(sellixApiProvider);
  String? mode;
  try {
    mode = (await container.read(orderPaymentsProvider(order.id).future)).refundMode;
  } on Object {
    // The sheet still opens; the server decides how the refund goes.
  }
  if (!context.mounted) return;
  var restock = canRestock && !reached;
  final reason = TextEditingController();
  final manual = mode == RefundMode.manual;
  final result = await showSxSheet<RefundResponse>(
    context,
    title: manual ? 'Record a refund?' : 'Refund this order?',
    subtitle: refundWords(mode, amount, name),
    builder: (_) => OrderActionSheet<RefundResponse>(
      content: (_, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          SxCard(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: SxSpace.s4),
            child: SxKeyValue(label: 'Full refund', value: '$amount. Refunds are full only.'),
          ),
          SxField(
            controller: reason,
            label: 'Reason (optional)',
            hint: 'Out of stock',
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (canRestock)
            SxSwitchRow(
              title: 'Put items back in stock',
              subtitle: reached ? 'Leave off if it came back damaged.' : 'It has not left yet.',
              value: restock,
              onChanged: (value) => setState(() => restock = value),
            )
          else
            Builder(
              builder: (context) => Text(
                'Stock does not go back for an order at this stage.',
                style: SxText.caption.copyWith(color: context.sx.textSecondary),
              ),
            ),
          _NoMessageNote(name),
        ],
      ),
      cancelLabel: 'Keep order',
      confirmLabel: manual ? 'Record refund' : 'Refund',
      confirmIcon: TablerIcons.arrow_back_up,
      errorText: refundErrorText,
      run: () async {
        final text = reason.text.trim();
        final refund = await api.refundOrder(order.id, reason: text.isEmpty ? null : text, restock: restock);
        _refresh(container, order.id);
        return refund;
      },
    ),
  );
  // The controller is left to the garbage collector: the sheet may still be animating out.
  if (result == null || !context.mounted) return;
  final sent = money(result.amountMinor, result.currency);
  final status = result.status.toLowerCase();
  showSxSnack(
    context,
    switch (status) {
      'pending' => 'Refund started. Razorpay is sending $sent back to $name.',
      'failed' => 'The refund failed. No money moved.',
      _ when (result.mode ?? mode) == RefundMode.manual => 'Refund of $sent recorded. No message sent.',
      _ => '$sent refunded. No message sent.',
    },
    icon: status == 'failed' ? TablerIcons.alert_triangle : TablerIcons.arrow_back_up,
    sellix: false,
  );
}

// ---------- Menu and slip ----------

/// The order's secondary actions. Only what makes sense for its state.
Future<void> showOrderMenu(
  BuildContext context,
  Order order,
  String name, {
  DateTime? lastChange,
  OrderPayments? payments,
}) async {
  final back = previousStatusOf(order, lastChange: lastChange);
  // The server says whether it can be refunded; until it has, the order's own state decides.
  final refundable = payments?.refundable ?? canRefund(order);
  final choice = await showSxSheet<String>(
    context,
    title: 'Order #${order.number}',
    builder: (sheet) => SxGroup(
      children: [
        if (back != null)
          SxListRow(
            icon: TablerIcons.corner_up_left,
            title: 'Go back one stage',
            subtitle: 'Used if you tapped by mistake',
            onTap: () => Navigator.of(sheet).pop('back'),
          ),
        if (kShowComingSoon && !isClosed(order) && !isFinished(order))
          // BACKEND GAP: no endpoint edits an order's address or time.
          const SxListRow(
            icon: TablerIcons.edit,
            title: 'Edit delivery details',
            subtitle: 'Not available yet',
            chevron: false,
          ),
        SxListRow(
          icon: TablerIcons.printer,
          title: 'Packing slip',
          subtitle: 'Items and address',
          onTap: () => Navigator.of(sheet).pop('slip'),
        ),
        if (refundable)
          SxListRow(
            icon: TablerIcons.arrow_back_up,
            title: 'Refund',
            subtitle: switch (payments?.refundMode) {
              RefundMode.razorpay => 'Razorpay sends the money back',
              RefundMode.manual => 'You send it back; sellix records it',
              _ => 'Full refund',
            },
            onTap: () => Navigator.of(sheet).pop('refund'),
          ),
        if (canCancel(order))
          SxListRow(
            icon: TablerIcons.ban,
            title: 'Cancel order',
            subtitle: isPaid(order) ? 'This does not refund the customer' : 'Stock goes back',
            danger: true,
            onTap: () => Navigator.of(sheet).pop('cancel'),
          ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'back':
      await showGoBackSheet(context, order, name, back!);
    case 'slip':
      await showSlipSheet(context, order, name);
    case 'refund':
      await showRefundSheet(context, order, name);
    case 'cancel':
      await showCancelSheet(context, order, name);
  }
}

String slipText(Order order, String name) {
  final lines = <String>[
    'Order #${order.number}',
    for (final item in order.items) '${item.label} × ${item.quantity}',
    '${methodLabel(methodOf(order))} to: $name',
    if (order.deliveryAddress?.trim().isNotEmpty ?? false) order.deliveryAddress!.trim(),
    if (order.customerNote?.trim().isNotEmpty ?? false) 'Note: ${order.customerNote!.trim()}',
  ];
  return lines.join('\n');
}

Future<void> showSlipSheet(BuildContext context, Order order, String name) {
  return showSxSheet<void>(
    context,
    title: 'Packing slip',
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        SxCard(
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: SxSpace.s4),
          child: Column(
            children: [
              SxKeyValue(label: 'Order', value: '#${order.number}'),
              for (final item in order.items)
                SxKeyValue(label: item.label, value: '× ${item.quantity}', divider: true),
              SxKeyValue(
                label: '${methodLabel(methodOf(order))} to',
                value: [name, order.deliveryAddress?.trim()]
                    .whereType<String>()
                    .where((part) => part.isNotEmpty)
                    .join('\n'),
                divider: true,
              ),
              if (order.customerNote?.trim().isNotEmpty ?? false)
                SxKeyValue(label: 'Note', value: order.customerNote!.trim(), divider: true),
            ],
          ),
        ),
        SxButtonRow(
          children: [
            // Printing needs a plugin the app doesn't ship. Copying is real, so that's the action.
            if (kShowComingSoon)
              const SxButton(
                label: 'Print soon',
                icon: TablerIcons.printer,
                kind: SxButtonKind.secondary,
                onTap: null,
              ),
            SxButton(
              label: 'Copy slip',
              icon: TablerIcons.copy,
              onTap: () {
                Navigator.of(sheet).pop();
                copyText(context, slipText(order, name), 'Slip');
              },
            ),
          ],
        ),
      ],
    ),
  );
}

// ---------- Shared sheet parts ----------

/// BACKEND GAP: stage changes, cancels and refunds send the customer nothing, so the prototype's
/// "sellix tells ..." preview and toggle would be untrue here.
class _NoMessageNote extends StatelessWidget {
  const _NoMessageNote(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      'No message goes out. sellix does not tell $name about this yet, so tell them in chat if '
      'they need to know.',
      style: SxText.caption.copyWith(color: context.sx.textSecondary),
    );
  }
}

/// A sheet body with its two buttons. It stays open while the call runs and shows a failure in
/// place, so nothing is reported as done before the server has said so.
class OrderActionSheet<T extends Object> extends StatefulWidget {
  const OrderActionSheet({
    super.key,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.run,
    this.confirmIcon,
    this.content,
    this.validate,
    this.errorText = sxErrorMessage,
  });

  final String cancelLabel;
  final String confirmLabel;
  final IconData? confirmIcon;
  final Future<T> Function() run;

  /// Rebuilt with the sheet's own setState, so choices kept by the caller stay simple.
  final Widget Function(BuildContext context, StateSetter setState)? content;

  /// A message when the sheet can't go ahead yet.
  final String? Function()? validate;
  final String Function(Object error) errorText;

  @override
  State<OrderActionSheet<T>> createState() => _OrderActionSheetState<T>();
}

class _OrderActionSheetState<T extends Object> extends State<OrderActionSheet<T>> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    final problem = widget.validate?.call();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.run();
      if (mounted) Navigator.of(context).pop(result);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s16,
        children: [
          if (content != null)
            content(context, (change) {
              setState(() {
                change();
                _error = null;
              });
            }),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: SxText.caption.copyWith(color: context.sx.errorText)),
            ),
          SxButtonRow(
            children: [
              SxButton(
                label: widget.cancelLabel,
                kind: SxButtonKind.secondary,
                onTap: _busy ? null : () => Navigator.of(context).pop(),
              ),
              SxButton(
                label: widget.confirmLabel,
                icon: widget.confirmIcon,
                loading: _busy,
                onTap: _busy ? null : _confirm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
