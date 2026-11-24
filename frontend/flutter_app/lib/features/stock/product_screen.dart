import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
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
    final schema = ref.watch(shopSchemaProvider);
    final carried = ref.read(carriedLogProvider).read(ref.watch(todayProvider).value?.businessDate ?? DateTime(0));
    final carriedHere = carried[item.variantId] ?? 0;
    final left = item.available;
    final choice = ShelfChoice.of(item.stockMode, item.shelfLifeDays);
    final canChangeStock = StockTypeQuestion.isNeeded(schema, choice, keepMode: item.stockMode);
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
                  if (kShowComingSoon)
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
              if (item.productId != null)
                SxListRow(
                  title: 'Name',
                  subtitle: item.name,
                  icon: TablerIcons.pencil,
                  onTap: () => _rename(context, ref, item),
                ),
              if (item.productId != null) ...[
                SxListRow(
                  title: item.availableOn == null ? 'Sold every day' : 'One-day item',
                  subtitle: item.availableOn == null
                      ? 'Tap to sell it on one day only, as a pre-order'
                      : 'Sold on ${_dayWords(item.availableOn!)} only. Tap to change',
                  icon: TablerIcons.calendar_event,
                  onTap: () => _pickDay(context, ref, item),
                ),
                if (item.availableOn != null)
                  SxListRow(
                    title: 'Last day to order',
                    value: item.orderByDate == null ? 'Not set' : _dayWords(item.orderByDate!),
                    icon: TablerIcons.clock,
                    onTap: () => _pickOrderBy(context, ref, item),
                  ),
              ],
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
                // A shop type with one way to stock has nothing to change here.
                chevron: canChangeStock,
                onTap: canChangeStock ? () => actions.changeShelf(context, item) : null,
              ),
              if (margin != null)
                SxListRow(
                  title: 'Cost ${money(cost, item.currency)} · margin $margin%',
                  icon: TablerIcons.coin_rupee,
                ),
              for (final field in schema.detailFields)
                SxListRow(
                  title: field.label,
                  subtitle: field.text(item.attributes).isEmpty
                      ? 'Not added. sellix asks you when a customer asks.'
                      : field.text(item.attributes),
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
              if (item.productId != null) ...[
                SxLinkButton(
                  label: 'Remove product',
                  icon: TablerIcons.trash,
                  color: p.errorText,
                  onTap: () => _remove(context, ref, item),
                ),
                Text(
                  'It leaves your stock lists and sellix stops offering it. Past orders keep it.',
                  style: SxText.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `today`, `tomorrow` or the date, inside a sentence.
String _dayWords(DateTime day) {
  final label = dayLabel(day);
  return label == 'Today' || label == 'Tomorrow' || label == 'Yesterday' ? label.toLowerCase() : label;
}

/// Reloads the lists a product change shows in.
void _refreshProducts(ProviderContainer container) => container
  ..invalidate(catalogProvider)
  ..invalidate(todayProvider);

Future<bool> _update(BuildContext context, String productId, ProductUpdate update, String done) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(sellixApiProvider).updateProduct(productId, update);
  } on ApiException catch (error) {
    if (context.mounted) showSxSnack(context, sxErrorMessage(error), icon: TablerIcons.alert_circle);
    return false;
  }
  _refreshProducts(container);
  if (context.mounted) showSxSnack(context, done, icon: TablerIcons.check, sellix: false);
  return true;
}

/// `PATCH is_active: false`, after asking. Undo brings it back.
Future<void> _remove(BuildContext context, WidgetRef ref, StockItem item) async {
  final yes = await showSxConfirm(
    context,
    title: 'Remove ${item.name}?',
    body: 'It leaves your stock lists and menus, and sellix stops offering it. Past orders keep it.',
    confirmLabel: 'Remove',
    confirmIcon: TablerIcons.trash,
  );
  if (!yes || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final api = container.read(sellixApiProvider);
  final productId = item.productId!;
  try {
    await api.updateProduct(productId, const ProductUpdate(isActive: false));
  } on ApiException catch (error) {
    if (context.mounted) showSxSnack(context, sxErrorMessage(error), icon: TablerIcons.alert_circle);
    return;
  }
  _refreshProducts(container);
  if (!context.mounted) return;
  showSxSnack(
    context,
    '${item.name} removed.',
    icon: TablerIcons.trash,
    sellix: false,
    action: 'Undo',
    onAction: () async {
      try {
        await api.updateProduct(productId, const ProductUpdate(isActive: true));
        _refreshProducts(container);
      } on ApiException {
        // The product stays removed; the stock list shows the truth.
      }
    },
  );
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.stock);
  }
}

/// A new name for the same product: it keeps its orders, stock and aliases.
Future<void> _rename(BuildContext context, WidgetRef ref, StockItem item) async {
  final name = await showSxSheet<String>(
    context,
    title: 'Rename',
    subtitle: 'Past orders keep the name they were placed with.',
    builder: (_) => _RenameSheet(current: item.name),
  );
  if (name == null || name == item.name || !context.mounted) return;
  await _update(context, item.productId!, ProductUpdate(name: name), 'Renamed to $name.');
}

/// Sell it on one day only, or every day again.
Future<void> _pickDay(BuildContext context, WidgetRef ref, StockItem item) async {
  final today = ref.read(todayProvider).value?.businessDate ?? dateOnly(DateTime.now());
  final current = item.availableOn;
  if (current != null) {
    final choice = await showSxSheet<String>(
      context,
      title: 'One-day item',
      subtitle: 'Sold on ${_dayWords(current)} only.',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          SxChoiceCard(
            title: 'Change the day',
            icon: TablerIcons.calendar_event,
            onTap: () => Navigator.of(sheet).pop('day'),
          ),
          SxChoiceCard(
            title: 'Sell it every day',
            subtitle: 'It stops being a one-day item',
            icon: TablerIcons.calendar_x,
            onTap: () => Navigator.of(sheet).pop('clear'),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'clear') {
      await _update(
        context,
        item.productId!,
        const ProductUpdate(clearAvailableOn: true, clearOrderByDate: true),
        '${item.name} is sold every day again.',
      );
      return;
    }
  }
  if (!context.mounted) return;
  final start = current != null && !current.isBefore(today) ? current : today;
  final picked = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: today,
    lastDate: addDays(today, 365),
    helpText: 'Day it is sold',
  );
  if (picked == null || !context.mounted) return;
  final day = dateOnly(picked);
  final orderBy = item.orderByDate;
  await _update(
    context,
    item.productId!,
    ProductUpdate(
      availableOn: day,
      // A last order day after the new day can't be right: it goes.
      clearOrderByDate: orderBy != null && orderBy.isAfter(day),
    ),
    '${item.name} is sold on ${_dayWords(day)} only.',
  );
}

/// The last day to order a one-day item: on or before its day.
Future<void> _pickOrderBy(BuildContext context, WidgetRef ref, StockItem item) async {
  final day = item.availableOn!;
  final today = ref.read(todayProvider).value?.businessDate ?? dateOnly(DateTime.now());
  final first = day.isBefore(today) ? day : today;
  final current = item.orderByDate;
  final picked = await showDatePicker(
    context: context,
    initialDate: current != null && !current.isBefore(first) && !current.isAfter(day) ? current : day,
    firstDate: first,
    lastDate: day,
    helpText: 'Last day to order',
  );
  if (picked == null || !context.mounted) return;
  final orderBy = dateOnly(picked);
  await _update(
    context,
    item.productId!,
    ProductUpdate(orderByDate: orderBy),
    'Orders close ${_dayWords(orderBy)}.',
  );
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.current});

  final String current;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _name = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _error = 'Type a name.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        SxField(
          controller: _name,
          label: 'Product name',
          errorText: _error,
          maxLength: 200,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        SxButton(label: 'Save name', fullWidth: true, onTap: _save),
      ],
    );
  }
}
