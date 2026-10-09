import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/strength_check.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../ui/format.dart';
import '../ui/routine_suggestion.dart';
import 'edit_schedule_screen.dart';

/// Read-only summary of a saved medicine. Returns a revised medicine if the
/// user confirmed a schedule edit, otherwise null.
class MedicationDetailsScreen extends StatelessWidget {
  const MedicationDetailsScreen({super.key, required this.medicine});
  final Medicine medicine;

  Widget _row(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: textTheme.bodySmall),
        Text(value, style: textTheme.bodyLarge),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final textTheme = Theme.of(context).textTheme;
    final end = m.scheduleEnd;
    final reminders = switch (m.scheduleKind) {
      ScheduleKind.interval => 'Every ${m.intervalHours} hours, counted from '
          '${Fmt.dateTime(m.start)}',
      ScheduleKind.prn => 'None (as needed)',
      _ => m.times.isEmpty ? 'None' : m.times.map(Fmt.clock).join(', '),
    };
    final total = m.totalDoses;
    return Scaffold(
      appBar: AppBar(title: const Text('Medication Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.name} ${m.dose}'.trim(),
                        style: textTheme.titleLarge),
                    const SizedBox(height: 8),
                    ScheduleBasisBadge(m),
                    const Divider(height: 24),
                    _row(context, 'Strength / dose',
                        m.dose.isEmpty ? '(not entered)' : m.dose),
                    _row(context, 'Amount per dose', m.qtyLabel),
                    _row(context, 'Schedule', m.frequencyLabel),
                    _row(context, 'Reminder times', reminders),
                    _row(context, 'Started', Fmt.dateTime(m.originalStart)),
                    _row(
                        context,
                        'Last dose',
                        m.isPrn
                            ? 'Not applicable (as needed)'
                            : end == null
                                ? 'Ongoing, no end date (maintenance)'
                                : Fmt.dateTime(m.lastDose ?? end)),
                    _row(
                        context,
                        'Directions as written',
                        m.instructions.isEmpty
                            ? '(none written)'
                            : m.instructions),
                    _row(
                        context,
                        'Doses marked taken',
                        total == null
                            ? '${m.taken.toSet().length}'
                            : '${m.taken.toSet().length} of $total planned'),
                  ]),
            ),
          ),
          if (StrengthCheck.concerns(m.name, m.dose).isNotEmpty)
            InfoBanner(
              tone: Tone.warning,
              title: 'Check the strength',
              lines: [
                ...StrengthCheck.concerns(m.name, m.dose),
                'Compare it with your prescription and ask your pharmacist '
                    'if unsure. To correct it, use Edit Schedule > Correct '
                    'prescription details.',
              ],
            ),
          if (m.revisions.isNotEmpty) ...[
            const SectionHeader('Schedule changes', icon: Icons.history),
            for (final revision in m.revisions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    '•  Changed from ${Fmt.dateTime(revision.until)} '
                    '(earlier doses kept their original times)',
                    style: textTheme.bodyMedium),
              ),
          ],
          if (m.legacy)
            const InfoBanner(
                tone: Tone.warning,
                message: 'Saved by an earlier version: the original schedule '
                    'was kept. Compare it with your prescription.'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final revised = await Navigator.push<Medicine>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EditScheduleScreen(medicine: m)));
                if (revised != null && context.mounted) {
                  Navigator.pop(context, revised);
                }
              },
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Edit Schedule'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              'Editing changes future reminders only. Past doses and taken '
              'records are kept.',
              style: textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
