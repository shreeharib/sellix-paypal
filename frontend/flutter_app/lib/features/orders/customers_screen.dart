import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import 'customers_logic.dart';
import 'order_logic.dart';
import 'orders_providers.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  CustomerFilter _filter = CustomerFilter.all;
  String _query = '';

  void _retry() {
    ref.invalidate(conversationsProvider);
    ref.invalidate(ordersProvider);
  }

  Future<void> _reload() async {
    _retry();
    await ref.read(customersProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final list = customers.value;
    return SxScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxDetailHeader(
            title: 'Customers',
            meta: list == null
                ? null
                : '${customerStatsOf(list).buyers} of ${list.length} people bought from you',
            fallback: Routes.orders,
          ),
          Expanded(
            child: SxAsyncView<List<CustomerSummary>>(
              value: customers,
              onRetry: _retry,
              loading: const SxSkeletonList(topHeight: 80),
              isEmpty: (all) => all.isEmpty,
              empty: const SxEmptyState(
                icon: TablerIcons.users,
                title: 'No customers yet',
                body: 'People who message your shop show here.',
              ),
              builder: (context, all) => _list(all),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<CustomerSummary> all) {
    final stats = customerStatsOf(all);
    final shown = all.where((c) => matchesCustomer(c, _filter, _query)).toList();
    return SxScrollList(
      onRefresh: _reload,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
          child: Row(
            spacing: SxSpace.s8,
            children: [
              Expanded(child: _Stat(value: '${stats.buyers}', label: 'Bought')),
              Expanded(child: _Stat(value: '${stats.backPercent}%', label: 'Come back')),
              Expanded(child: _Stat(value: stats.perOrder ?? '–', label: 'Per order')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s12, SxSpace.screen, SxSpace.s12),
          child: SxField(
            hint: 'Search customers',
            trailing: Icon(TablerIcons.search, size: 20, color: context.sx.textSecondary),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SxFilterChips(
          children: [
            for (final (value, label) in const [
              (CustomerFilter.all, 'All'),
              (CustomerFilter.repeat, 'Repeat'),
              (CustomerFilter.fresh, 'New'),
            ])
              SxFilterChip(
                label: label,
                selected: _filter == value,
                onTap: () => setState(() => _filter = value),
              ),
            // BACKEND GAP: no customer country in the API, so "Abroad" can't be worked out.
            SxFilterChip(
              label: 'Abroad',
              selected: false,
              onTap: () => showSxSnack(
                context,
                'Customer country isn’t available yet.',
                icon: TablerIcons.world,
                sellix: false,
                aboveBar: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: SxSpace.s12),
        if (shown.isEmpty)
          const SxEmptyState(
            icon: TablerIcons.user_search,
            title: 'No customers match',
            body: 'Try another name.',
          ),
        for (final (index, customer) in shown.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.screen, 0, SxSpace.screen, SxSpace.listGap),
            child: SxFadeUp(index: index, child: _CustomerRow(customer: customer)),
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final spent = customer.spentText;
    return SxCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: SxSpace.s12),
      onTap: () => context.push(Routes.customer(customer.id)),
      child: Row(
        spacing: SxSpace.s12,
        children: [
          SxCustomerAvatar(name: customer.handle, channel: channelBrand(customer.conversation.channel)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: SxSpace.s8,
                  children: [
                    Expanded(
                      child: Text(
                        customer.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                      ),
                    ),
                    if (spent != null)
                      Text(spent, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                  ],
                ),
                Row(
                  spacing: SxSpace.s8,
                  children: [
                    Expanded(
                      child: Text(
                        '${customer.paidCount} paid order${customer.paidCount == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.caption.copyWith(color: p.textSecondary),
                      ),
                    ),
                    if (customer.isRepeat)
                      const SxChip(label: 'Repeat', tone: SxChipTone.positive),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
