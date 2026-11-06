import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'settings_providers.dart';
import 'shop_type.dart';

enum _View { cards, raw }

/// The agent's brief. Each topic edits the onboarding answers behind it, not the Markdown: the backend
/// rewrites the Markdown from those answers on every save, so a hand edit of the text would vanish.
class ShopProfileScreen extends ConsumerStatefulWidget {
  const ShopProfileScreen({super.key});

  @override
  ConsumerState<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _Topic {
  const _Topic(this.title, this.icon, this.read, this.write);

  final String title;
  final IconData icon;
  final String? Function(OnboardingAnswers) read;
  final OnboardingAnswers Function(OnboardingAnswers, String?) write;
}

final _textTopics = <_Topic>[
  _Topic('What you sell', TablerIcons.shopping_bag, (a) => a.products, (a, v) => a.copyWith(products: v)),
  _Topic('Pickup and delivery', TablerIcons.truck_delivery, (a) => a.fulfilment, (a, v) => a.copyWith(fulfilment: v)),
  _Topic('Custom orders', TablerIcons.pencil, (a) => a.customOrders, (a, v) => a.copyWith(customOrders: v)),
  _Topic('Cancellations and refunds', TablerIcons.receipt_refund, (a) => a.cancellations, (a, v) => a.copyWith(cancellations: v)),
  _Topic('Never promise', TablerIcons.ban, (a) => a.neverPromise, (a, v) => a.copyWith(neverPromise: v)),
  _Topic('Common questions', TablerIcons.help_circle, (a) => a.faqs, (a, v) => a.copyWith(faqs: v)),
];

class _ShopProfileScreenState extends ConsumerState<ShopProfileScreen> {
  _View _view = _View.cards;
  bool _saving = false;
  bool _done = false;
  String? _nameError;

  /// Topics opened for editing. Only these are written, so the rest always keep the server's value.
  final _textEditors = <String, TextEditingController>{};
  _ShopEditor? _shopEditor;
  _TalkEditor? _talkEditor;

  @override
  void dispose() {
    for (final c in _textEditors.values) {
      c.dispose();
    }
    _shopEditor?.dispose();
    _talkEditor?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final shop = _shopEditor;
    final talk = _talkEditor;
    if (_textEditors.isEmpty && shop == null && talk == null) {
      await finishSave(context, null, fallback: Routes.profile);
      return;
    }
    if (shop != null && shop.name.text.trim().isEmpty) {
      setState(() => _nameError = 'Type your shop name');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    try {
      await saveAnswers(containerOf(context), shopName: shop?.name.text.trim(), (answers) {
        var next = answers;
        for (final topic in _textTopics) {
          final editor = _textEditors[topic.title];
          if (editor != null) next = topic.write(next, blankToNull(editor.text));
        }
        if (shop != null) {
          next = next.copyWith(
            area: blankToNull(shop.area.text),
            city: blankToNull(shop.city.text),
            address: blankToNull(shop.address.text),
          );
        }
        if (talk != null) {
          next = next.copyWith(
            tone: talk.tone,
            emoji: talk.emoji,
            addressCustomers: blankToNull(talk.address.text),
            intro: blankToNull(talk.intro.text),
          );
        }
        return next;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSxSnack(context, sxErrorMessage(error));
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _done = true;
    });
    await finishSave(context, 'Saved. sellix uses this from now on.', fallback: Routes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final profile = ref.watch(shopProfileProvider);
    final version = profile.value;
    final meta = !profile.hasValue
        ? null
        : version == null
        ? 'Not written yet'
        : 'Version ${version.version} · ${updatedWords(version.createdAt)}';
    return SxScaffold(
      floating: onboarding.hasValue
          ? SxBottomCta(
              label: _done ? 'Saved' : 'Save',
              icon: TablerIcons.check,
              loading: _saving,
              done: _done,
              onTap: _done ? null : _save,
            )
          : null,
      body: Column(
        children: [
          SxDetailHeader(title: 'What sellix knows', meta: meta, fallback: Routes.profile),
          Expanded(
            child: SxAsyncView<Onboarding>(
              value: onboarding,
              onRetry: () => ref
                ..invalidate(onboardingProvider)
                ..invalidate(shopProfileProvider),
              loading: const SxSkeletonList(topHeight: 48),
              builder: (context, data) => _list(context, data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, Onboarding data) {
    final answers = data.answers;
    final profile = ref.watch(shopProfileProvider);
    final p = context.sx;
    return SxScrollList(
      children: [
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              SxSegmented<_View>(
                segments: const [SxSegment(_View.cards, 'By topic'), SxSegment(_View.raw, 'As text')],
                value: _view,
                onChanged: (v) => setState(() => _view = v),
              ),
              const SizedBox(height: SxSpace.s4),
              if (_view == _View.raw)
                if (profile.hasError && !profile.hasValue)
                  SxErrorState(error: profile.error, onRetry: () => ref.invalidate(shopProfileProvider))
                else
                  SxCard(
                    child: Text(
                      profile.isLoading && !profile.hasValue
                          ? ' '
                          : profile.value?.contentMd ?? 'sellix has nothing written yet. Fill in a topic and save.',
                      style: SxText.bodyS.copyWith(color: p.textPrimary),
                    ),
                  )
              else ...[
                SxRowCard(
                  icon: categoryOf(answers.category).icon,
                  title: 'Shop type',
                  meta: categoryLabel(answers.category),
                  onTap: () => changeShopType(context, answers.category),
                ),
                _shopCard(data),
                _talkCard(answers),
                for (final topic in _textTopics) _textCard(topic, answers),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required bool editing,
    required VoidCallback onOpen,
    required String? shown,
    required Widget Function() editor,
  }) {
    final p = context.sx;
    return SxCard(
      onTap: editing ? null : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: SxSpace.s12,
            children: [
              SxIconTile(icon: icon, size: 36),
              Expanded(child: Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary))),
              if (!editing) Icon(TablerIcons.pencil, size: 18, color: p.textSecondary),
            ],
          ),
          const SizedBox(height: SxSpace.s8),
          if (editing)
            editor()
          else
            Text(
              shown ?? 'Not set yet. Tap to add.',
              style: SxText.bodyS.copyWith(color: shown == null ? p.textSecondary : p.textPrimary),
            ),
        ],
      ),
    );
  }

  Widget _textCard(_Topic topic, OnboardingAnswers answers) {
    final editor = _textEditors[topic.title];
    return _card(
      title: topic.title,
      icon: topic.icon,
      editing: editor != null,
      shown: blankToNull(topic.read(answers) ?? ''),
      onOpen: () => setState(() {
        _textEditors[topic.title] = TextEditingController(text: topic.read(answers) ?? '');
      }),
      editor: () => SxField(
        controller: editor,
        onTile: true,
        autofocus: true,
        maxLines: 4,
        maxLength: answerLongLimit,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }

  Widget _shopCard(Onboarding data) {
    final a = data.answers;
    final place = [?blankToNull(a.area ?? ''), ?blankToNull(a.city ?? '')].join(', ');
    final words = [data.shopName, if (place.isNotEmpty) place, ?blankToNull(a.address ?? '')].join('. ');
    final editor = _shopEditor;
    return _card(
      title: 'Shop',
      icon: TablerIcons.building_store,
      editing: editor != null,
      shown: '$words.',
      onOpen: () => setState(() => _shopEditor = _ShopEditor(data)),
      editor: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          SxField(
            controller: editor!.name,
            label: 'Shop name',
            onTile: true,
            errorText: _nameError,
            maxLength: shopNameLimit,
          ),
          SxField(controller: editor.area, label: 'Area', onTile: true, maxLength: answerShortLimit),
          SxField(controller: editor.city, label: 'City', onTile: true, maxLength: answerShortLimit),
          SxField(controller: editor.address, label: 'Address', onTile: true, maxLines: 3, maxLength: answerLongLimit),
        ],
      ),
    );
  }

  Widget _talkCard(OnboardingAnswers a) {
    final editor = _talkEditor;
    final bits = [
      if (a.tone != null) a.tone == 'formal' ? 'Formal' : 'Friendly',
      if (a.emoji != null) a.emoji! ? 'light emoji' : 'no emoji',
      if (blankToNull(a.addressCustomers ?? '') != null) 'calls customers ${a.addressCustomers!.trim()}',
    ].join(', ');
    final intro = blankToNull(a.intro ?? '');
    final shown = [if (bits.isNotEmpty) '$bits.', ?intro].join(' ');
    final p = context.sx;
    return _card(
      title: 'How sellix talks',
      icon: TablerIcons.message_language,
      editing: editor != null,
      shown: blankToNull(shown),
      onOpen: () => setState(() => _talkEditor = _TalkEditor(a)),
      editor: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          SxSegmented<String>(
            segments: const [SxSegment('friendly', 'Friendly'), SxSegment('formal', 'Formal')],
            value: editor!.tone,
            onChanged: (v) => setState(() => editor.tone = v),
          ),
          Row(
            spacing: SxSpace.s12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Use emoji', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                    Text('A few, never in prices', style: SxText.caption.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
              SxToggle(
                value: editor.emoji,
                semanticLabel: 'Use emoji',
                onChanged: (v) => setState(() => editor.emoji = v),
              ),
            ],
          ),
          Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final label in const ['Sir or madam', 'By name', 'Akka / anna'])
                SxPickChip(
                  label: label,
                  selected: editor.address.text == label,
                  onTap: () => setState(() => editor.address.text = label),
                ),
            ],
          ),
          SxField(
            controller: editor.address,
            label: 'Call customers',
            onTile: true,
            maxLength: answerShortLimit,
            onChanged: (_) => setState(() {}),
          ),
          SxField(
            controller: editor.intro,
            label: 'How sellix introduces itself',
            hint: 'Hi, I am your shop’s assistant',
            onTile: true,
            maxLength: answerShortLimit,
          ),
        ],
      ),
    );
  }
}

class _ShopEditor {
  _ShopEditor(Onboarding data)
    : name = TextEditingController(text: data.shopName),
      area = TextEditingController(text: data.answers.area ?? ''),
      city = TextEditingController(text: data.answers.city ?? ''),
      address = TextEditingController(text: data.answers.address ?? '');

  final TextEditingController name, area, city, address;

  void dispose() {
    name.dispose();
    area.dispose();
    city.dispose();
    address.dispose();
  }
}

class _TalkEditor {
  _TalkEditor(OnboardingAnswers a)
    : tone = a.tone == 'formal' ? 'formal' : 'friendly',
      emoji = a.emoji ?? true,
      address = TextEditingController(text: a.addressCustomers ?? ''),
      intro = TextEditingController(text: a.intro ?? '');

  String tone;
  bool emoji;
  final TextEditingController address, intro;

  void dispose() {
    address.dispose();
    intro.dispose();
  }
}
