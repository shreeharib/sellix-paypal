import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_answers_text.dart';
import 'ob_common.dart';

/// Every hour from 5 AM to 11 PM, plus the current value if it is not on the hour.
List<String> _timeList(String current) {
  final list = [
    for (var h = 5; h <= 23; h++) '${h % 12 == 0 ? 12 : h % 12}:00 ${h >= 12 ? 'PM' : 'AM'}',
  ];
  return list.contains(current) ? list : [current, ...list];
}

class ObHoursScreen extends ConsumerStatefulWidget {
  const ObHoursScreen({super.key});

  @override
  ConsumerState<ObHoursScreen> createState() => _ObHoursScreenState();
}

class _ObHoursScreenState extends ConsumerState<ObHoursScreen> with ObSaving {
  bool _ready = false;
  Map<String, ObDayHours> _week = obDefaultWeek();
  List<ObClosedDate> _closedDates = [];

  void _load() {
    final draft = ref.watch(onboardingDraftProvider).value;
    if (_ready || draft == null) return;
    _ready = true;
    final a = draft.answers;
    _week = obParseHours(a.hours) ?? _week;
    if (a.hours == null && a.weeklyOff != null) {
      _week = {
        for (final d in obDays) d: _week[d]!.copyWith(open: !obParseClosedDays(a.weeklyOff).contains(d)),
      };
    }
    _closedDates = obParseClosedDates(draft.answers.weeklyOff);
  }

  void _continue() {
    final hours = obHoursText(_week);
    final closed = obClosedText(_week, _closedDates);
    // The API keeps 200 characters for each.
    if ((closed?.length ?? 0) > 200) {
      showSxSnack(context, 'That is too many closed dates to save. Remove one.');
      return;
    }
    saveThen((a) => a.copyWith(hours: hours, weeklyOff: closed), () => context.push(Routes.obPay));
  }

  Future<void> _pickTime(String day, {required bool opens}) async {
    final current = opens ? _week[day]!.opens : _week[day]!.closes;
    final picked = await showSxSheet<String>(
      context,
      title: '${opens ? 'Opens' : 'Closes'} on $day',
      builder: (sheet) => Wrap(
        spacing: SxSpace.s8,
        runSpacing: SxSpace.s8,
        children: [
          for (final time in _timeList(current))
            SxPickChip(label: time, selected: time == current, onTap: () => Navigator.of(sheet).pop(time)),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _week = {..._week, day: opens ? _week[day]!.copyWith(opens: picked) : _week[day]!.copyWith(closes: picked)};
    });
  }

  Future<void> _addDate() async {
    final date = await showSxSheet<ObClosedDate>(context, title: 'Add a closed date', subtitle: 'sellix tells customers you are closed that day.', builder: (sheet) => const _AddDateSheet());
    if (date == null || !mounted) return;
    if (_closedDates.any(date.sameDay)) return;
    setState(() => _closedDates = [..._closedDates, date]);
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final p = context.sx;
    return ObStepFrame(
      step: 1,
      fraction: 0.85,
      fallback: Routes.obRules,
      title: 'When are you open?',
      why: 'Outside these hours sellix tells customers when you are back and takes orders for your next open day. No physical shop? Set the hours you can pack and reply.',
      saving: saving,
      onContinue: _ready ? _continue : null,
      onSkip: () => context.push(Routes.obPay),
      children: [
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 2,
          child: SxCard(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: 6),
            child: Column(
              children: [
                for (final (i, day) in obDays.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
                  _DayRow(
                    day: day,
                    hours: _week[day]!,
                    onToggle: (open) => setState(() => _week = {..._week, day: _week[day]!.copyWith(open: open)}),
                    onOpens: () => _pickTime(day, opens: true),
                    onCloses: () => _pickTime(day, opens: false),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ObLabel('Closed dates'),
              Wrap(
                spacing: SxSpace.s8,
                runSpacing: SxSpace.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final date in _closedDates)
                    SxPressable(
                      small: true,
                      semanticLabel: 'Remove ${date.label}',
                      onTap: () => setState(() {
                        _closedDates = _closedDates.where((d) => !d.sameDay(date)).toList();
                      }),
                      child: SxChip(label: date.label, icon: TablerIcons.x),
                    ),
                  SxPickChip(label: 'Add a date', selected: false, icon: TablerIcons.plus, onTap: _addDate),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.hours,
    required this.onToggle,
    required this.onOpens,
    required this.onCloses,
  });

  final String day;
  final ObDayHours hours;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpens;
  final VoidCallback onCloses;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(day, style: SxText.bodyStrong.copyWith(color: p.textPrimary))),
          const SizedBox(width: SxSpace.s4),
          Expanded(
            child: hours.open
                ? Wrap(
                    spacing: SxSpace.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SxTimeChip(label: hours.opens, onTap: onOpens),
                      Text('to', style: SxText.bodyS.copyWith(color: p.textSecondary)),
                      SxTimeChip(label: hours.closes, onTap: onCloses),
                    ],
                  )
                : Text('Closed', style: SxText.bodyS.copyWith(color: p.textTertiary)),
          ),
          const SizedBox(width: SxSpace.s4),
          SxToggle(value: hours.open, onChanged: onToggle, semanticLabel: 'Open on $day'),
        ],
      ),
    );
  }
}

class _AddDateSheet extends StatefulWidget {
  const _AddDateSheet();

  @override
  State<_AddDateSheet> createState() => _AddDateSheetState();
}

class _AddDateSheetState extends State<_AddDateSheet> {
  final _date = TextEditingController();
  final _why = TextEditingController();
  DateTime? _picked;
  String? _error;

  @override
  void dispose() {
    _date.dispose();
    _why.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2, now.month, now.day),
      initialDate: _picked ?? now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _error = null;
      _date.text = DateFormat('EEE d MMM y', 'en_US').format(picked);
    });
  }

  void _add() {
    final picked = _picked;
    if (picked == null) {
      setState(() => _error = 'Pick a date first.');
      return;
    }
    // Commas and semicolons separate the saved closed dates.
    final why = _why.text.replaceAll(RegExp('[,;]'), ' ').trim();
    Navigator.of(context).pop(ObClosedDate(picked, why.isEmpty ? null : why));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SxField(
          controller: _date,
          label: 'Date',
          hint: 'Pick a date',
          readOnly: true,
          onTap: _choose,
          errorText: _error,
        ),
        const SizedBox(height: SxSpace.s12),
        SxField(controller: _why, label: 'Reason (optional)', hint: 'Holiday', maxLength: 30),
        const SizedBox(height: SxSpace.s16),
        SxButton(label: 'Add date', icon: TablerIcons.check, fullWidth: true, onTap: _add),
      ],
    );
  }
}
