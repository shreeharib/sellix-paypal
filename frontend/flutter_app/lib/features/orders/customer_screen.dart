import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import 'customers_logic.dart';
import 'order_actions.dart';
import 'order_logic.dart';
import 'order_row.dart';
import 'orders_providers.dart';

/// One customer. [customerId] is the conversation id: the API has no customer id to use.
class CustomerScreen extends ConsumerWidget {
  const CustomerScreen(this.customerId, {super.key});

  final String customerId;

  void _retry(WidgetRef ref) {
    ref.invalidate(conversationsProvider);
    ref.invalidate(ordersProvider);
    ref.invalidate(customerFactsProvider(customerId));
  }

  Future<void> _reload(WidgetRef ref) async {
    _retry(ref);
    await ref.read(customersProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    final found = customers.value?.where((c) => c.id == customerId).firstOrNull;
    return SxScaffold(
      floating: found == null
          ? null
          : SxBottomCta(
              label: 'Open chat',
              icon: TablerIcons.message_circle,
              onTap: () => context.push(Routes.chat(customerId)),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SxDetailHeader(title: '', fallback: Routes.customers),
          Expanded(
            child: SxAsyncView<List<CustomerSummary>>(
              value: customers,
              onRetry: () => _retry(ref),
              loading: const SxSkeletonList(topHeight: 160),
              builder: (context, _) => SxScrollList(
                onRefresh: () => _reload(ref),
                children: found == null
                    ? const [
                        SxEmptyState(
                          icon: TablerIcons.user_search,
                          title: 'Customer not found',
                          body: 'This chat is no longer on your list.',
                        ),
                      ]
                    : [_CustomerBody(customer: found)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerBody extends ConsumerWidget {
  const _CustomerBody({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final channel = channelName(customer.conversation.channel);
    final first = customer.firstOrderAt;
    final address = customer.lastAddress;
    // Nice to have: a failure here leaves the rest of the profile standing.
    final facts = ref.watch(customerFactsProvider(customer.id)).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SxFadeUp(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
            child: Column(
              spacing: SxSpace.s4,
              children: [
                SxCustomerAvatar(
                  name: customer.handle,
                  large: true,
                  channel: channelBrand(customer.conversation.channel),
                ),
                const SizedBox(height: SxSpace.s8),
                Text(
                  customer.handle,
                  textAlign: TextAlign.center,
                  style: SxText.titleL.copyWith(color: p.textPrimary),
                ),
                Text(
                  // BACKEND GAP: no customer "since" date; the first order we can see stands in.
                  first == null ? channel : '$channel · first order ${formatDate(first)}',
                  textAlign: TextAlign.center,
                  style: SxText.caption.copyWith(color: p.textSecondary),
                ),
                // BACKEND GAP: no customer language, so the prototype's language chip is left out.
                if (customer.isRepeat)
                  const Padding(
                    padding: EdgeInsets.only(top: SxSpace.s4),
                    child: SxChip(label: 'Repeat customer', tone: SxChipTone.positive),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
            child: Row(
              spacing: SxSpace.s8,
              children: [
                Expanded(child: _Stat(value: '${customer.paidCount}', label: 'Paid orders')),
                Expanded(child: _Stat(value: customer.spentText ?? '–', label: 'Spent')),
                Expanded(child: _Stat(value: customer.perOrderText ?? '–', label: 'Per order')),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s12, SxSpace.screen, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              if (facts.isNotEmpty)
                SxFadeUp(
                  index: 2,
                  child: SxCard(
                    child: SxAiNote(facts.map((f) => '${f.key}: ${f.value}').join('\n')),
                  ),
                ),
              SxFadeUp(
                index: 3,
                child: SxGroup(
                  children: [
                    // BACKEND GAP: customer phone isn't in the API. Nothing is invented.
                    const SxListRow(
                      icon: TablerIcons.phone_off,
                      title: 'No phone number',
                      subtitle: 'sellix can’t show phone numbers yet',
                      chevron: false,
                    ),
                    if (address != null)
                      SxListRow(
                        icon: TablerIcons.map_pin,
                        title: address,
                        subtitle: 'Latest delivery address',
                        trailing: const Icon(TablerIcons.copy, size: 20),
                        onTap: () => copyText(context, address, 'Address'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SxSectionHeader(title: 'All orders', badge: customer.orders.length),
        if (customer.orders.isEmpty)
          const SxEmptyState(
            icon: TablerIcons.receipt,
            title: 'No orders yet',
            body: 'Their orders show here.',
          ),
        for (final (index, order) in customer.orders.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.screen, 0, SxSpace.screen, SxSpace.listGap),
            child: SxFadeUp(
              index: index,
              child: OrderRow(order: order, name: customer.handle, compact: true),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: SxText.stat.copyWith(color: p.textPrimary)),
          ),
          Text(label, style: SxText.micro.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}
