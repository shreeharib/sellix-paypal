import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import 'today_providers.dart';

const _currencies = ['INR', 'USD', 'GBP', 'EUR', 'AUD', 'CAD', 'SGD'];

/// The morning stock update: today's items, prices and quantities.
Future<void> showStockEditor(BuildContext context, List<StockRow> current) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _StockEditor(current: current),
    );

class _LineDraft {
  _LineDraft({String product = '', String variant = '', String price = '', String quantity = '', this.currency = 'INR'})
      : product = TextEditingController(text: product),
        variant = TextEditingController(text: variant),
        price = TextEditingController(text: price),
        quantity = TextEditingController(text: quantity);

  factory _LineDraft.from(StockRow row) => _LineDraft(
        product: row.product,
        variant: row.variant ?? '',
        price: _priceText(row.priceMinor),
        quantity: '${row.opening}',
        currency: row.currency,
      );

  final TextEditingController product;
  final TextEditingController variant;
  final TextEditingController price;
  final TextEditingController quantity;
  String currency;

  /// Null when the line isn't complete (product, a valid price and quantity).
  StockLine? toLine() {
    final name = product.text.trim();
    final priceMinor = _parsePrice(price.text);
    final count = int.tryParse(quantity.text.trim());
    if (name.isEmpty || priceMinor == null || count == null || count < 0) return null;
    final variantName = variant.text.trim();
    return StockLine(
      product: name,
      variant: variantName.isEmpty ? null : variantName,
      priceMinor: priceMinor,
      currency: currency,
      quantity: count,
    );
  }

  void dispose() {
    product.dispose();
    variant.dispose();
    price.dispose();
    quantity.dispose();
  }

  static String _priceText(int minor) =>
      minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

  /// "60" or "70.50" in rupees/dollars -> minor units; null if invalid.
  static int? _parsePrice(String text) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,2}))?\s*$').firstMatch(text);
    if (match == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return int.parse(match.group(1)!) * 100 + int.parse(fraction);
  }
}

class _StockEditor extends ConsumerStatefulWidget {
  const _StockEditor({required this.current});

  final List<StockRow> current;

  @override
  ConsumerState<_StockEditor> createState() => _StockEditorState();
}

class _StockEditorState extends ConsumerState<_StockEditor> {
  late final List<_LineDraft> _lines = widget.current.isEmpty
      ? [_LineDraft()]
      : [for (final row in widget.current) _LineDraft.from(row)];
  bool _saving = false;

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final lines = [for (final draft in _lines) draft.toLine()];
    if (lines.isEmpty || lines.any((line) => line == null)) {
      showMessage(context, context.l10n.stockEditorInvalid);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).setOpeningStock(lines.cast<StockLine>());
      ref.invalidate(todayProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ContentWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              child: Text(l10n.todayStockTitle, style: Theme.of(context).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(Insets.md),
                children: [
                  for (final (index, line) in _lines.indexed) ...[
                    _LineFields(
                      line: line,
                      onCurrencyChanged: (currency) => setState(() => line.currency = currency),
                      onRemove: _lines.length == 1
                          ? null
                          : () => setState(() => _lines.removeAt(index).dispose()),
                    ),
                    const SizedBox(height: Insets.md),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _lines.add(_LineDraft())),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.stockEditorAddItem),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.md, 0, Insets.md, Insets.md),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(l10n.stockEditorSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineFields extends StatelessWidget {
  const _LineFields({required this.line, required this.onCurrencyChanged, required this.onRemove});

  final _LineDraft line;
  final ValueChanged<String> onCurrencyChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.product,
                    decoration: InputDecoration(labelText: l10n.stockEditorProduct),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: l10n.stockEditorRemoveItem,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            TextField(
              controller: line.variant,
              decoration: InputDecoration(labelText: l10n.stockEditorVariant),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.price,
                    decoration: InputDecoration(labelText: l10n.stockEditorPrice),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                DropdownButton<String>(
                  value: line.currency,
                  onChanged: (value) => value == null ? null : onCurrencyChanged(value),
                  items: [
                    for (final currency in _currencies)
                      DropdownMenuItem(value: currency, child: Text(currency)),
                  ],
                ),
                const SizedBox(width: Insets.sm),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: line.quantity,
                    decoration: InputDecoration(labelText: l10n.stockEditorQuantity),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
