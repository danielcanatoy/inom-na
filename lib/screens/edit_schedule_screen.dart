import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../models/routine.dart';
import '../services/schedule_edit.dart';
import '../services/store.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../services/strength_check.dart';
import '../ui/routine_suggestion.dart';

/// Edits a SAVED medicine's future schedule on a draft copy. Returns the
/// revised medicine only after the user confirms; cancel returns null and the
/// saved medicine, its history and its reminders are untouched.
class EditScheduleScreen extends StatefulWidget {
  const EditScheduleScreen({
    super.key,
    required this.medicine,
    this.clock,
    this.correctPrescription = false,
  });

  /// Opens as "Edit Medication" with prescription corrections shown.
  final bool correctPrescription;
  final Medicine medicine;
  final DateTime Function()? clock;

  @override
  State<EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<EditScheduleScreen> {
  late final Medicine _saved = widget.medicine.copy();
  late final Medicine _draft = ScheduleEdit.draftOf(_saved);
  late final bool _started = ScheduleEdit.hasStarted(_saved, _now());
  final DailyRoutine? _routine = Store.routine;
  late bool _applyToday =
      ScheduleEdit.canApplyToday(_saved, _draft.times, _now());
  bool _dirty = false;
  late bool _correcting = widget.correctPrescription;
  bool _corrected = false;
  bool _correctionVerified = false;
  bool _endEdited = false;

  /// True once the user picks the interval's first/next dose themselves.
  bool _anchorChosen = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  bool get _isInterval => _draft.scheduleKind == ScheduleKind.interval;
  bool get _isClock =>
      _draft.scheduleKind == ScheduleKind.daily ||
      _draft.scheduleKind == ScheduleKind.explicit;

  @override
  void initState() {
    super.initState();
    if (_isInterval && _started) {
      // Default: keep the current spacing by starting at the next dose.
      _draft.start = ScheduleEdit.nextDose(_saved, _now()) ?? _saved.start;
    }
  }

  void _edit(VoidCallback change, {bool correction = false}) {
    setState(() {
      change();
      _dirty = true;
      if (correction) {
        _corrected = true;
        _correctionVerified = false;
      }
    });
  }

  /// When the new rule takes effect and the draft's matching start.
  DateTime get _effectiveFrom {
    if (!_started) return _draft.start;
    // Interval changes apply from now: earlier doses are history and the
    // new first dose replaces the upcoming ones.
    if (_isInterval) return _now();
    final today =
        _applyToday && ScheduleEdit.canApplyToday(_saved, _draft.times, _now());
    return ScheduleEdit.clockEffectiveFrom(_saved, _now(), today: today);
  }

  Medicine get _next {
    final next = _draft.copy();
    if (!_isInterval && _started) next.start = _effectiveFrom;
    // Keep the same number of remaining doses unless the end was corrected.
    // Moving times keeps the same number of remaining doses. A corrected
    // frequency, interval or schedule type keeps the course's end instead,
    // so the corrected rate decides the doses.
    if (!_endEdited && !_rateChanged) {
      next.end = ScheduleEdit.preservedEnd(_saved, next, _effectiveFrom);
    }
    return next;
  }

  List<String> get _errors {
    final errors = ScheduleEdit.errors(_saved, _next, _effectiveFrom, _now());
    if (_corrected && !_correctionVerified) {
      errors.add('Confirm that you checked the corrected details against '
          'your prescription.');
    }
    return errors;
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = _now();
    final day = await showDatePicker(
        context: context,
        initialDate: initial.isBefore(now) ? now : initial,
        firstDate: ScheduleEdit.dayStart(now),
        lastDate: now.add(const Duration(days: 3650)));
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _editTime(int? index, {bool correction = false}) async {
    final base = index == null ? '08:00' : _draft.times[index];
    final minutes = DailyRoutine.minutesOf(base) ?? 8 * 60;
    final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    if (picked == null || !mounted) return;
    final value = DailyRoutine.format(picked.hour * 60 + picked.minute);
    if (_draft.times
        .asMap()
        .entries
        .any((entry) => entry.key != index && entry.value == value)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This time has already been added.')));
      return;
    }
    _edit(() {
      if (index == null) {
        _draft.times.add(value);
      } else {
        _draft.times[index] = value;
      }
      _draft.times.sort();
      _draft.routineLink = null; // Customized times are never overwritten.
    }, correction: correction);
  }

  Future<void> _save() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final errors = _errors;
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errors.first)));
      return;
    }
    final effective = _effectiveFrom;
    final next = _next;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save schedule changes?'),
        content: SingleChildScrollView(
          child: Text([
            '${_saved.name} ${_saved.dose}'.trim(),
            '',
            'Previous: ${_describe(_saved)}',
            'New: ${_describe(next)}',
            'Takes effect: ${Fmt.dateTime(effective)}',
            if (next.scheduleEnd != null)
              'Last dose: ${Fmt.dateTime(next.lastDose ?? next.scheduleEnd!)}',
            if (_corrected) 'Prescription details were corrected and verified.',
            '',
            'Past doses and taken records are kept.',
          ].join('\n')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Go Back')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm Changes')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context, _saved.withScheduleFrom(next, effective));
  }

  String _describe(Medicine m) => switch (m.scheduleKind) {
        ScheduleKind.interval =>
          'every ${m.intervalHours} hours, from ${Fmt.dateTime(m.start)}',
        ScheduleKind.prn => 'as needed (no reminders)',
        _ => m.times.map(Fmt.clock).join(', '),
      };

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        content:
            const Text('Your saved schedule and reminders will stay the same.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep Editing')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Widget _timeChips({required bool editable, bool correction = false}) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < _draft.times.length; i++)
          editable
              ? InputChip(
                  label: Text(Fmt.clock(_draft.times[i])),
                  tooltip: 'Change this time',
                  deleteButtonTooltipMessage: 'Remove this time',
                  onPressed: () => _editTime(i, correction: correction),
                  onDeleted: () => _edit(() {
                        _draft.times.removeAt(i);
                        _draft.routineLink = null;
                      }, correction: correction))
              : Chip(label: Text(Fmt.clock(_draft.times[i]))),
        if (editable &&
            (correction || _draft.times.length < (_draft.frequencyPerDay ?? 0)))
          ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(_draft.scheduleKind == ScheduleKind.explicit
                  ? 'Add Written Time'
                  : 'Add Dose Time'),
              onPressed: () => _editTime(null, correction: correction)),
      ]);

  List<Widget> _reminderSection(TextTheme textTheme) {
    switch (_draft.scheduleKind) {
      case ScheduleKind.daily:
        return [
          Text(
              'Change the times you want to be reminded. The number of '
              'doses per day (${_draft.frequencyPerDay}) stays as prescribed.',
              style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          _timeChips(editable: true),
          RoutineSuggestionPanel(
            medicine: _draft,
            routine: _routine,
            onApply: (times, link) => _edit(() {
              _draft.times = [...times];
              _draft.routineLink = link;
            }),
          ),
        ];
      case ScheduleKind.explicit:
        return [
          _timeChips(editable: false),
          const SizedBox(height: 6),
          Text(
              'These times are written on your prescription, so they are '
              'kept. If they were read incorrectly, use "Correct prescription '
              'details" below.',
              style: textTheme.bodyMedium),
        ];
      case ScheduleKind.interval:
        final wake = _routine?[RoutineEvent.wake];
        return [
          Text(
              'Doses stay exactly ${_draft.intervalHours} hours apart, '
              'including overnight. Choose the next dose; the rest follow '
              'from it.',
              style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_started ? 'Next dose' : 'First dose',
                  style: textTheme.titleSmall),
              _anchorChosen
                  ? const StatusBadge(
                      label: 'You chose this', tone: Tone.success)
                  : const StatusBadge(
                      label: 'Unchanged',
                      tone: Tone.info,
                      icon: Icons.schedule),
            ],
          ),
          Text(Fmt.dateTime(_draft.start), style: textTheme.bodyLarge),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await _pickDateTime(_draft.start);
                if (picked != null) {
                  _edit(() {
                    _draft.start = picked;
                    _anchorChosen = true;
                  });
                }
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(_started ? 'Choose Next Dose' : 'Choose First Dose'),
            ),
          ),
          if (wake != null && wake.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _edit(() {
                  final now = _now();
                  var at = Medicine.atTime(now, wake);
                  if (at.isBefore(now)) {
                    at =
                        Medicine.atTime(now.add(const Duration(days: 1)), wake);
                  }
                  _draft.start = at;
                  _anchorChosen = true;
                }),
                icon: const Icon(Icons.wb_twilight),
                label: Text('Use my wake-up time (${Fmt.clock(wake)})'),
              ),
            ),
        ];
      case ScheduleKind.prn:
        return [
          Text('As-needed medicines have no scheduled reminders.',
              style: textTheme.bodyMedium),
        ];
      case ScheduleKind.unknown:
        return [
          const InfoBanner(
              tone: Tone.warning,
              message: 'This schedule is unclear and cannot be edited here. '
                  'Delete it and scan or type the prescription again, or ask '
                  'your pharmacist.'),
        ];
    }
  }

  /// Last dose of the corrected course, when it is valid.
  DateTime? get _lastDosePreview {
    try {
      final next = _next;
      if (next.validationErrors().isNotEmpty) return null;
      return _saved.withScheduleFrom(next, _effectiveFrom).lastDose;
    } catch (_) {
      return null;
    }
  }

  bool get _rateChanged =>
      _draft.scheduleKind != _saved.scheduleKind ||
      _draft.intervalHours != _saved.intervalHours ||
      (_draft.scheduleKind == ScheduleKind.daily &&
          _draft.frequencyPerDay != _saved.frequencyPerDay) ||
      (_draft.scheduleKind == ScheduleKind.explicit &&
          _draft.times.length != _saved.times.length);

  List<Widget> _correctionSection(TextTheme textTheme) => [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _correcting,
          onChanged: (value) => setState(() => _correcting = value),
          title: const Text('Correct prescription details'),
          subtitle: const Text('Only if the saved details do not match your '
              'prescription. Corrections must be verified.'),
        ),
        if (_correcting) ...[
          const InfoBanner(
            tone: Tone.warning,
            message: 'These fields are your prescription record, not '
                'reminder preferences. Change them only to match what your '
                'doctor or pharmacist wrote.',
          ),
          TextFormField(
              initialValue: _draft.name,
              decoration: const InputDecoration(labelText: 'Medication name'),
              onChanged: (v) =>
                  _edit(() => _draft.name = v.trim(), correction: true)),
          const SizedBox(height: 12),
          TextFormField(
              initialValue: _draft.dose,
              decoration: const InputDecoration(
                  labelText: 'Strength / dose', hintText: 'e.g. 500 mg'),
              onChanged: (v) =>
                  _edit(() => _draft.dose = v.trim(), correction: true)),
          if (StrengthCheck.concerns(_draft.name, _draft.dose).isNotEmpty)
            InfoBanner(
              tone: Tone.warning,
              title: 'Check the strength',
              lines: [
                ...StrengthCheck.concerns(_draft.name, _draft.dose),
                'Compare it with your prescription and ask your pharmacist '
                    'if unsure. IMedsU never changes a strength.',
              ],
            ),
          const SizedBox(height: 12),
          TextFormField(
              initialValue: _draft.qtyPerIntake > 0 ? _draft.qtyLabel : '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount per dose'),
              onChanged: (v) => _edit(
                  () => _draft.qtyPerIntake = double.tryParse(v) ?? 0,
                  correction: true)),
          const SizedBox(height: 12),
          DropdownButtonFormField<ScheduleKind>(
            initialValue: _draft.scheduleKind == ScheduleKind.unknown
                ? null
                : _draft.scheduleKind,
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            decoration: const InputDecoration(
                labelText: 'Schedule type (as prescribed)'),
            items: const [
              DropdownMenuItem(
                  value: ScheduleKind.daily,
                  child: Text('Times per day (OD/BID/TID/QID)')),
              DropdownMenuItem(
                  value: ScheduleKind.interval,
                  child: Text('Exact interval (q6h/q8h)')),
              DropdownMenuItem(
                  value: ScheduleKind.explicit,
                  child: Text('Written clock times')),
              DropdownMenuItem(
                  value: ScheduleKind.prn,
                  child: Text('As needed (PRN, no reminders)')),
            ],
            onChanged: (kind) {
              if (kind == null) return;
              _edit(() {
                _draft.scheduleKind = kind;
                _draft.routineLink = null;
                if (kind == ScheduleKind.daily) {
                  _draft.frequencyPerDay ??= _draft.times.length;
                }
                if (kind == ScheduleKind.interval) _anchorChosen = false;
              }, correction: true);
            },
          ),
          const SizedBox(height: 12),
          if (_draft.scheduleKind == ScheduleKind.daily)
            TextFormField(
                initialValue: _draft.frequencyPerDay?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Times per day'),
                onChanged: (v) => _edit(() {
                      _draft.frequencyPerDay = int.tryParse(v);
                      _draft.routineLink = null;
                    }, correction: true)),
          if (_draft.scheduleKind == ScheduleKind.interval)
            TextFormField(
                initialValue: _draft.intervalHours?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Hours between doses'),
                onChanged: (v) => _edit(
                    () => _draft.intervalHours = int.tryParse(v),
                    correction: true)),
          if (_draft.scheduleKind == ScheduleKind.daily ||
              _draft.scheduleKind == ScheduleKind.explicit) ...[
            const SizedBox(height: 8),
            Text('Prescribed or reminder times', style: textTheme.bodyMedium),
            const SizedBox(height: 6),
            _timeChips(editable: true, correction: true),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _draft.end == null,
            title: const Text('Ongoing, no end date (maintenance)'),
            subtitle: const Text('Reminders continue until you edit or '
                'delete this medicine.'),
            onChanged: (ongoing) => _edit(() {
              _endEdited = true;
              _draft.days = null;
              _draft.durationConfirmed = true;
              _draft.end = ongoing
                  ? null
                  : (_saved.scheduleEnd ?? _now().add(const Duration(days: 7)));
            }, correction: true),
          ),
          if (_draft.end != null) ...[
            TextFormField(
              key: const ValueKey('course-days'),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Course length in days (optional)',
                helperText: 'Counted from the original start, '
                    '${Fmt.dateTime(_saved.originalStart)}.',
                helperMaxLines: 2,
              ),
              onChanged: (v) {
                final days = int.tryParse(v.trim());
                if (days == null || days <= 0 || days > 3650) return;
                _edit(() {
                  _endEdited = true;
                  final s = _saved.originalStart;
                  _draft.end =
                      DateTime(s.year, s.month, s.day + days, s.hour, s.minute);
                }, correction: true);
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await _pickDateTime(_draft.end!);
                  if (picked != null) {
                    _edit(() {
                      _endEdited = true;
                      _draft.end = picked;
                    }, correction: true);
                  }
                },
                icon: const Icon(Icons.event_busy_outlined),
                label: Text(
                    'Ends: ${Fmt.dateTime(_draft.end!)} (no doses from then)'),
              ),
            ),
            if (_lastDosePreview != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Last dose: ${Fmt.dateTime(_lastDosePreview!)}',
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
          ] else
            Text('Reminders continue until you change or stop this schedule.',
                style: textTheme.bodySmall),
          const SizedBox(height: 12),
          TextFormField(
              initialValue: _draft.instructions,
              maxLines: null,
              decoration: const InputDecoration(
                  labelText: 'Directions (as interpreted)',
                  helperText: 'The original prescription text below is kept '
                      'unchanged.'),
              onChanged: (v) => _edit(() => _draft.instructions = v.trim(),
                  correction: true)),
          const SizedBox(height: 12),
          TextFormField(
              initialValue: _draft.stock?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Quantity bought (optional)'),
              onChanged: (v) => _edit(() => _draft.stock = int.tryParse(v),
                  correction: true)),
          if (_saved.sourceText != null) ...[
            const SizedBox(height: 12),
            Text('Original prescription text (kept as read)',
                style: textTheme.bodySmall),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(color: AppColors.divider),
              ),
              child: SelectableText(_saved.sourceText!),
            ),
          ],
          if (_started)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  'This medicine already has dose history, so its original '
                  'start (${Fmt.dateTime(_saved.originalStart)}) and past '
                  'doses stay as recorded. Corrections apply to future doses.',
                  style: textTheme.bodySmall),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _correctionVerified,
            onChanged: _corrected
                ? (v) => setState(() => _correctionVerified = v == true)
                : null,
            title: const Text(AppStrings.iveVerifiedThis),
            subtitle: const Text('I checked the corrected details against my '
                'prescription.'),
          ),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = _now();
    final errors = _dirty ? _errors : const <String>[];
    final todayReason =
        ScheduleEdit.todayBlockReason(_saved, _draft.times, now);
    final todayAllowed = todayReason == null;
    final preview = errors.isEmpty && _draft.scheduleKind != ScheduleKind.prn
        ? _saved
            .withScheduleFrom(_next, _effectiveFrom)
            .allDoses(horizon: now.add(const Duration(days: 3)), from: now)
            .take(8)
            .toList()
        : <DateTime>[];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.correctPrescription
                ? 'Edit Medication'
                : 'Edit Schedule')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_saved.name} ${_saved.dose}'.trim(),
                          style: textTheme.titleLarge),
                      const SizedBox(height: 6),
                      ScheduleBasisBadge(_draft),
                      const SizedBox(height: 8),
                      Text(_saved.frequencyLabel, style: textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text('Original directions', style: textTheme.bodySmall),
                      Text(
                          _saved.instructions.isEmpty
                              ? '(none written)'
                              : _saved.instructions,
                          style: textTheme.bodyLarge),
                    ]),
              ),
            ),
            const SectionHeader('Reminder Times', icon: Icons.alarm),
            ..._reminderSection(textTheme),
            if (_isClock && _started) ...[
              const SectionHeader('Applies From',
                  icon: Icons.event_available_outlined),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: true,
                      label: const Text('Today'),
                      enabled: todayAllowed),
                  const ButtonSegment(value: false, label: Text('Tomorrow')),
                ],
                selected: {_applyToday && todayAllowed},
                onSelectionChanged: (value) =>
                    setState(() => _applyToday = value.first),
              ),
              const SizedBox(height: 6),
              Text(
                  todayAllowed
                      ? "Today's earlier doses stay as they were. Today's "
                          'remaining doses follow the new times.'
                      : todayReason,
                  style: textTheme.bodySmall),
            ],
            if (_isClock && !_started) ...[
              const SectionHeader('Start', icon: Icons.event_outlined),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickDateTime(_draft.start);
                    if (picked != null) _edit(() => _draft.start = picked);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Starts: ${Fmt.dateTime(_draft.start)}'),
                ),
              ),
            ],
            const SectionHeader('Prescription Details',
                icon: Icons.medication_outlined),
            ..._correctionSection(textTheme),
            if (errors.isNotEmpty)
              InfoBanner(
                  tone: Tone.error, title: 'Fix before saving', lines: errors),
            if (preview.isNotEmpty) ...[
              const SectionHeader('Upcoming Reminders',
                  icon: Icons.event_note_outlined,
                  subtitle: 'How your next doses will be scheduled'),
              for (final dose in preview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('•  ${Fmt.dateTime(dose)}',
                      style: textTheme.bodyMedium),
                ),
            ],
            const SizedBox(height: 8),
            Text('Past doses and taken records are never changed.',
                style: textTheme.bodySmall),
          ],
        ),
        bottomNavigationBar: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Material(
            color: AppColors.surface,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: () =>
                            _dirty ? _confirmDiscard() : Navigator.pop(context),
                        child: const Text(AppStrings.cancel)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                        onPressed: _save, child: const Text('Save Changes')),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
