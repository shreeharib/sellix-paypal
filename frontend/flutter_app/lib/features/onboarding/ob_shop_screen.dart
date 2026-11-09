import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_categories.dart';
import 'ob_common.dart';

class ObShopScreen extends ConsumerStatefulWidget {
  const ObShopScreen({super.key});

  @override
  ConsumerState<ObShopScreen> createState() => _ObShopScreenState();
}

class _ObShopScreenState extends ConsumerState<ObShopScreen> with ObSaving {
  final _name = TextEditingController();
  final _other = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _pickup = TextEditingController();
  bool _ready = false;
  ObCategory? _category;
  String? _nameError;
  String? _categoryError;

  @override
  void dispose() {
    for (final c in [_name, _other, _area, _city, _pickup]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load() {
    final draft = ref.watch(onboardingDraftProvider).value;
    if (_ready || draft == null) return;
    _ready = true;
    final a = draft.answers;
    _name.text = draft.shopName;
    _category = obCategoryOf(a.category);
    if (_category == obOtherCategory) _other.text = a.category ?? '';
    _area.text = a.area ?? '';
    _city.text = a.city ?? '';
    _pickup.text = a.address ?? '';
  }

  void _continue() {
    final name = _name.text.trim();
    final other = _other.text.trim();
    final category = _category;
    final noCategory = category == null || (category == obOtherCategory && other.isEmpty);
    setState(() {
      _nameError = name.isEmpty ? 'Enter your shop’s name. Customers see it in every chat.' : null;
      _categoryError = noCategory
          ? (category == obOtherCategory ? 'Tell sellix what you sell.' : 'Pick what you sell.')
          : null;
    });
    if (name.isEmpty || noCategory) {
      HapticFeedback.heavyImpact();
      return;
    }
    final saved = category == obOtherCategory ? other : category.label;
    saveThen(
      shopName: name,
      // A shop type picked in Settings stays while the category is the same; a different category
      // goes back to the backend choosing the type from it.
      (a) => a.copyWith(
        category: saved,
        shopType: saved == a.category ? a.shopType : null,
        area: obText(_area.text),
        city: obText(_city.text),
        address: obText(_pickup.text),
      ),
      () => context.push(Routes.obTalk),
    );
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final p = context.sx;
    final picked = _category;
    return ObStepFrame(
      step: 0,
      fraction: 0.5,
      fallback: Routes.connected,
      title: 'Tell sellix about your shop',
      why: 'Customers ask these first. sellix answers them for you.',
      saving: saving,
      onContinue: _ready ? _continue : null,
      children: [
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 2,
          child: SxField(
            controller: _name,
            label: 'Shop name',
            hint: 'Your shop name',
            maxLength: 120,
            errorText: _nameError,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ObLabel('What do you sell?'),
              _CategoryGrid(
                selected: picked,
                onPick: (c) => setState(() {
                  _category = c;
                  _categoryError = null;
                }),
              ),
              if (picked != null && picked != obOtherCategory)
                Padding(
                  padding: const EdgeInsets.only(top: SxSpace.s8, left: SxSpace.s4),
                  child: Text(picked.examples, style: SxText.caption.copyWith(color: p.textSecondary)),
                ),
              if (picked == obOtherCategory)
                Padding(
                  padding: const EdgeInsets.only(top: SxSpace.s8),
                  child: SxField(
                    controller: _other,
                    label: 'What do you sell?',
                    hint: 'Pet food, books, phone covers',
                    maxLength: 60,
                    onChanged: (_) {
                      if (_categoryError != null) setState(() => _categoryError = null);
                    },
                  ),
                ),
              if (_categoryError != null)
                Padding(
                  padding: const EdgeInsets.only(top: SxSpace.s8, left: SxSpace.s4),
                  child: Text(_categoryError!, style: SxText.caption.copyWith(color: p.errorText)),
                ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        SxFadeUp(
          index: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SxField(controller: _area, label: 'Area (optional)', hint: 'Anna Nagar', maxLength: 200),
              ),
              const SizedBox(width: SxSpace.s8),
              Expanded(
                child: SxField(controller: _city, label: 'City (optional)', hint: 'Chennai', maxLength: 200),
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        SxFadeUp(
          index: 5,
          child: SxField(
            controller: _pickup,
            label: 'Pickup address (optional)',
            hint: 'Door number, street, landmark',
            maxLines: 3,
            maxLength: 1500,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(SxSpace.s4, 6, SxSpace.s4, 0),
          child: Text(
            'Online only? Leave this empty. sellix tells customers you deliver.',
            style: SxText.caption.copyWith(color: p.textSecondary),
          ),
        ),
        const SizedBox(height: SxSpace.s12),
        const SxAiNote('I share a pickup address only after a customer confirms an order.'),
      ],
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.selected, required this.onPick});

  final ObCategory? selected;
  final ValueChanged<ObCategory> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 2 * SxSpace.s8) / 3;
        return Wrap(
          spacing: SxSpace.s8,
          runSpacing: SxSpace.s8,
          children: [
            for (final c in obCategories)
              SizedBox(
                width: width,
                child: _CategoryTile(category: c, on: c == selected, onTap: () => onPick(c)),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.on, required this.onTap});

  final ObCategory category;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final fg = on ? p.onPrimary : p.textPrimary;
    return Semantics(
      selected: on,
      button: true,
      child: SxPressable(
        small: true,
        onTap: onTap,
        child: AnimatedContainer(
          duration: SxMotion.base,
          curve: SxMotion.curve,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.fromLTRB(6, SxSpace.s12, 6, 10),
          decoration: BoxDecoration(
            color: on ? p.primary : p.card,
            borderRadius: BorderRadius.circular(SxRadius.attach),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon, size: 24, color: fg),
                    const SizedBox(height: 6),
                    Text(
                      category.label,
                      textAlign: TextAlign.center,
                      style: SxText.caption.copyWith(height: 16 / 13, color: fg),
                    ),
                  ],
                ),
              ),
              // Selected is never shown by colour alone.
              if (on) Positioned(top: -4, right: 0, child: Icon(TablerIcons.check, size: 16, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
