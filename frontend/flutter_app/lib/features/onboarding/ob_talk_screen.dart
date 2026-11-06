import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_answers_text.dart';
import 'ob_common.dart';

const _addressOptions = ['Sir or madam', 'By name', 'Akka / anna'];
const _languageOptions = ['English', 'Tanglish', 'Tamil', 'Hinglish', 'Hindi'];

/// What the chosen voice sounds like. A fixed example built on this phone, labelled as one.
String talkPreview({required String tone, required bool emoji, required String address}) {
  final friendly = tone == 'friendly';
  final name = switch (address) {
    'By name' => '[name]',
    'Akka / anna' => 'akka',
    _ => 'madam',
  };
  if (!friendly) {
    return 'Good afternoon ${address == 'By name' ? '[name]' : 'madam'}. Yes, this is available today. Which one would you like?';
  }
  return 'Hi $name${emoji ? ' 👋' : ''}! Yes, this is available today${emoji ? ' ✨' : ''}. Which one do you want?';
}

class ObTalkScreen extends ConsumerStatefulWidget {
  const ObTalkScreen({super.key});

  @override
  ConsumerState<ObTalkScreen> createState() => _ObTalkScreenState();
}

class _ObTalkScreenState extends ConsumerState<ObTalkScreen> with ObSaving {
  final _intro = TextEditingController();
  bool _ready = false;
  String _tone = 'friendly';
  bool _emoji = true;
  String _address = _addressOptions.first;
  Set<String> _languages = {'English', 'Tanglish', 'Tamil'};

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _load() {
    final draft = ref.watch(onboardingDraftProvider).value;
    if (_ready || draft == null) return;
    _ready = true;
    final a = draft.answers;
    _tone = a.tone ?? _tone;
    _emoji = a.emoji ?? _emoji;
    _address = _addressOptions.contains(a.addressCustomers) ? a.addressCustomers! : _address;
    final saved = obParseLanguages(a.faqs);
    if (saved != null) _languages = saved.toSet();
    _intro.text = a.intro ?? 'Hi, I am ${draft.shopName}’s assistant';
  }

  void _continue() {
    saveThen(
      (a) => a.copyWith(
        tone: _tone,
        emoji: _emoji,
        addressCustomers: _address,
        intro: obText(_intro.text),
        // BACKEND GAP: no field for customer languages; see obFaqsWith.
        faqs: obFaqsWith(a.faqs, languages: [
          for (final l in _languageOptions)
            if (_languages.contains(l)) l,
        ]),
      ),
      () => context.push(Routes.obRules),
    );
  }

  @override
  Widget build(BuildContext context) {
    _load();
    return ObStepFrame(
      step: 1,
      fraction: 0.25,
      fallback: Routes.obShop,
      title: 'How should sellix talk?',
      why: 'sellix replies as your shop’s assistant. Customers see this voice.',
      saving: saving,
      onContinue: _ready ? _continue : null,
      onSkip: () => context.push(Routes.obRules),
      children: [
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 2,
          child: _PreviewCard(text: talkPreview(tone: _tone, emoji: _emoji, address: _address)),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ObLabel('Tone'),
              SxSegmented<String>(
                segments: const [SxSegment('friendly', 'Friendly'), SxSegment('formal', 'Formal')],
                value: _tone,
                onChanged: (v) => setState(() => _tone = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s12),
        SxFadeUp(
          index: 4,
          child: SxGroup(
            children: [
              SxSwitchRow(
                title: 'Use emoji',
                subtitle: 'A few, never in prices',
                value: _emoji,
                onChanged: (v) => setState(() => _emoji = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ObLabel('Call customers'),
              Wrap(
                spacing: SxSpace.s8,
                runSpacing: SxSpace.s8,
                children: [
                  for (final option in _addressOptions)
                    SxPickChip(
                      label: option,
                      selected: _address == option,
                      onTap: () => setState(() => _address = option),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ObLabel('Your customers write in'),
              Wrap(
                spacing: SxSpace.s8,
                runSpacing: SxSpace.s8,
                children: [
                  for (final language in _languageOptions)
                    SxPickChip(
                      label: language,
                      selected: _languages.contains(language),
                      onTap: () => setState(() {
                        _languages = {..._languages};
                        if (!_languages.remove(language)) _languages.add(language);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: SxSpace.s8),
              const SxAiNote('I always reply in the language of the customer’s last message.'),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        SxFadeUp(
          index: 7,
          child: SxField(
            controller: _intro,
            label: 'How sellix introduces itself',
            hint: 'Hi, I am your shop’s assistant',
            maxLength: 200,
          ),
        ),
      ],
    );
  }
}

/// A made-up exchange that shows the voice, so it says so. Never a real chat.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(TablerIcons.eye, size: 16, color: p.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Preview. An example, not a real chat.', style: SxText.micro.copyWith(color: p.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: SxSpace.s8),
          const SxBubble(text: 'Is this available today?', sender: SxBubbleSender.customer),
          const SizedBox(height: SxSpace.s8),
          _TypedBubble(text: text),
        ],
      ),
    );
  }
}

/// The reply re-types itself on every change.
class _TypedBubble extends StatefulWidget {
  const _TypedBubble({required this.text});

  final String text;

  @override
  State<_TypedBubble> createState() => _TypedBubbleState();
}

class _TypedBubbleState extends State<_TypedBubble> {
  Timer? _timer;
  int _shown = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _type();
  }

  @override
  void didUpdateWidget(_TypedBubble old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _type();
  }

  void _type() {
    _timer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown = widget.text.characters.length;
      return;
    }
    _shown = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 14), (timer) {
      setState(() => _shown += 2);
      if (_shown >= widget.text.characters.length) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SxBubble(text: widget.text.characters.take(_shown).toString(), sender: SxBubbleSender.sellix);
}
