import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'hours_codec.dart';
import 'settings_providers.dart';

class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  WeekHours? _week;
  bool _understood = true;
  bool _edited = false;
  bool _saving = false;
  bool _done = false;

  void _edit(WeekHours next) => setState(() {
    _week = next;
    _edited = true;
  });

  void _toggleDay(int day, bool on) =>
      _edit(_week!.withDay(day, on ? const DayHours(defaultOpens, defaultCloses) : null));

  Future<void> _pickTime(int day, {required bool opens}) async {
    final hours = _week!.days[day]!;
    final picked = await showTimeSheet(
      context,
      title: '${opens ? 'Opens' : 'Closes'} on ${weekDayNames[day]}',
      current: opens ? hours.opens : hours.closes,
    );
    if (picked == null || !mounted) return;
    _edit(_week!.withDay(day, opens ? DayHours(picked, hours.closes) : DayHours(hours.opens, picked)));
  }

  Future<void> _addDate() async {
    final added = await showSxSheet<ClosedDate>(
      context,
      title: 'Add a closed date',
      subtitle: 'sellix tells customers you are closed that day.',
      builder: (_) => const _ClosedDateSheet(),
    );
    if (added == null || !mounted) return;
    final week = _week!;
    if (week.closedDates.any((d) => d.sameDay(added.date))) return;
    final next = week.withClosedDates([...week.closedDates, added]);
    if ((encodeClosed(next)?.length ?? 0) > answerShortLimit) {
      showSxSnack(context, 'That is too many closed dates. Remove one first.', icon: TablerIcons.calendar);
      return;
    }
    _edit(next);
  }

  Future<void> _removeDate(ClosedDate date) async {
    final yes = await showSxConfirm(
      context,
      title: 'Remove this date?',
      body: date.label,
      confirmLabel: 'Remove',
      cancelLabel: 'Keep',
    );
    if (!yes || !mounted) return;
    _edit(_week!.withClosedDates(_week!.closedDates.where((d) => d != date).toList()));
  }

  Future<void> _save() async {
    // Untouched, there is nothing to write: this matters when the saved text was not understood.
    if (!_edited) {
      await finishSave(context, null, fallback: Routes.profile);
      return;
    }
    final week = _week!;
    setState(() => _saving = true);
    try {
      await saveAnswers(
        containerOf(context),
        (a) => a.copyWith(hours: encodeHours(week), weeklyOff: encodeClosed(week)),
      );
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
    await finishSave(context, 'Opening hours saved.', fallback: Routes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final data = onboarding.value;
    if (data != null && _week == null) {
      final parsed = parseHours(data.answers.hours, data.answers.weeklyOff);
      _week = parsed.week;
      _understood = parsed.understood;
    }
    return SxScaffold(
      floating: _week == null
          ? null
          : SxBottomCta(
              label: _done ? 'Saved' : 'Save',
              icon: TablerIcons.check,
              loading: _saving,
              done: _done,
              onTap: _done ? null : _save,
            ),
      body: Column(
        children: [
          const SxDetailHeader(
            title: 'Opening hours',
            meta: 'sellix uses these to say open or closed',
            fallback: Routes.profile,
          ),
          Expanded(
            child: SxAsyncView<Onboarding>(
              value: onboarding,
              onRetry: () => ref.invalidate(onboardingProvider),
              loading: const SxSkeletonList(count: 1, itemHeight: 380),
              builder: (context, data) => _list(context, data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, Onboarding data) {
    final p = context.sx;
    final week = _week!;
    return SxScrollList(
      children: [
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SxFadeUp(
                child: Text(
                  'Outside these hours sellix tells customers when you are back and takes orders for your next open day. No physical shop? Set the hours you can pack and reply.',
                  style: SxText.bodyS.copyWith(color: p.textSecondary),
                ),
              ),
              const SizedBox(height: SxSpace.s12),
              if (!_understood) ...[
                SxBanner(
                  tone: SxBannerTone.neutral,
                  message:
                      'Your hours are saved as: “${[?data.answers.hours, ?data.answers.weeklyOff].join(', closed ')}”. Saving here replaces that text.',
                ),
                const SizedBox(height: SxSpace.s12),
              ],
              SxFadeUp(
                index: 1,
                child: SxCard(
                  padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: 6),
                  child: Column(
                    children: [
                      for (var day = 0; day < 7; day++) ...[
                        if (day > 0) Divider(height: 1, thickness: 1, color: p.line),
                        _DayRow(
                          day: day,
                          hours: week.days[day],
                          onToggle: (on) => _toggleDay(day, on),
                          onPick: (opens) => _pickTime(day, opens: opens),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SxSpace.s20),
              Text('Closed dates', style: SxText.label.copyWith(color: p.textPrimary)),
              const SizedBox(height: SxSpace.s8),
              SxFadeUp(
                index: 2,
                child: Wrap(
                  spacing: SxSpace.s8,
                  runSpacing: SxSpace.s8,
                  children: [
                    for (final date in week.closedDates)
                      SxPickChip(
                        label: date.label,
                        icon: TablerIcons.calendar,
                        selected: false,
                        onTap: () => _removeDate(date),
                      ),
                    SxPickChip(label: 'Add a date', icon: TablerIcons.plus, selected: false, onTap: _addDate),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.hours, required this.onToggle, required this.onPick});

  final int day;
  final DayHours? hours;
  final ValueChanged<bool> onToggle;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final h = hours;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        spacing: SxSpace.s8,
        children: [
          SizedBox(
            width: 40,
            child: Text(weekDayNames[day], style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
          ),
          Expanded(
            child: h == null
                ? Text('Closed', style: SxText.bodyS.copyWith(color: p.textSecondary))
                // Scales down rather than overflowing on a narrow phone or with large text.
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: SxSpace.s4,
                      children: [
                        SxTimeChip(label: h.opens, onTap: () => onPick(true)),
                        Text('to', style: SxText.caption.copyWith(color: p.textSecondary)),
                        SxTimeChip(label: h.closes, onTap: () => onPick(false)),
                      ],
                    ),
                  ),
          ),
          SxToggle(value: h != null, onChanged: onToggle, semanticLabel: 'Open on ${weekDayNames[day]}'),
        ],
      ),
    );
  }
}

class _ClosedDateSheet extends StatefulWidget {
  const _ClosedDateSheet();

  @override
  State<_ClosedDateSheet> createState() => _ClosedDateSheetState();
}

class _ClosedDateSheetState extends State<_ClosedDateSheet> {
  final _reason = TextEditingController();
  DateTime? _date;
  bool _missing = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final today = DateUtils.dateOnly(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Date', style: SxText.label.copyWith(color: p.textPrimary)),
        CalendarDatePicker(
          initialDate: _date,
          firstDate: today,
          lastDate: DateTime(today.year + 2, today.month, today.day),
          onDateChanged: (date) => setState(() {
            _date = date;
            _missing = false;
          }),
        ),
        if (_missing) Text('Pick a date first.', style: SxText.caption.copyWith(color: p.errorText)),
        const SizedBox(height: SxSpace.s12),
        // A semicolon is how the saved text separates closed days and dates.
        SxField(controller: _reason, label: 'Reason (optional)', hint: 'Holiday', maxLength: 30),
        const SizedBox(height: SxSpace.s16),
        SxButton(
          label: 'Add date',
          icon: TablerIcons.check,
          fullWidth: true,
          onTap: () {
            final date = _date;
            if (date == null) {
              setState(() => _missing = true);
              return;
            }
            final reason = blankToNull(_reason.text.replaceAll(';', ' '));
            Navigator.of(context).pop(ClosedDate(date, reason: reason));
          },
        ),
      ],
    );
  }
}
