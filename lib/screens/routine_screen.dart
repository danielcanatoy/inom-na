import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../models/routine.dart';
import '../services/routine_schedule.dart';
import '../services/schedule_edit.dart';
import '../services/store.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../ui/format.dart';

/// Returned when the routine was saved. [updated] holds medicines whose
/// reminder times the user confirmed to change (history preserved).
class RoutineResult {
  const RoutineResult(this.updated);
  final List<Medicine> updated;
}

enum _ProposalChoice { apply, keep }

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, required this.medicines, this.clock});

  /// Saved medicines, used only to propose (never silently apply) updates.
  final List<Medicine> medicines;
  final DateTime Function()? clock;

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  final DailyRoutine? _saved = Store.routine;
  late DailyRoutine _draft = _saved ?? DailyRoutine.pickerDefaults;
  bool _dirty = false;
  bool _busy = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  static const _icons = {
    RoutineEvent.wake: Icons.wb_twilight,
    RoutineEvent.breakfast: Icons.free_breakfast_outlined,
    RoutineEvent.lunch: Icons.wb_sunny_outlined,
    RoutineEvent.dinner: Icons.restaurant_outlined,
    RoutineEvent.bedtime: Icons.bedtime_outlined,
  };

  String _display(String hhmm) {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    return use24 ? hhmm : Fmt.clock(hhmm);
  }

  Future<void> _pick(RoutineEvent event) async {
    final minutes = DailyRoutine.minutesOf(_draft[event]) ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      helpText: '${event.label} time'.toUpperCase(),
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(
          event, DailyRoutine.format(picked.hour * 60 + picked.minute));
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final errors = _draft.validationErrors();
    if (errors.isNotEmpty) {
      _snack(errors.first);
      return;
    }
    if (!_dirty && _saved != null) {
      Navigator.pop(context);
      return;
    }
    final now = _now();
    final proposals = RoutineScheduler.proposals(widget.medicines, _draft, now);
    var updated = <Medicine>[];
    if (proposals.isNotEmpty) {
      final choice = await showDialog<(_ProposalChoice, Set<String>)>(
        context: context,
        builder: (_) => _ProposalDialog(
          proposals: proposals,
          unlinked: widget.medicines.length - proposals.length,
          now: now,
        ),
      );
      if (choice == null || !mounted) return; // Cancel: nothing is saved.
      if (choice.$1 == _ProposalChoice.apply) {
        updated = [
          for (final p in proposals)
            if (choice.$2.contains(p.medicine.id))
              ScheduleEdit.applyTimes(p.medicine, p.newTimes, now),
        ];
      }
    }
    setState(() => _busy = true);
    try {
      await Store.saveRoutine(_draft);
      if (mounted) Navigator.pop(context, RoutineResult(updated));
    } catch (_) {
      _snack('Your daily routine could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your routine changes have not been saved.'),
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final errors = _draft.validationErrors();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('My Daily Routine')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const InfoBanner(
              tone: Tone.info,
              message: 'Set your usual daily routine to help IMedsU suggest '
                  'convenient medication reminder times. Your prescription '
                  'instructions will always take priority.',
            ),
            if (_saved == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                    'These are starting values only. Adjust them to your '
                    'usual day, then save.',
                    style: textTheme.bodyMedium),
              ),
            for (final event in RoutineEvent.values)
              Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(_icons[event], color: AppColors.primary),
                  title:
                      Text('${event.label} Time', style: textTheme.titleMedium),
                  subtitle: Text(_display(_draft[event]),
                      style: textTheme.bodyLarge
                          ?.copyWith(color: AppColors.primaryDark)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _pick(event),
                ),
              ),
            if (errors.isNotEmpty)
              InfoBanner(
                  tone: Tone.error,
                  title: 'Please check your routine',
                  lines: errors),
            const SizedBox(height: 4),
            Text(
                'Bedtime can be after midnight. Times are only used to '
                'suggest reminders; prescribed times and fixed intervals '
                'never change.',
                style: textTheme.bodySmall),
          ],
        ),
        bottomNavigationBar: Material(
          color: AppColors.surface,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _dirty
                              ? _confirmDiscard()
                              : Navigator.pop(context),
                      child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Save Changes')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProposalDialog extends StatefulWidget {
  const _ProposalDialog(
      {required this.proposals, required this.unlinked, required this.now});
  final List<RoutineProposal> proposals;
  final int unlinked;
  final DateTime now;

  @override
  State<_ProposalDialog> createState() => _ProposalDialogState();
}

class _ProposalDialogState extends State<_ProposalDialog> {
  late final Set<String> _selected = {
    for (final p in widget.proposals) p.medicine.id
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Your daily routine has changed'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Some medication reminder times can be updated to '
                'match your new routine. Prescribed times and fixed '
                'intervals are never changed. Past doses are kept.'),
            const SizedBox(height: 8),
            for (final p in widget.proposals)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(p.medicine.id),
                onChanged: (value) => setState(() => value == true
                    ? _selected.add(p.medicine.id)
                    : _selected.remove(p.medicine.id)),
                title: Text('${p.medicine.name} ${p.medicine.dose}'.trim(),
                    style: textTheme.titleSmall),
                subtitle: Text(
                    'Previous: ${p.medicine.times.map(Fmt.clock).join(', ')}\n'
                    'Proposed: ${p.newTimes.map(Fmt.clock).join(', ')}\n'
                    'Starts: ${ScheduleEdit.canApplyToday(p.medicine, p.newTimes, widget.now) ? "today" : "tomorrow"}'),
              ),
            if (widget.unlinked > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '${widget.unlinked} other '
                    '${widget.unlinked == 1 ? "medication is" : "medications are"} '
                    'not linked to your routine and will stay the same.',
                    style: textTheme.bodySmall),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () =>
                Navigator.pop(context, (_ProposalChoice.keep, <String>{})),
            child: const Text('Keep Current Schedules')),
        FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(
                    context, (_ProposalChoice.apply, Set.of(_selected))),
            child: const Text('Apply Selected Changes')),
      ],
    );
  }
}
