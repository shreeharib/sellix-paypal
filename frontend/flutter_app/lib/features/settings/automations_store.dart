import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/theme_mode.dart';
import '../../design/design.dart';
import 'settings_providers.dart';

// BACKEND GAP: no automations API. No endpoint to list, switch, configure or create automations, and
// none for their numbers (replies, orders, recovered sales). Everything here lives on this phone and
// nothing runs. Screens must show [automationLocalNote] wherever an automation appears.

const automationLocalNote = 'Saved on this phone only, not active yet';

enum AutomationGroup { core, grow }

enum AutomationMode { auto, draft }

enum ChatLineKind { customer, sellix, button, event }

class ChatLine {
  const ChatLine(this.kind, this.text);

  final ChatLineKind kind;
  final String text;
}

class FlowStep {
  const FlowStep(this.tag, this.text, this.icon);

  final String tag;
  final String text;
  final IconData icon;
}

class Automation {
  const Automation({
    required this.id,
    required this.group,
    required this.icon,
    required this.title,
    required this.desc,
    required this.channels,
    required this.trigger,
    required this.chat,
    this.locked = false,
    this.popular = false,
    this.hiddenUntilOn = false,
    this.custom = false,
    this.on = false,
    this.mode = AutomationMode.auto,
    this.waitMinutes = 10,
    this.words = const [],
    this.action,
  });

  final String id;
  final AutomationGroup group;
  final IconData icon;
  final String title;
  final String desc;
  final List<SxBrand> channels;
  final String trigger;

  /// A pattern with {product} and {price} in it, never a real or invented customer's chat.
  final List<ChatLine> chat;

  /// Built into the agent, so it does run: it follows the agent switch and is stored nowhere.
  final bool locked;
  final bool popular;

  /// A template that joins the list once it is switched on.
  final bool hiddenUntilOn;

  /// Built by the merchant in "Build your own".
  final bool custom;
  final String? action;

  final bool on;
  final AutomationMode mode;

  /// Payment reminder only.
  final int waitMinutes;

  /// Comment to DM only.
  final List<String> words;

  Automation copyWith({bool? on, AutomationMode? mode, int? waitMinutes, List<String>? words}) => Automation(
    id: id,
    group: group,
    icon: icon,
    title: title,
    desc: desc,
    channels: channels,
    trigger: trigger,
    chat: chat,
    locked: locked,
    popular: popular,
    hiddenUntilOn: hiddenUntilOn,
    custom: custom,
    action: action,
    on: on ?? this.on,
    mode: mode ?? this.mode,
    waitMinutes: waitMinutes ?? this.waitMinutes,
    words: words ?? this.words,
  );

  /// The prototype's description, with the wait the merchant chose.
  String get description => id == 'pay'
      ? 'If a payment link is not paid in $waitMinutes minutes, sends one friendly reminder.'
      : desc;

  String get channelNames => channels.map(brandName).join(' and ');

  List<FlowStep> get flow => switch (id) {
    'pay' => [
      const FlowStep('When', 'A payment link is not paid', TablerIcons.clock),
      FlowStep('Wait', '$waitMinutes minutes', TablerIcons.hourglass),
      const FlowStep('sellix sends', 'One friendly reminder with the same link', TablerIcons.send),
      const FlowStep('Then', 'At 15 min the hold ends and stock goes back', TablerIcons.package),
    ],
    'comment' => const [
      FlowStep('When', 'A comment has “price”, “cost” or “how much”', TablerIcons.message_2),
      FlowStep('Only if', 'The post has a product tagged', TablerIcons.tag),
      FlowStep('sellix sends', 'A DM with the price and today’s stock', TablerIcons.send),
      FlowStep('Then', 'Replies under the comment: “Sent you a DM”', TablerIcons.corner_down_right),
    ],
    'story' => const [
      FlowStep('When', 'A customer replies to your story', TablerIcons.circle_dashed),
      FlowStep('sellix knows', 'Which product is in that story', TablerIcons.eye),
      FlowStep('sellix sends', 'Price, what is left today, and asks how many', TablerIcons.send),
    ],
    _ => [
      FlowStep('When', trigger, icon),
      FlowStep(action ?? 'sellix sends', desc, TablerIcons.send),
    ],
  };
}

String brandName(SxBrand brand) => switch (brand) {
  SxBrand.instagram => 'Instagram',
  SxBrand.whatsapp => 'WhatsApp',
  _ => brand.name,
};

const _both = [SxBrand.instagram, SxBrand.whatsapp];
const _ig = [SxBrand.instagram];

/// The prototype's list without its demo numbers. Everything optional starts off.
const automationCatalog = <Automation>[
  Automation(
    id: 'dm',
    group: AutomationGroup.core,
    icon: TablerIcons.message_chatbot,
    title: 'Answer DMs and take orders',
    desc: 'Replies in the customer’s language, quotes today’s stock and takes the order.',
    channels: _both,
    trigger: 'A customer sends a DM',
    locked: true,
    on: true,
    chat: [
      ChatLine(ChatLineKind.customer, 'Is {product} there today?'),
      ChatLine(ChatLineKind.sellix, 'Yes! {price} each. How many do you want?'),
    ],
  ),
  Automation(
    id: 'story',
    group: AutomationGroup.core,
    icon: TablerIcons.circle_dashed,
    title: 'Reply to story replies',
    desc: 'Knows which product is in each story, so “I want this” becomes an order.',
    channels: _ig,
    trigger: 'A customer replies to your story',
    chat: [
      ChatLine(ChatLineKind.customer, 'I want this'),
      ChatLine(ChatLineKind.sellix, '{product}, {price} each. {left} left today. How many do you want?'),
    ],
  ),
  Automation(
    id: 'pay',
    group: AutomationGroup.core,
    icon: TablerIcons.clock_dollar,
    title: 'Payment reminder',
    desc: 'If a payment link is not paid in 10 minutes, sends one friendly reminder.',
    channels: _both,
    trigger: 'Payment not received after 10 min',
    chat: [
      ChatLine(ChatLineKind.sellix, 'Your {product} is still held for you. Pay here to confirm.'),
      ChatLine(ChatLineKind.button, 'Pay {price}'),
    ],
  ),
  Automation(
    id: 'hold',
    group: AutomationGroup.core,
    icon: TablerIcons.hand_stop,
    title: 'Holding message when sellix asks you',
    desc: 'Tells the customer you are checking.',
    channels: _both,
    trigger: 'sellix asks you a question',
    locked: true,
    on: true,
    chat: [
      ChatLine(ChatLineKind.customer, 'Can I get a big order for Saturday?'),
      ChatLine(ChatLineKind.sellix, 'Let me check with the shop and tell you soon.'),
    ],
  ),
  Automation(
    id: 'hours',
    group: AutomationGroup.core,
    icon: TablerIcons.moon,
    title: 'Out of hours reply',
    desc: 'Outside your opening hours, takes pre-orders for the next working day.',
    channels: _both,
    trigger: 'A DM arrives outside your hours',
    chat: [
      ChatLine(ChatLineKind.customer, '{product} available now?'),
      ChatLine(ChatLineKind.sellix, 'We are closed now. Shall I keep one for you for when we open?'),
    ],
  ),
  Automation(
    id: 'comment',
    group: AutomationGroup.grow,
    icon: TablerIcons.message_2,
    title: 'Comment to DM',
    desc: 'When someone comments “price” on a post, sellix sends the price in a DM.',
    channels: _ig,
    trigger: 'A comment has “price”, “cost” or “how much”',
    popular: true,
    words: ['price', 'cost', 'how much', 'rate', 'evlo', 'kitna'],
    chat: [
      ChatLine(ChatLineKind.event, 'Comment: price?'),
      ChatLine(ChatLineKind.sellix, 'Hi! {product} is {price}. Want one?'),
    ],
  ),
  Automation(
    id: 'restock',
    group: AutomationGroup.grow,
    icon: TablerIcons.bell_ringing,
    title: 'Back in stock alert',
    desc: 'Customers who asked after sell-out get a DM when you restock.',
    channels: _both,
    trigger: 'You restock a sold-out item',
    mode: AutomationMode.draft,
    chat: [ChatLine(ChatLineKind.sellix, '{product} is back. {left} in stock now. Shall I keep one for you?')],
  ),
  Automation(
    id: 'ready',
    group: AutomationGroup.grow,
    icon: TablerIcons.package,
    title: 'Order ready message',
    desc: 'Tells the customer when you mark the order ready or out for delivery.',
    channels: _both,
    trigger: 'You mark an order ready',
    chat: [ChatLine(ChatLineKind.sellix, 'Your order is ready, {name}.')],
  ),
  Automation(
    id: 'winback',
    group: AutomationGroup.grow,
    icon: TablerIcons.user_heart,
    title: 'Win back regulars',
    desc: 'Customers who have not ordered in 30 days get what is new today.',
    channels: _both,
    trigger: 'Customer back after 30 days',
    hiddenUntilOn: true,
    chat: [ChatLine(ChatLineKind.sellix, 'Hi {name}! {product} today, {price}. Shall I keep one for you?')],
  ),
];

/// A trigger in "Build your own".
class AutomationTrigger {
  const AutomationTrigger(this.icon, this.title, this.channel);

  final IconData icon;
  final String title;
  final String channel;
}

const automationTriggers = [
  AutomationTrigger(TablerIcons.message_2, 'Comment on a post', 'Instagram'),
  AutomationTrigger(TablerIcons.circle_dashed, 'Story reply', 'Instagram'),
  AutomationTrigger(TablerIcons.abc, 'Keyword in a DM', 'Both'),
  AutomationTrigger(TablerIcons.receipt, 'Order is paid', 'Both'),
  AutomationTrigger(TablerIcons.package, 'Order is ready', 'Both'),
  AutomationTrigger(TablerIcons.package_off, 'Item sells out', 'Both'),
  AutomationTrigger(TablerIcons.user_heart, 'Customer back after 30 days', 'Both'),
  AutomationTrigger(TablerIcons.moon, 'DM outside hours', 'Both'),
];

/// Kept per shop, so a second shop signing in on this phone does not inherit the first one's.
class AutomationsController extends AsyncNotifier<List<Automation>> {
  late String _key;

  @override
  Future<List<Automation>> build() async {
    final me = await ref.watch(meProvider.future);
    _key = 'automations.v1.${me.merchant.id}';
    return _decode(ref.read(sharedPreferencesProvider).getString(_key));
  }

  Future<void> setOn(String id, bool on) async {
    final list = await future;
    await _store([
      for (final a in list)
        if (a.id == id) a.copyWith(on: on) else a,
    ]);
  }

  Future<void> saveSettings(Automation next) async {
    final list = await future;
    await _store([
      for (final a in list)
        if (a.id == next.id) next else a,
    ]);
  }

  /// Saves a "Build your own" automation and returns it.
  Future<Automation> addCustom({
    required String trigger,
    required String channel,
    required String message,
    required String action,
    required String preview,
  }) async {
    final list = await future;
    final added = _custom({
      'id': 'own${DateTime.now().microsecondsSinceEpoch}',
      'trigger': trigger,
      'channel': channel,
      'message': message,
      'action': action,
      'preview': preview,
      'on': true,
    });
    await _store([...list, added]);
    return added;
  }

  Future<void> _store(List<Automation> list) async {
    state = AsyncData(list);
    await ref.read(sharedPreferencesProvider).setString(_key, _encode(list));
  }

  static List<Automation> _decode(String? saved) {
    Map<String, dynamic> data;
    try {
      data = saved == null ? const {} : jsonDecode(saved) as Map<String, dynamic>;
    } on FormatException {
      data = const {};
    }
    final states = (data['state'] as Map<String, dynamic>?) ?? const {};
    return [
      for (final base in automationCatalog) _withState(base, states[base.id] as Map<String, dynamic>?),
      for (final item in (data['custom'] as List<dynamic>?) ?? const [])
        _custom((item as Map).cast<String, dynamic>()),
    ];
  }

  static Automation _withState(Automation base, Map<String, dynamic>? saved) {
    if (saved == null || base.locked) return base;
    return base.copyWith(
      on: saved['on'] as bool?,
      mode: saved['mode'] == 'draft'
          ? AutomationMode.draft
          : saved['mode'] == 'auto'
          ? AutomationMode.auto
          : null,
      waitMinutes: saved['wait'] as int?,
      words: (saved['words'] as List<dynamic>?)?.cast<String>(),
    );
  }

  static Automation _custom(Map<String, dynamic> json) {
    final trigger = json['trigger'] as String;
    final channel = json['channel'] as String? ?? 'Both';
    final message = json['message'] as String;
    return Automation(
      id: json['id'] as String,
      group: AutomationGroup.grow,
      icon: TablerIcons.bolt,
      title: trigger,
      desc: message,
      channels: channel == 'Instagram' ? _ig : _both,
      trigger: trigger,
      custom: true,
      action: json['action'] as String?,
      on: json['on'] as bool? ?? true,
      mode: json['mode'] == 'draft' ? AutomationMode.draft : AutomationMode.auto,
      chat: [ChatLine(ChatLineKind.sellix, json['preview'] as String? ?? message)],
    );
  }

  static String _encode(List<Automation> list) => jsonEncode({
    'state': {
      for (final a in list)
        if (!a.custom && !a.locked)
          a.id: {'on': a.on, 'mode': a.mode.name, 'wait': a.waitMinutes, 'words': a.words},
    },
    'custom': [
      for (final a in list)
        if (a.custom)
          {
            'id': a.id,
            'trigger': a.trigger,
            'channel': a.channels.length == 1 ? 'Instagram' : 'Both',
            'message': a.desc,
            'action': a.action,
            'preview': a.chat.first.text,
            'on': a.on,
            'mode': a.mode.name,
          },
    ],
  });
}

final automationsProvider = AsyncNotifierProvider.autoDispose<AutomationsController, List<Automation>>(
  AutomationsController.new,
);

/// Switched-on automations the merchant can see, for the counts. Locked ones are not a choice.
int chosenAutomations(List<Automation> list) => list.where((a) => a.on && !a.locked).length;

/// What the list shows: templates waiting to be picked stay out of it.
List<Automation> visibleAutomations(List<Automation> list) =>
    list.where((a) => !a.hiddenUntilOn || a.on).toList();

// BACKEND GAP: no notification preferences on the backend, and the app has no push yet. The morning
// reminder and quiet hours are kept per shop on this phone and trigger nothing.
class LocalAlerts {
  const LocalAlerts(this._read, this._write, this._merchantId);

  final String? Function(String key) _read;
  final Future<bool> Function(String key, String value) _write;
  final String _merchantId;

  String get morning => _read('alerts.$_merchantId.morning') ?? '8:00 AM';
  String get quietFrom => _read('alerts.$_merchantId.quiet_from') ?? '10:00 PM';
  String get quietTo => _read('alerts.$_merchantId.quiet_to') ?? '7:00 AM';

  /// "10 PM to 7 AM".
  String get quietWords => '${quietFrom.replaceAll(':00', '')} to ${quietTo.replaceAll(':00', '')}';

  Future<void> setMorning(String time) => _write('alerts.$_merchantId.morning', time);

  Future<void> setQuiet(String from, String to) async {
    await _write('alerts.$_merchantId.quiet_from', from);
    await _write('alerts.$_merchantId.quiet_to', to);
  }
}
