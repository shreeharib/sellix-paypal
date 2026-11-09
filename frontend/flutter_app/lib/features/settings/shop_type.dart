import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../design/design.dart';
import 'settings_providers.dart';

/// The id the backend uses for "something else": it also takes what the merchant types.
const otherShopType = 'other';

/// The icon for a backend shop type id.
IconData shopTypeIcon(String? id) => switch (id) {
  'bakery' => TablerIcons.cake,
  'jewellery' => TablerIcons.diamond,
  'beauty' => TablerIcons.droplet,
  'plants' => TablerIcons.plant_2,
  'handmade_gifts' => TablerIcons.gift,
  'dress_shop' => TablerIcons.hanger,
  _ => TablerIcons.dots,
};

/// A shop made before shop types: its `category` is free text, matched here only to pick an icon.
class _LegacyCategory {
  const _LegacyCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

const _legacyCategories = [
  _LegacyCategory('fashion', 'Clothing', TablerIcons.hanger),
  _LegacyCategory('footwear', 'Shoes', TablerIcons.shoe),
  _LegacyCategory('food', 'Food and sweets', TablerIcons.cake),
  _LegacyCategory('beauty', 'Beauty and skincare', TablerIcons.droplet),
  _LegacyCategory('jewellery', 'Jewellery and accessories', TablerIcons.diamond),
  _LegacyCategory('home', 'Home and decor', TablerIcons.lamp),
  _LegacyCategory('handmade', 'Handmade and gifts', TablerIcons.gift),
  _LegacyCategory('plants', 'Plants and flowers', TablerIcons.plant_2),
];

/// The icon for a shop's answers: its shop type, else what its free-text category looks like.
IconData shopIconOf(OnboardingAnswers? answers) {
  final type = answers?.shopType;
  if (type != null && type.isNotEmpty) return shopTypeIcon(type);
  final text = answers?.category?.trim().toLowerCase() ?? '';
  for (final c in _legacyCategories) {
    if (c.id == text || c.label.toLowerCase() == text) return c.icon;
  }
  return TablerIcons.dots;
}

/// The words to show for a shop's type: the label of its shop type, what the merchant typed for
/// Other, or the saved category of a shop that never picked a type.
String shopTypeLabel(OnboardingAnswers? answers, List<ShopTypeChoice> types) {
  final category = answers?.category?.trim() ?? '';
  final type = answers?.shopType;
  if (type != null && type.isNotEmpty) {
    if (type == otherShopType && category.isNotEmpty) return category;
    final label = types.where((t) => t.id == type).firstOrNull?.label;
    if (label != null) return label;
  }
  return category.isEmpty ? 'Not set' : category;
}

/// A shop type picked in the sheet, with the free text to keep as the category.
class _Pick {
  const _Pick(this.id, this.category);

  final String id;
  final String category;
}

/// Opens the sheet and saves the pick, with the prototype's Undo.
///
/// Saves `shop_type` (the backend's id) and `category` (its label, or what the merchant typed for
/// Other) together, and keeps every other answer.
Future<void> changeShopType(BuildContext context, OnboardingAnswers current) async {
  final container = containerOf(context);
  final picked = await showSxSheet<_Pick>(
    context,
    title: 'Shop type',
    subtitle: 'sellix changes its words, questions and samples to fit your shop.',
    builder: (_) => _ShopTypeSheet(current: current),
  );
  if (picked == null || !context.mounted) return;
  if (picked.id == current.shopType && picked.category == current.category) return;
  try {
    await saveAnswers(container, (a) => a.copyWith(shopType: picked.id, category: picked.category));
  } on ApiException catch (error) {
    if (context.mounted) showSxSnack(context, sxErrorMessage(error));
    return;
  }
  if (!context.mounted) return;
  showSxSnack(
    context,
    'Shop type is now ${picked.category}.',
    icon: TablerIcons.check,
    action: 'Undo',
    onAction: () async {
      try {
        await saveAnswers(
          container,
          (a) => a.copyWith(shopType: current.shopType, category: current.category),
        );
      } on ApiException catch (error) {
        if (context.mounted) showSxSnack(context, sxErrorMessage(error));
      }
    },
  );
}

class _ShopTypeSheet extends ConsumerStatefulWidget {
  const _ShopTypeSheet({required this.current});

  final OnboardingAnswers current;

  @override
  ConsumerState<_ShopTypeSheet> createState() => _ShopTypeSheetState();
}

class _ShopTypeSheetState extends ConsumerState<_ShopTypeSheet> {
  late final String? _saved = widget.current.shopType;
  late bool _other = _saved == otherShopType;

  /// Starts with what was typed for Other before, and empty otherwise (not the old category).
  late final _label = TextEditingController(text: _saved == otherShopType ? widget.current.category : '');
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
    Navigator.of(context).pop(_Pick(otherShopType, text));
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(shopTypesProvider).value ?? builtInShopTypes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s8,
      children: [
        for (final t in types)
          SxChoiceCard(
            title: t.label,
            icon: shopTypeIcon(t.id),
            check: true,
            selected: t.id == otherShopType ? _other : !_other && _saved == t.id,
            onTap: () {
              if (t.id == otherShopType) {
                setState(() => _other = true);
              } else {
                Navigator.of(context).pop(_Pick(t.id, t.label));
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
