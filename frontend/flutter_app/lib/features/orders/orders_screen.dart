import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/nav_badges.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import '../stock/stock_providers.dart';
import 'order_logic.dart';
import 'order_row.dart';
import 'orders_providers.dart';

const _tabs = [
  (OrderTab.todo, 'To do'),
  (OrderTab.moving, 'In progress'),
  (OrderTab.waiting, 'Waiting payment'),
  (OrderTab.done, 'Done'),
  (OrderTab.all, 'All'),
];

const _emptyStates = {
  OrderTab.todo: (
    TablerIcons.checks,
    'Nothing to do now',
    'New orders show here first.',
  ),
  OrderTab.moving: (
    TablerIcons.truck_delivery,
    'Nothing on the way',
    'Orders that wait for pickup show here.',
  ),
  OrderTab.waiting: (
    TablerIcons.clock,
    'No payments to wait for',
    'Orders show here until the customer pays.',
  ),
  OrderTab.done: (
    TablerIcons.flag,
    'No finished orders yet',
    'Delivered, cancelled and expired orders show here.',
  ),
  OrderTab.all: (
    TablerIcons.receipt_off,
    'No orders yet',
    'Orders sellix takes in your DMs show here.',
  ),
};

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _search = TextEditingController();
  OrderTab _tab = OrderTab.todo;
  SalesPeriod _period = SalesPeriod.day;
  bool _searching = false;
  int? _pushedBadge;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }

  Future<void> _reload() {
    ref.invalidate(conversationsProvider);
    ref.invalidate(todayProvider);
    return ref.refresh(ordersProvider.future);
  }

  void _pushBadge(int count) {
    if (_pushedBadge == count) return;
    _pushedBadge = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navBadgesProvider.notifier).update(ordersToAct: count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);
    // A customer name is a nicety on this screen, so a failure here doesn't hide the orders.
    final handles = handlesById(ref.watch(conversationsProvider).value ?? const []);
    final businessDate = ref.watch(todayProvider).value?.businessDate ?? dateOnly(DateTime.now());
    return SxScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxPageTitle(
            title: 'Orders',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: SxSpace.s8,
              children: [
                SxIconButton(
                  icon: TablerIcons.search,
                  semanticLabel: 'Search orders',
                  onTap: _toggleSearch,
                ),
                SxIconButton(
                  icon: TablerIcons.users,
                  semanticLabel: 'Customers',
                  onTap: () => context.push(Routes.customers),
                ),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s12, SxSpace.screen, 0),
              child: SxField(
                controller: _search,
                hint: 'Name or order number',
                autofocus: true,
                onChanged: (_) => setState(() {}),
                trailing: SxIconButton(
                  icon: TablerIcons.x,
                  semanticLabel: 'Clear search',
                  ghost: true,
                  onTap: _toggleSearch,
                ),
              ),
            ),
          const SizedBox(height: SxSpace.s12),
          Expanded(
            child: SxAsyncView<List<Order>>(
              value: orders,
              onRetry: () => ref.invalidate(ordersProvider),
              loading: const SxSkeletonList(topHeight: 160),
              builder: (context, list) {
                _pushBadge(ordersToAct(list).length);
                return _body(list, handles, businessDate);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<Order> list, Map<String, String> handles, DateTime businessDate) {
    final query = _search.text.trim().toLowerCase().replaceFirst(RegExp('^#'), '');
    return SxScrollList(
      onRefresh: _reload,
      children: query.isNotEmpty
          ? _searchResults(list, handles, query)
          : [
              _Anchor(
                orders: list,
                handles: handles,
                businessDate: businessDate,
                period: _period,
                onPeriod: (value) => setState(() => _period = value),
              ),
              const SizedBox(height: SxSpace.s12),
              _TabBar(
                orders: list,
                selected: _tab,
                onSelect: (value) => setState(() => _tab = value),
              ),
              const SizedBox(height: SxSpace.s8),
              ..._tabList(list, handles, businessDate),
            ],
    );
  }

  List<Widget> _searchResults(List<Order> list, Map<String, String> handles, String query) {
    final rows = list.where((order) {
      return customerNameOf(order, handles).toLowerCase().contains(query) ||
          order.number.toString().contains(query);
    }).toList();
    return [
      _SectionLabel('${rows.length} order${rows.length == 1 ? '' : 's'} found'),
      if (rows.isEmpty)
        const SxEmptyState(
          icon: TablerIcons.search,
          title: 'No orders match',
          body: 'Try another name or order number.',
        ),
      for (final order in rows)
        _padded(OrderRow(order: order, name: customerNameOf(order, handles))),
    ];
  }

  List<Widget> _tabList(List<Order> list, Map<String, String> handles, DateTime businessDate) {
    final shown = ordersInTab(_tab, list);
    if (shown.isEmpty) {
      final (icon, title, body) = _emptyStates[_tab]!;
      return [SxEmptyState(icon: icon, title: title, body: body)];
    }
    return [
      for (final section in sectionsOf(_tab, shown, businessDate))
        if (section.orders.isNotEmpty) ...[
          if (section.title.isNotEmpty) _SectionLabel(section.title),
          for (final (index, order) in section.orders.indexed)
            _padded(
              SxFadeUp(
                index: index,
                child: OrderRow(
                  order: order,
                  name: customerNameOf(order, handles),
                  quick: _tab == OrderTab.todo,
                ),
              ),
            ),
        ],
    ];
  }

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(SxSpace.screen, 0, SxSpace.screen, SxSpace.listGap),
    child: child,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, SxSpace.s8, 22, SxSpace.s8),
      child: Text(text, style: SxText.micro.copyWith(color: context.sx.textSecondary)),
    );
  }
}

/// "Do this next", then the sales summary. The period only changes the summary, never the list.
class _Anchor extends StatelessWidget {
  const _Anchor({
    required this.orders,
    required this.handles,
    required this.businessDate,
    required this.period,
    required this.onPeriod,
  });

  final List<Order> orders;
  final Map<String, String> handles;
  final DateTime businessDate;
  final SalesPeriod period;
  final ValueChanged<SalesPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final toAct = ordersToAct(orders);
    final first = toAct.firstOrNull;
    final sales = salesFor(orders, period, businessDate);
    final main = sales.mainCurrency;
    final notes = [
      '${sales.count} order${sales.count == 1 ? '' : 's'}',
      if (sales.others.isNotEmpty) 'plus ${sales.others.join(', ')}',
      if (ordersClipped(orders)) 'latest $ordersWindow only',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: SxAnchorCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first == null
                ? const _NextHead(
                    title: 'You are up to date',
                    sub: 'New orders show here when they come.',
                  )
                : _NextHead(
                    title: _nextTitle(first),
                    sub: _nextSub(first),
                    count: toAct.length,
                    onTap: () => context.push(Routes.order(first.id)),
                  ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SxSpace.s12),
              child: Divider(height: 1, thickness: 1, color: p.anchorLine),
            ),
            Row(
              spacing: SxSpace.s8,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SxCountUp(
                        value: sales.mainMinor,
                        style: SxText.stat.copyWith(color: p.onAnchor),
                        duration: SxMotion.slow,
                        format: (minor) => main == null ? money(0, 'INR') : money(minor, main),
                      ),
                      Text(
                        notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.micro.copyWith(color: p.onAnchorSecondary),
                      ),
                    ],
                  ),
                ),
                for (final (value, label) in const [
                  (SalesPeriod.day, 'Today'),
                  (SalesPeriod.week, 'Week'),
                  (SalesPeriod.month, 'Month'),
                ])
                  SxPressable(
                    small: true,
                    semanticLabel: label,
                    onTap: () => onPeriod(value),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: value == period ? p.anchorRaised : null,
                          borderRadius: BorderRadius.circular(SxRadius.pill),
                        ),
                        child: Text(
                          label,
                          style: SxText.caption.copyWith(
                            color: value == period ? p.onAnchor : p.onAnchorSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _nextTitle(Order order) {
    final name = customerNameOf(order, handles);
    if (isRefundDue(order)) {
      return 'Refund $name ${money(order.totalMinor, order.currency)}';
    }
    return nextStepOf(order)!.task(name);
  }

  String _nextSub(Order order) {
    if (isRefundDue(order)) return '#${order.number} · Cancelled, not refunded yet';
    final due = dueText(order);
    return '#${order.number}${due == null ? '' : ' · $due'}';
  }
}

class _NextHead extends StatelessWidget {
  const _NextHead({required this.title, required this.sub, this.count, this.onTap});

  final String title;
  final String sub;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final body = Row(
      spacing: SxSpace.s8,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SxSpace.s4,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Do this next', style: SxText.caption.copyWith(color: p.onAnchorSecondary)),
                  if (count != null)
                    Text(
                      '$count to do',
                      style: SxText.caption.copyWith(
                        color: p.attentionOnAnchor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SxText.titleM.copyWith(color: p.onAnchor),
              ),
              Text(sub, style: SxText.caption.copyWith(color: p.onAnchorSecondary)),
            ],
          ),
        ),
        if (onTap != null) Icon(TablerIcons.chevron_right, size: 20, color: p.onAnchorSecondary),
      ],
    );
    return onTap == null ? body : SxPressable(onTap: onTap, child: body);
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.orders, required this.selected, required this.onSelect});

  final List<Order> orders;
  final OrderTab selected;
  final ValueChanged<OrderTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (tab, label) in _tabs)
            Expanded(
              child: Builder(
                builder: (context) {
                  final on = tab == selected;
                  final count = ordersInTab(tab, orders).length;
                  final countColor = on
                      ? p.onPrimary
                      : (tab == OrderTab.todo && count > 0 ? p.attentionText : p.textPrimary);
                  return SxPressable(
                    small: true,
                    semanticLabel: '$label, $count orders',
                    onTap: () => onSelect(tab),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 66),
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                      decoration: BoxDecoration(
                        color: on ? p.primary : null,
                        borderRadius: BorderRadius.circular(SxRadius.tile),
                      ),
                      child: Column(
                        spacing: 2,
                        children: [
                          Text(
                            '$count',
                            style: SxText.bodyStrong.copyWith(
                              color: countColor,
                              fontSize: 18,
                              height: 22 / 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: SxText.micro.copyWith(
                              color: on ? p.onPrimary : p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
