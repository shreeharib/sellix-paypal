import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../design/design.dart';
import 'settings_providers.dart';

class ShopCategory {
  const ShopCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

/// The same categories as onboarding.
const shopCategories = [
  ShopCategory('fashion', 'Clothing', TablerIcons.hanger),
  ShopCategory('footwear', 'Shoes', TablerIcons.shoe),
  ShopCategory('food', 'Food and sweets', TablerIcons.cake),
  ShopCategory('beauty', 'Beauty and skincare', TablerIcons.droplet),
  ShopCategory('jewellery', 'Jewellery and accessories', TablerIcons.diamond),
  ShopCategory('home', 'Home and decor', TablerIcons.lamp),
  ShopCategory('handmade', 'Handmade and gifts', TablerIcons.gift),
  ShopCategory('plants', 'Plants and flowers', TablerIcons.plant_2),
  ShopCategory('other', 'Other', TablerIcons.dots),
];

/// `answers.category` is free text: a category id, a label, or what the merchant typed for Other.
ShopCategory categoryOf(String? saved) {
  final text = saved?.trim().toLowerCase() ?? '';
  for (final c in shopCategories) {
    if (c.id == text || c.label.toLowerCase() == text) return c;
  }
  return shopCategories.last;
}

/// The words to show for the saved category.
String categoryLabel(String? saved) {
  final text = saved?.trim() ?? '';
  if (text.isEmpty) return 'Not set';
  final c = categoryOf(text);
  return c.id == 'other' ? text : c.label;
}

/// Opens the sheet and saves the pick, with the prototype's Undo.
Future<void> changeShopType(BuildContext context, String? current) async {
  final container = containerOf(context);
  final picked = await showSxSheet<String>(
    context,
    title: 'Shop type',
    subtitle: 'sellix changes its words, questions and samples to fit your shop.',
    builder: (_) => _ShopTypeSheet(current: current),
  );
  if (picked == null || picked == current || !context.mounted) return;
  try {
    await saveAnswers(container, (a) => a.copyWith(category: picked));
  } on ApiException catch (error) {
    if (context.mounted) showSxSnack(context, sxErrorMessage(error));
    return;
  }
  if (!context.mounted) return;
  showSxSnack(
    context,
    'Shop type is now $picked.',
    icon: TablerIcons.check,
    action: 'Undo',
    onAction: () async {
      try {
        await saveAnswers(container, (a) => a.copyWith(category: current));
      } on ApiException catch (error) {
        if (context.mounted) showSxSnack(context, sxErrorMessage(error));
      }
    },
  );
}

class _ShopTypeSheet extends StatefulWidget {
  const _ShopTypeSheet({required this.current});

  final String? current;

  @override
  State<_ShopTypeSheet> createState() => _ShopTypeSheetState();
}

class _ShopTypeSheetState extends State<_ShopTypeSheet> {
  late final bool _hasSaved = widget.current?.trim().isNotEmpty ?? false;
  late bool _other = _hasSaved && categoryOf(widget.current).id == 'other';
  late final _label = TextEditingController(text: _other ? widget.current : '');
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _saveOther() {
    final text = _label.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Type what you sell first');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _hasSaved ? categoryOf(widget.current).id : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s8,
      children: [
        for (final c in shopCategories)
          SxChoiceCard(
            title: c.label,
            icon: c.icon,
            check: true,
            selected: c.id == 'other' ? _other : !_other && selected == c.id,
            onTap: () {
              if (c.id == 'other') {
                setState(() => _other = true);
              } else {
                Navigator.of(context).pop(c.label);
              }
            },
          ),
        if (_other) ...[
          SxField(
            controller: _label,
            hint: 'What do you sell?',
            errorText: _error,
            maxLength: answerShortLimit,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          SxButton(label: 'Save shop type', fullWidth: true, onTap: _saveOther),
        ],
      ],
    );
  }
}
