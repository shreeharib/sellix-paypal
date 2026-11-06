import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'stock_actions.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

/// One product. The route carries a variant id, because a ledger row is a variant, and the catalogue
/// is searched for its product.
class ProductScreen extends ConsumerWidget {
  const ProductScreen(this.variantId, {super.key});

  final String variantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(stockViewProvider);
    final item = value.value?.byVariant(variantId);
    final editable = item?.productId != null;
    return SxScaffold(
      floating: editable
          ? SxBottomCta(
              label: 'Edit product',
              icon: TablerIcons.pencil,
              onTap: () => context.push(Routes.editProduct(variantId)),
            )
          : null,
      body: SxAsyncView<StockView>(
        value: value,
        onRetry: () {
          ref.invalidate(todayProvider);
          ref.invalidate(catalogProvider);
        },
        loading: const SxSkeletonList(topHeight: 240),
        isEmpty: (v) => v.byVariant(variantId) == null,
        empty: Column(
          children: [
            const SxDetailHeader(title: 'Product', fallback: Routes.stock),
            Expanded(
              child: const SxEmptyState(
                icon: TablerIcons.package_off,
                title: 'This product isn’t in your catalogue',
              ),
            ),
          ],
        ),
        builder: (context, view) => _Body(item: view.byVariant(variantId)!),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.sx;
    final actions = StockActions(context);
    final terms = ShopTerms.of(ref.watch(shopAnswersProvider).value?.category, item.attributes);
    final details = terms.read(item.attributes);
    final carried = ref.read(carriedLogProvider).read(ref.watch(todayProvider).value?.businessDate ?? DateTime(0));
    final carriedHere = carried[item.variantId] ?? 0;
    final left = item.available;
    final choice = ShelfChoice.of(item.stockMode, item.shelfLifeDays);
    final cost = item.costPriceMinor ?? 0;
    final margin = cost > 0 && item.priceMinor > 0
        ? ((item.priceMinor - cost) * 100 + item.priceMinor ~/ 2) ~/ item.priceMinor
        : null;
    Widget side(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: child,
    );
    return SxScrollList(
      onRefresh: () async {
        ref.invalidate(todayProvider);
        ref.invalidate(catalogProvider);
        await ref.read(stockViewProvider.future);
      },
      children: [
        Stack(
          children: [
            Container(
              height: 240,
              color: p.tile,
              alignment: Alignment.center,
              child: item.baseImageUrl == null
                  ? Icon(TablerIcons.package, size: 56, color: p.textSecondary)
                  : Image.network(
                      item.baseImageUrl!,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(TablerIcons.package, size: 56, color: p.textSecondary),
                    ),
            ),
            Positioned(
              top: SxSpace.s8,
              left: SxSpace.screen,
              right: SxSpace.screen,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  SxBackButton(fallback: Routes.stock),
                  // BACKEND GAP: products have no public link, so there is nothing to share yet.
                  SxIconButton(icon: TablerIcons.share, semanticLabel: 'Sharing isn’t available yet', onTap: null),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: SxSpace.s16),
        side(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: SxSpace.s8,
                runSpacing: SxSpace.s8,
                children: [
                  if (!item.counted)
                    const SxChip(label: 'On sale', tone: SxChipTone.positive, icon: TablerIcons.circle_check)
                  else if (left > 0)
                    const SxChip(label: 'On sale today', tone: SxChipTone.positive, icon: TablerIcons.circle_check)
                  else if (item.live)
                    const SxChip(label: 'Sold out', icon: TablerIcons.ban)
                  else
                    const SxChip(label: 'Not on sale today'),
                  SxChip(label: item.shelf, icon: TablerIcons.hourglass),
                ],
              ),
              const SizedBox(height: SxSpace.s12),
              Text(item.name, style: SxText.titleL.copyWith(color: p.textPrimary)),
              const SizedBox(height: SxSpace.s4),
              Row(
                children: [
                  Text(item.priceLabel, style: SxText.titleM.copyWith(color: p.textPrimary)),
                  if (item.variant != null) ...[
                    const SizedBox(width: SxSpace.s8),
                    Text('· ${item.variant}', style: SxText.bodyS.copyWith(color: p.textSecondary)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (item.counted && item.made > 0) ...[
          const SizedBox(height: SxSpace.s16),
          side(
            SxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Today', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                      Text('$left left', style: SxText.caption.copyWith(color: p.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: SxSpace.s12),
                  Row(
                    children: [
                      for (final (label, n) in [
                        ('Stock', item.made),
                        ('On hold', item.held),
                        ('Sold', item.row?.sold ?? 0),
                        ('At shop', item.row?.counterSales ?? 0),
                      ])
                        Expanded(
                          child: Column(
                            children: [
                              Text('$n', style: SxText.stat.copyWith(color: p.textPrimary)),
                              Text(label, style: SxText.micro.copyWith(color: p.textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SxSpace.s12),
                  LedgerBar(item: item),
                  if (carriedHere > 0) ...[
                    const SizedBox(height: SxSpace.s8),
                    Text(
                      '$carriedHere from yesterday. ${item.shelf}.',
                      style: SxText.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: SxSpace.s12),
                  SxButtonRow(
                    children: [
                      SxButton(
                        label: 'Add stock',
                        kind: SxButtonKind.secondary,
                        icon: TablerIcons.plus,
                        onTap: () => actions.restock(context, item),
                      ),
                      SxButton(
                        label: 'Fix count',
                        kind: SxButtonKind.secondary,
                        icon: TablerIcons.pencil,
                        onTap: () => actions.fixCount(context, item),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: SxSpace.s12),
        side(
          SxGroup(
            children: [
              if (item.counted)
                SxSwitchRow(
                  title: 'On sale today',
                  subtitle: 'sellix offers it to customers',
                  icon: TablerIcons.circle_check,
                  value: left > 0,
                  onChanged: (on) => on ? actions.restock(context, item) : actions.takeOffSale(item),
                )
              else
                SxListRow(
                  title: 'No count needed',
                  subtitle: noCountWhy(item.stockMode),
                  icon: TablerIcons.circle_check,
                ),
              SxListRow(
                title: item.shelf,
                subtitle: choice.line,
                icon: TablerIcons.hourglass,
                chevron: true,
                onTap: () => actions.changeShelf(context, item),
              ),
              if (margin != null)
                SxListRow(
                  title: 'Cost ${money(cost, item.currency)} · margin $margin%',
                  icon: TablerIcons.coin_rupee,
                ),
              SxListRow(
                title: terms.attrLabel,
                subtitle: details.isEmpty ? 'Not added. sellix asks you when a customer asks.' : details.join(', '),
                icon: TablerIcons.list_details,
              ),
            ],
          ),
        ),
        const SxSectionHeader(title: 'Customers also call it'),
        side(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SxSpace.s8,
            children: [
              if (item.aliases.isNotEmpty)
                Wrap(
                  spacing: SxSpace.s8,
                  runSpacing: SxSpace.s8,
                  children: [for (final a in item.aliases) SxChip(label: a.aliasText)],
                ),
              const SxAiNote('I use these names to find it when a customer asks.'),
            ],
          ),
        ),
        // BACKEND GAP: no per-product sales history, so the prototype's "This week" card is dropped.
        const SizedBox(height: SxSpace.s16),
        side(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SxSpace.s4,
            children: [
              // BACKEND GAP: PATCH /v1/products/{id} doesn't accept is_active, so nothing can remove it.
              const SxLinkButton(label: 'Remove product', icon: TablerIcons.trash, onTap: null),
              Text(
                'Removing products isn’t available yet.',
                style: SxText.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
