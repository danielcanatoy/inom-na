import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/med_names.dart';
import '../services/rx_parser.dart';
import '../services/strength_check.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../models/routine.dart';
import '../services/store.dart';
import '../ui/routine_suggestion.dart';
import 'routine_screen.dart';

/// Every prescription field and the resulting schedule must be reviewed.
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({super.key, required this.result, required this.rawText});
  final ParseResult result;
  final String rawText;
  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late final List<Medicine> _meds =
      widget.result.meds.map((m) => Medicine.fromJson(m.toJson())).toList();
  final Set<String> _verified = {};
  final Set<String> _startReviewed = {};

  /// Strength the user confirmed comparing (per medicine). Editing the
  /// strength clears it, so a changed value must be compared again.
  final Map<String, String> _strengthChecked = {};

  List<String> _strengthConcerns(Medicine m) =>
      StrengthCheck.concerns(m.name, m.dose, sourceText: widget.rawText);

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  List<String> _errors(Medicine m) => [
        ...m.validationErrors(),
        if (m.scheduleKind == ScheduleKind.interval &&
            !_startReviewed.contains(m.id))
          'Choose the first dose date and time (the time shown is only a '
              'suggestion).',
        if (_strengthConcerns(m).isNotEmpty && _strengthChecked[m.id] != m.dose)
          'Compare the strength with your prescription, then tick '
              '"I compared this strength".',
        if (m.scheduleKind == ScheduleKind.interval &&
            m.intervalHours != null &&
            m.intervalHours! > 0 &&
            m.times.any((time) =>
                Medicine.validTime(time) &&
                (Medicine.atTime(m.start, time)
                            .difference(DateTime(m.start.year, m.start.month,
                                m.start.day, m.start.hour, m.start.minute))
                            .inMinutes %
                        (m.intervalHours! * 60) !=
                    0)))
          'The first dose and interval do not match the written times. '
              'Correct the times using your prescription before verifying.',
      ];

  void _verify(Medicine m) {
    final errors = _errors(m);
    if (errors.isNotEmpty) {
      _message(errors.join('\n'));
      return;
    }
    setState(() => _verified.add(m.id));
  }

  void _save() {
    if (_meds.isEmpty) {
      _message('Add a medication first.');
      return;
    }
    for (final m in _meds) {
      final errors = _errors(m);
      if (errors.isNotEmpty || !_verified.contains(m.id)) {
        _message(errors.isEmpty
            ? 'Review and verify each medication and its schedule before saving.'
            : errors.join('\n'));
        return;
      }
    }
    Navigator.pop(context, _meds);
  }

  bool get _usedLaptopAi => widget.result.source != RxParser.srcOffline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final verifiedCount = _meds.where((m) => _verified.contains(m.id)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Prescription')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                    _usedLaptopAi
                        ? Icons.laptop_chromebook_outlined
                        : Icons.phone_android_outlined,
                    color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Read by', style: textTheme.bodySmall),
                        Text(widget.result.source,
                            style: textTheme.titleMedium),
                        if (widget.result.note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(widget.result.note!,
                                style: textTheme.bodyMedium),
                          ),
                      ]),
                ),
              ]),
            ),
          ),
          const InfoBanner(
            tone: Tone.warning,
            title: 'Check every detail',
            message: AppStrings.reviewWarning,
          ),
          Text(
              'Privacy: the photo and the text read from it may be sent to '
              'the Ollama AI on your laptop over your local network '
              '(unencrypted HTTP). Your medications and reminders are '
              'saved on this phone.',
              style: textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Original text read from prescription'),
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                            widget.rawText.isEmpty ? '(none)' : widget.rawText),
                      )),
                ]),
          ),
          if (_meds.isEmpty)
            const EmptyState(
              title: 'No medications found',
              message: 'Try again with a clearer photo, type the '
                  'prescription, or add a medication below.',
            ),
          if (_meds.isNotEmpty)
            SectionHeader(
                '${_meds.length} ${_meds.length == 1 ? "medication" : "medications"} found',
                subtitle: '$verifiedCount of ${_meds.length} verified'),
          for (final (index, m) in _meds.indexed)
            _MedEditor(
              key: ValueKey(m.id),
              index: index + 1,
              med: m,
              warning: widget.result.warnings[m.id],
              verified: _verified.contains(m.id),
              startReviewed: _startReviewed.contains(m.id),
              errors: _errors(m),
              rawText: widget.rawText,
              strengthConcerns: _strengthConcerns(m),
              strengthChecked: _strengthChecked[m.id] == m.dose,
              onStrengthChecked: (checked) => setState(() {
                checked
                    ? _strengthChecked[m.id] = m.dose
                    : _strengthChecked.remove(m.id);
                _verified.remove(m.id);
              }),
              onChanged: () => setState(() => _verified.remove(m.id)),
              onStartReviewed: () => setState(() {
                _startReviewed.add(m.id);
                _verified.remove(m.id);
              }),
              onVerify: () => _verify(m),
              onRemove: () => setState(() {
                _meds.remove(m);
                _verified.remove(m.id);
                _startReviewed.remove(m.id);
                _strengthChecked.remove(m.id);
              }),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => setState(
                  () => _meds.add(Medicine(id: Medicine.newId(), name: ''))),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addMedication)),
        ],
      ),
      // Raised by the keyboard height so Save stays reachable while typing;
      // snack bars float above it instead of covering it.
      bottomNavigationBar: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Material(
          color: AppColors.surface,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_meds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                        verifiedCount == _meds.length
                            ? 'All ${_meds.length} verified. Ready to save.'
                            : '$verifiedCount of ${_meds.length} verified. '
                                'Verify every medication to save.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.alarm_on),
                      label: const Text(AppStrings.saveAndSetReminders)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DurationChoice { unknown, days, end, maintenance }

class _MedEditor extends StatefulWidget {
  const _MedEditor({
    super.key,
    required this.index,
    required this.med,
    required this.verified,
    required this.startReviewed,
    required this.errors,
    required this.onChanged,
    required this.onStartReviewed,
    required this.onVerify,
    required this.onRemove,
    required this.rawText,
    required this.strengthConcerns,
    required this.strengthChecked,
    required this.onStrengthChecked,
    this.warning,
  });
  final String rawText;
  final List<String> strengthConcerns;
  final bool strengthChecked;
  final ValueChanged<bool> onStrengthChecked;
  final int index;
  final Medicine med;
  final bool verified;
  final bool startReviewed;
  final List<String> errors;
  final VoidCallback onChanged;
  final VoidCallback onStartReviewed;
  final VoidCallback onVerify;
  final VoidCallback onRemove;
  final String? warning;
  @override
  State<_MedEditor> createState() => _MedEditorState();
}

class _MedEditorState extends State<_MedEditor> {
  Medicine get m => widget.med;

  /// Problems found when the prescription was read. They are shown live in
  /// "Fix before verifying" instead, so they are not repeated as warnings.
  late final Set<String> _initialErrors = m.validationErrors().toSet();
  late _DurationChoice _duration = !m.durationConfirmed
      ? _DurationChoice.unknown
      : m.days != null
          ? _DurationChoice.days
          : m.end != null
              ? _DurationChoice.end
              : _DurationChoice.maintenance;

  void _change(VoidCallback edit) {
    setState(edit);
    widget.onChanged();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final day = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(initial.year < 2000 ? initial.year : 2000),
        lastDate: DateTime(initial.year > 2100 ? initial.year : 2100, 12, 31));
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _setUpRoutine() async {
    await Navigator.push<RoutineResult>(context,
        MaterialPageRoute(builder: (_) => const RoutineScreen(medicines: [])));
    if (mounted) setState(() {});
  }

  /// Sets the first interval dose to the next wake-up time (a user choice).
  void _useWakeTime(DailyRoutine routine) {
    final now = DateTime.now();
    final wake = routine[RoutineEvent.wake];
    var at = Medicine.atTime(now, wake);
    if (at.isBefore(now)) {
      at = Medicine.atTime(now.add(const Duration(days: 1)), wake);
    }
    _change(() => m.start = at);
    widget.onStartReviewed();
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(m.start);
    if (picked == null || !mounted) return;
    _change(() => m.start = picked);
    widget.onStartReviewed();
  }

  Future<void> _pickEnd() async {
    final picked =
        await _pickDateTime(m.end ?? m.start.add(const Duration(days: 7)));
    if (picked == null || !mounted) return;
    _change(() {
      m.end = picked;
      m.days = null;
      m.durationConfirmed = true;
    });
  }

  Future<void> _editTime(int? index) async {
    final base = index == null ? '08:00' : m.times[index];
    final initial = Medicine.validTime(base)
        ? TimeOfDay(
            hour: int.parse(base.substring(0, 2)),
            minute: int.parse(base.substring(3)))
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    if (m.times
        .asMap()
        .entries
        .any((entry) => entry.key != index && entry.value == value)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This time has already been added.')));
      return;
    }
    _change(() {
      if (index == null) {
        m.times.add(value);
      } else {
        m.times[index] = value;
      }
      m.times.sort();
      m.routineLink = null; // Customized times are never overwritten later.
    });
  }

  InputDecoration _dec(String label, [String? hint, String? helper]) =>
      InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3);

  // Long values wrap inside the field instead of overflowing (see layout test).
  Widget _dropdown<T>({
    required T value,
    required String label,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        decoration: _dec(label),
        items: [
          for (final (itemValue, text) in items)
            DropdownMenuItem(value: itemValue, child: Text(text)),
        ],
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      );

  /// Sets the first interval dose to a time written on the prescription
  /// (next occurrence from the suggested start). An explicit user choice.
  void _useWrittenTime(String hhmm) {
    final now = DateTime.now();
    final base = m.start.isBefore(now) ? now : m.start;
    var at = Medicine.atTime(base, hhmm);
    if (at.isBefore(now)) {
      at = Medicine.atTime(base.add(const Duration(days: 1)), hhmm);
    }
    _change(() => m.start = at);
    widget.onStartReviewed();
  }

  /// Clock times of one day of an interval schedule, from the first dose.
  List<String> _intervalPattern() {
    final hours = m.intervalHours;
    if (hours == null || hours <= 0 || hours > 24) return const [];
    return [
      for (var i = 0; i * hours < 24; i++)
        Fmt.time(m.start.add(Duration(hours: i * hours))),
    ];
  }

  Widget _timeChips({required String addLabel, required bool canAdd}) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < m.times.length; i++)
          InputChip(
              label: Text(Fmt.clock(m.times[i])),
              tooltip: 'Change this time',
              deleteButtonTooltipMessage: 'Remove this time',
              onPressed: () => _editTime(i),
              onDeleted: () => _change(() {
                    m.times.removeAt(i);
                    m.routineLink = null;
                  })),
        if (canAdd)
          ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(addLabel),
              onPressed: () => _editTime(null)),
      ]);

  List<Widget> _intervalSection(TextTheme textTheme, DailyRoutine? routine) {
    final confirmed = widget.startReviewed;
    final pattern = _intervalPattern();
    return [
      TextFormField(
          key: const ValueKey('interval-hours'),
          initialValue: m.intervalHours?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: _dec('Hours between doses', 'e.g. 8 for q8h'),
          onChanged: (v) => _change(() => m.intervalHours = int.tryParse(v))),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: confirmed ? AppColors.successLight : AppColors.warningLight,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('First dose', style: textTheme.titleSmall),
              confirmed
                  ? const StatusBadge(label: 'Confirmed', tone: Tone.success)
                  : const StatusBadge(
                      label: 'Not confirmed',
                      tone: Tone.warning,
                      icon: Icons.help_outline),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              confirmed
                  ? Fmt.dateTime(m.start)
                  : 'Suggested: ${Fmt.dateTime(m.start)} (when the '
                      'prescription was read). Choose the real first dose.',
              style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: _pickStart,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                    confirmed ? 'Change First Dose' : 'Choose First Dose')),
          ),
          if (m.times.any(Medicine.validTime) || routine != null)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final time in m.times)
                if (Medicine.validTime(time))
                  ActionChip(
                      label: Text('First dose at ${Fmt.clock(time)}'),
                      onPressed: () => _useWrittenTime(time)),
              if (routine != null)
                ActionChip(
                    avatar: const Icon(Icons.wb_twilight, size: 18),
                    label: Text('At my wake-up time '
                        '(${Fmt.clock(routine[RoutineEvent.wake])})'),
                    onPressed: () => _useWakeTime(routine)),
            ]),
        ]),
      ),
      if (pattern.isNotEmpty) ...[
        const SizedBox(height: 10),
        ScheduleBasisBadge(m),
        const SizedBox(height: 4),
        Text(
            'Every ${m.intervalHours} hours: ${pattern.join(', ')}, '
            'repeating daily${confirmed ? '' : ' (from the suggested first dose)'}.',
            style: textTheme.bodyMedium),
      ],
      if (m.times.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
            'Times written on the prescription (used only to check the '
            'first dose; remove any that were misread):',
            style: textTheme.bodySmall),
        const SizedBox(height: 6),
        _timeChips(addLabel: '', canAdd: false),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nameWarning = MedNames.check(m.name).warning;
    final routine = Store.routine;
    final errors = widget.errors;
    final valid = m.validationErrors().isEmpty;
    final provisional = !widget.verified ||
        (m.scheduleKind == ScheduleKind.interval && !widget.startReviewed);
    final preview = valid
        ? m.allDoses(
            from: m.start, horizon: m.start.add(const Duration(days: 2)))
        : <DateTime>[];
    final lastDose = valid ? m.lastDose : null;
    final initialWarning = widget.warning ?? '';
    final warnings = [
      for (final line in initialWarning.split('\n'))
        if (line.trim().isNotEmpty &&
            line != RxParser.genericReviewNote &&
            !_initialErrors.contains(line))
          line,
      if (nameWarning != null && !initialWarning.contains(nameWarning))
        nameWarning,
      for (final note in m.reviewNotes)
        if (!initialWarning.contains(note)) note,
    ];
    final (statusLabel, statusTone) = widget.verified
        ? (AppStrings.verified, Tone.success)
        : errors.isEmpty
            ? (AppStrings.readyToVerify, Tone.info)
            : ('${AppStrings.needsAttention} (${errors.length})', Tone.warning);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
        side: BorderSide(
            color: widget.verified ? AppColors.success : AppColors.divider,
            width: widget.verified ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${AppStrings.medication} ${widget.index}',
                      style: textTheme.titleMedium),
                  StatusBadge(label: statusLabel, tone: statusTone),
                ],
              ),
            ),
            IconButton(
                tooltip: 'Remove this medication',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close)),
          ]),
          if (warnings.isNotEmpty)
            InfoBanner(
                tone: Tone.warning,
                title: 'Check these details',
                lines: warnings),

          // ---- Medicine ----
          const SectionHeader('Medicine', icon: Icons.medication_outlined),
          TextFormField(
              initialValue: m.name,
              decoration: _dec('Medication name', 'e.g. Amoxicillin'),
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => _change(() => m.name = v.trim())),
          const SizedBox(height: 12),
          TextFormField(
              initialValue: m.dose,
              decoration: _dec('Strength / dose', 'e.g. 500 mg'),
              onChanged: (v) => _change(() => m.dose = v.trim())),
          if (widget.strengthConcerns.isNotEmpty) ...[
            InfoBanner(
              tone: Tone.warning,
              title: 'Check the strength',
              lines: [
                ...widget.strengthConcerns,
                'Compare it with the original prescription. If unsure, ask '
                    'your pharmacist. IMedsU never changes a strength.',
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: widget.strengthChecked,
              onChanged: (v) => widget.onStrengthChecked(v == true),
              title: const Text('I compared this strength'),
              subtitle: const Text('It matches my prescription or was '
                  'confirmed by my pharmacist.'),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
              initialValue: m.qtyPerIntake > 0 ? m.qtyLabel : '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec('Amount per dose', 'e.g. 1 or 0.5',
                  'Number of tablets, capsules or mL each time.'),
              onChanged: (v) =>
                  _change(() => m.qtyPerIntake = double.tryParse(v) ?? 0)),

          // ---- Schedule ----
          const SectionHeader('Schedule', icon: Icons.schedule),
          _dropdown<ScheduleKind>(
            value: m.scheduleKind,
            label: 'Schedule type (as prescribed)',
            items: const [
              (ScheduleKind.unknown, 'Not clear yet'),
              (ScheduleKind.daily, 'Times per day (OD/BID/TID/QID)'),
              (ScheduleKind.interval, 'Exact interval (q6h/q8h)'),
              (ScheduleKind.explicit, 'Written clock times'),
              (ScheduleKind.prn, 'As needed (PRN, no reminders)'),
            ],
            onChanged: (kind) => _change(() {
              m.scheduleKind = kind;
              m.routineLink = null;
            }),
          ),
          const SizedBox(height: 12),
          if (m.scheduleKind == ScheduleKind.interval)
            ..._intervalSection(textTheme, routine),
          if (m.scheduleKind == ScheduleKind.daily) ...[
            TextFormField(
                key: const ValueKey('daily-frequency'),
                initialValue: m.frequencyPerDay?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _dec('Times per day'),
                onChanged: (v) => _change(() {
                      m.frequencyPerDay = int.tryParse(v);
                      m.routineLink = null;
                    })),
            const SizedBox(height: 8),
            ScheduleBasisBadge(m),
            const SizedBox(height: 6),
            Text(
                m.routineLink != null
                    ? 'Reminder times from My Daily Routine (not part of '
                        'your prescription).'
                    : 'Suggested reminder times. Adjust them to match your '
                        'prescription.',
                style: textTheme.bodySmall),
            const SizedBox(height: 6),
            _timeChips(addLabel: 'Add Reminder Time', canAdd: true),
            RoutineSuggestionPanel(
              key: ValueKey('routine-${m.frequencyPerDay}'),
              medicine: m,
              routine: routine,
              onApply: (times, link) => _change(() {
                m.times = [...times];
                m.routineLink = link;
              }),
              onSetUpRoutine: routine == null ? _setUpRoutine : null,
            ),
          ],
          if (m.scheduleKind == ScheduleKind.explicit) ...[
            ScheduleBasisBadge(m),
            const SizedBox(height: 6),
            Text('Clock times written on the prescription. Compare each one.',
                style: textTheme.bodySmall),
            const SizedBox(height: 6),
            _timeChips(addLabel: 'Add Written Time', canAdd: true),
          ],
          if (m.scheduleKind != ScheduleKind.interval) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Start: ${Fmt.dateTime(m.start)}')),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Reminders begin from this date and time.',
                  style: textTheme.bodySmall),
            ),
          ],

          // ---- Duration ----
          const SectionHeader('Duration', icon: Icons.date_range_outlined),
          _dropdown<_DurationChoice>(
            value: _duration,
            label: 'How long to take it (as prescribed)',
            items: const [
              (_DurationChoice.unknown, 'Not clear yet'),
              (_DurationChoice.days, 'For a number of days'),
              (_DurationChoice.end, 'Until a specific date'),
              (
                _DurationChoice.maintenance,
                'Ongoing, no end date (maintenance)'
              ),
            ],
            onChanged: (choice) => _change(() {
              _duration = choice;
              if (choice != _DurationChoice.days) m.days = null;
              if (choice != _DurationChoice.end) m.end = null;
              m.durationConfirmed = choice == _DurationChoice.maintenance ||
                  (choice == _DurationChoice.days &&
                      m.days != null &&
                      m.days! > 0) ||
                  (choice == _DurationChoice.end && m.end != null);
            }),
          ),
          if (_duration == _DurationChoice.days)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                    key: const ValueKey('duration-days'),
                    initialValue: m.days?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: _dec('How many days', 'e.g. 7',
                        'Counted from the first dose or start time.'),
                    onChanged: (v) => _change(() {
                          m.days = int.tryParse(v);
                          m.end = null;
                          m.durationConfirmed = m.days != null && m.days! > 0;
                        }))),
          if (_duration == _DurationChoice.end)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.event_busy_outlined),
                    label: Text(m.end == null
                        ? 'Choose the end date and time'
                        : 'Ends: ${Fmt.dateTime(m.end!)} (no doses from then)')),
              ),
            ),
          if (_duration == _DurationChoice.maintenance)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Reminders continue every day until you edit or delete this '
                  'medicine. Choose this only if your prescription says to '
                  'continue.',
                  style: textTheme.bodySmall),
            ),
          if (lastDose != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Last dose: ${Fmt.dateTime(lastDose)}',
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),

          // ---- Other details ----
          const SectionHeader('Other details', icon: Icons.notes_outlined),
          TextFormField(
              initialValue: m.stock?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: _dec('Quantity bought (optional)', 'e.g. 21',
                  'Used for the running-low reminder.'),
              onChanged: (v) => _change(() => m.stock = int.tryParse(v))),
          const SizedBox(height: 12),
          TextFormField(
              initialValue: m.instructions,
              maxLines: null,
              decoration: _dec(
                  'Directions as written', null, 'Keep the original wording.'),
              onChanged: (v) => _change(() => m.instructions = v.trim())),

          // ---- Preview ----
          if (preview.isNotEmpty) ...[
            SectionHeader(
                provisional
                    ? 'Schedule preview (not confirmed yet)'
                    : 'Schedule preview',
                icon: Icons.event_note_outlined,
                subtitle: provisional
                    ? 'This becomes your schedule only after you verify it.'
                    : 'First doses from the start'),
            for (final dose in preview.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('•  ${Fmt.dateTime(dose)}',
                    style: textTheme.bodyMedium?.copyWith(
                        color: provisional ? AppColors.textSecondary : null)),
              ),
          ],

          // ---- Verification ----
          const SectionHeader('Verification', icon: Icons.verified_outlined),
          if (errors.isNotEmpty)
            InfoBanner(
                tone: Tone.error, title: 'Fix before verifying', lines: errors),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: widget.verified,
              title: Text(AppStrings.iveVerifiedThis,
                  style: textTheme.titleMedium),
              subtitle: const Text('Name, strength, amount, schedule, '
                  'duration and directions match my prescription.'),
              onChanged: (checked) {
                if (checked == true) {
                  widget.onVerify();
                } else {
                  widget.onChanged();
                }
              }),
        ]),
      ),
    );
  }
}
