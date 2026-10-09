import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../services/dose_status.dart';
import 'app_strings.dart';
import 'app_theme.dart';
import 'components.dart';
import 'format.dart';

extension DoseStatusLabel on DoseStatus {
  (String, Tone, IconData) get badge => switch (this) {
        DoseStatus.taken => (
            AppStrings.taken,
            Tone.success,
            Icons.check_circle
          ),
        DoseStatus.upcoming => (AppStrings.upcoming, Tone.info, Icons.schedule),
        DoseStatus.overdue => (
            AppStrings.overdue,
            Tone.warning,
            Icons.error_outline
          ),
        DoseStatus.missed => (
            AppStrings.missed,
            Tone.error,
            Icons.cancel_outlined
          ),
      };
}

/// Progress for one day, from saved records only.
class DayProgressCard extends StatelessWidget {
  const DayProgressCard(
      {super.key, required this.counts, required this.dayLabel});
  final DoseCounts counts;
  final String dayLabel; // e.g. "today" or "on Oct 9"

  @override
  Widget build(BuildContext context) {
    if (counts.total == 0) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: AppColors.primaryLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${counts.taken} of ${counts.total} doses taken $dayLabel',
              style: textTheme.titleMedium
                  ?.copyWith(color: AppColors.primaryDark)),
          const SizedBox(height: 10),
          // The text already announces the count to screen readers.
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  value: counts.taken / counts.total,
                  minHeight: 10,
                  backgroundColor: AppColors.surface),
            ),
          ),
          if (counts.overdue + counts.missed > 0) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (counts.overdue > 0)
                StatusBadge(
                    label: '${AppStrings.overdue}: ${counts.overdue}',
                    tone: Tone.warning,
                    icon: Icons.error_outline),
              if (counts.missed > 0)
                StatusBadge(
                    label: '${AppStrings.missed}: ${counts.missed}',
                    tone: Tone.error,
                    icon: Icons.cancel_outlined),
            ]),
          ],
          if (counts.missed > 0) ...[
            const SizedBox(height: 8),
            Text(AppStrings.missedGuidance, style: textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}

/// One scheduled dose: time, medicine, status and the taken action.
class DoseCard extends StatelessWidget {
  const DoseCard({
    super.key,
    required this.medicine,
    required this.dose,
    required this.now,
    required this.busy,
    required this.onChanged,
    this.allowTaking = true,
  });
  final Medicine medicine;
  final DateTime dose;
  final DateTime now;
  final bool busy;
  final ValueChanged<bool> onChanged;

  /// False for future days: a dose cannot be confirmed in advance there.
  final bool allowTaking;

  @override
  Widget build(BuildContext context) {
    final status = DoseTracking.statusOf(medicine, dose, now);
    final taken = status == DoseStatus.taken;
    final (label, tone, icon) = status.badge;
    final textTheme = Theme.of(context).textTheme;
    final takenAt = medicine.takenTimeOf(dose);
    final details = [
      'Amount: ${medicine.qtyLabel}',
      if (medicine.instructions.isNotEmpty) medicine.instructions,
    ].join(' · ');
    final takenLine = !taken
        ? null
        : takenAt == null
            ? 'Marked taken (confirmation time not recorded)'
            : takenAt.difference(dose) > DoseTracking.missedAfter
                ? 'Marked taken late, at ${Fmt.dateTime(takenAt)}'
                : 'Marked taken at ${Fmt.dateTime(takenAt)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(Fmt.time(dose),
                  style: textTheme.titleLarge
                      ?.copyWith(color: AppColors.primaryDark)),
              StatusBadge(label: label, tone: tone, icon: icon),
            ],
          ),
          const SizedBox(height: 6),
          Text('${medicine.name} ${medicine.dose}'.trim(),
              style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(details, style: textTheme.bodyMedium),
          if (takenLine != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(takenLine, style: textTheme.bodySmall),
            ),
          if (status == DoseStatus.missed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'No confirmation was recorded. ${AppStrings.missedGuidance}',
                  style: textTheme.bodySmall),
            ),
          if (taken || allowTaking) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: taken
                  ? OutlinedButton.icon(
                      onPressed: busy ? null : () => onChanged(false),
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo: Mark as Not Taken'))
                  : FilledButton.icon(
                      onPressed: busy ? null : () => onChanged(true),
                      icon: const Icon(Icons.check),
                      label: Text(status == DoseStatus.upcoming
                          ? AppStrings.markAsTaken
                          : 'Mark as Taken (late)')),
            ),
          ],
        ]),
      ),
    );
  }
}
