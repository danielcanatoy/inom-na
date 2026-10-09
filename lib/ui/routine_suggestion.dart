import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../models/routine.dart';
import '../services/fallback_parser.dart';
import '../services/routine_schedule.dart';
import 'app_theme.dart';
import 'components.dart';
import 'format.dart';

/// "Suggested Schedule" for a verified general daily frequency. Times are
/// only applied when the user taps "Use These Times".
class RoutineSuggestionPanel extends StatefulWidget {
  const RoutineSuggestionPanel({
    super.key,
    required this.medicine,
    required this.routine,
    required this.onApply,
    this.onSetUpRoutine,
  });
  final Medicine medicine;
  final DailyRoutine? routine;
  final void Function(List<String> times, RoutineLink link) onApply;
  final VoidCallback? onSetUpRoutine;

  @override
  State<RoutineSuggestionPanel> createState() => _RoutineSuggestionPanelState();
}

class _RoutineSuggestionPanelState extends State<RoutineSuggestionPanel> {
  late final _hints = FallbackParser.timingHints(widget.medicine.instructions);
  late RoutineMode _mode = widget.medicine.routineLink?.mode ??
      RoutineScheduler.suggestedMode(widget.medicine,
          bedtime: _hints.bedtime,
          beforeMeals: _hints.beforeMeals,
          afterMeals: _hints.afterMeals);
  late List<RoutineEvent> _meals = widget.medicine.routineLink?.meals ??
      RoutineScheduler.defaultMeals(widget.medicine.frequencyPerDay ?? 0);
  late final _offset = TextEditingController(
      text: widget.medicine.routineLink?.offsetMinutes?.toString() ?? '');

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  int get _perDay => widget.medicine.frequencyPerDay ?? 0;

  List<RoutineMode> get _modes => [
        RoutineMode.spread,
        if (_perDay >= 1 && _perDay <= 3) ...[
          RoutineMode.beforeMeals,
          RoutineMode.afterMeals,
        ],
        if (_perDay == 1) RoutineMode.bedtime,
      ];

  RoutineLink get _link => RoutineLink(
        mode: _mode,
        meals:
            _mode == RoutineMode.beforeMeals || _mode == RoutineMode.afterMeals
                ? _meals
                : const [],
        offsetMinutes:
            _mode == RoutineMode.beforeMeals || _mode == RoutineMode.afterMeals
                ? int.tryParse(_offset.text.trim())
                : null,
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final routine = widget.routine;
    final written = [
      if (_hints.bedtime) 'at bedtime',
      if (_hints.beforeMeals) 'before meals',
      if (_hints.afterMeals) 'after meals',
    ];
    final children = <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Suggested Schedule', style: textTheme.titleSmall),
          const StatusBadge(
              label: 'Based on My Daily Routine',
              tone: Tone.info,
              icon: Icons.wb_twilight),
        ],
      ),
      if (written.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Your directions mention: ${written.join(', ')}.',
              style: textTheme.bodyMedium),
        ),
    ];

    if (routine == null) {
      children.addAll([
        const SizedBox(height: 6),
        Text('Set up My Daily Routine to get reminder times that fit your day.',
            style: textTheme.bodyMedium),
        if (widget.onSetUpRoutine != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: widget.onSetUpRoutine,
                icon: const Icon(Icons.wb_twilight),
                label: const Text('Set Up My Daily Routine')),
          ),
      ]);
    } else {
      if (!_modes.contains(_mode)) _mode = RoutineMode.spread;
      final usesMeals =
          _mode == RoutineMode.beforeMeals || _mode == RoutineMode.afterMeals;
      final suggestion = RoutineScheduler.suggest(
          perDay: _perDay, link: _link, routine: routine);
      children.addAll([
        const SizedBox(height: 10),
        DropdownButtonFormField<RoutineMode>(
          key: ValueKey(_mode),
          initialValue: _mode,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'Fit to my routine'),
          items: [
            for (final mode in _modes)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (mode) {
            if (mode != null) setState(() => _mode = mode);
          },
        ),
        if (usesMeals) ...[
          const SizedBox(height: 10),
          Text('Which meals?', style: textTheme.bodyMedium),
          Wrap(spacing: 8, children: [
            for (final meal in mealEvents)
              FilterChip(
                label: Text('${meal.label} '
                    '(${Fmt.clock(routine[meal])})'),
                selected: _meals.contains(meal),
                onSelected: (selected) => setState(() {
                  _meals = [
                    for (final m in mealEvents)
                      if (m == meal ? selected : _meals.contains(m)) m,
                  ];
                }),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _offset,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _mode == RoutineMode.beforeMeals
                  ? 'Minutes before the meal'
                  : 'Minutes after the meal',
              helperText: 'Use the number from your prescription or '
                  'pharmacist. IMedsU does not assume one.',
              helperMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 10),
        if (!suggestion.usable)
          InfoBanner(tone: Tone.warning, lines: suggestion.problems)
        else ...[
          Text('Suggested times: ${suggestion.times.map(Fmt.clock).join(', ')}',
              style:
                  textTheme.titleSmall?.copyWith(color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          Text(
              'These are reminder suggestions, not part of your prescription. '
              'Review them before saving.',
              style: textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: suggestion.usable
                ? () => widget.onApply(suggestion.times, _link)
                : null,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Use These Times'),
          ),
        ),
      ]);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Small label explaining where a medicine's reminder times come from.
class ScheduleBasisBadge extends StatelessWidget {
  const ScheduleBasisBadge(this.medicine, {super.key});
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (medicine.scheduleKind) {
      ScheduleKind.explicit => (
          'Prescribed Time',
          Icons.edit_calendar_outlined
        ),
      ScheduleKind.interval => ('Fixed Interval', Icons.timelapse),
      ScheduleKind.prn => (
          'As needed (no reminders)',
          Icons.back_hand_outlined
        ),
      ScheduleKind.unknown => ('Needs review', Icons.help_outline),
      ScheduleKind.daily => medicine.routineLink != null
          ? ('Based on My Daily Routine', Icons.wb_twilight)
          : ('Custom times', Icons.tune),
    };
    return StatusBadge(
        label: label,
        tone: medicine.scheduleKind == ScheduleKind.unknown
            ? Tone.warning
            : Tone.info,
        icon: icon);
  }
}
