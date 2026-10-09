import '../models/medicine.dart';
import '../models/routine.dart';

/// Rules for changing a saved medicine's schedule. Only future doses change;
/// past doses and taken records stay exactly as they were.
class ScheduleEdit {
  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// An editable copy of the current rule. A day-count course is converted to
  /// its absolute end so moving the start of the new rule never extends it.
  /// Editing this copy never changes [saved].
  static Medicine draftOf(Medicine saved) {
    final draft = saved.copy()
      ..revisions = []
      ..reviewNotes = [];
    final end = saved.scheduleEnd;
    if (!saved.isMaintenance && end != null) {
      draft
        ..days = null
        ..end = end;
    }
    draft.legacy = false;
    return draft;
  }

  /// Whether the course has doses before [now] (or taken records), so edits
  /// must keep a history segment rather than replace the schedule.
  static bool hasStarted(Medicine saved, DateTime now) =>
      saved.taken.isNotEmpty ||
      saved.allDoses(horizon: now).any((d) => d.isBefore(now));

  /// New clock times may apply from today only if none of today's doses,
  /// old or new, has already passed or been marked taken. Otherwise one day
  /// could get extra or missing doses, so the change starts tomorrow.
  static bool canApplyToday(
      Medicine saved, List<String> newTimes, DateTime now) {
    final today = dayStart(now);
    final tomorrow = today.add(const Duration(days: 1));
    for (final dose in saved.allDoses(horizon: tomorrow, from: today)) {
      if (!dose.isBefore(tomorrow)) break;
      if (dose.isBefore(now) || saved.isTaken(dose)) return false;
    }
    return newTimes.every((time) =>
        !Medicine.validTime(time) ||
        !Medicine.atTime(today, time).isBefore(now));
  }

  /// When new clock times take effect: today (if allowed and chosen) or
  /// tomorrow, never earlier than the current rule's own start.
  static DateTime clockEffectiveFrom(Medicine saved, DateTime now,
      {required bool today}) {
    final day = dayStart(now).add(Duration(days: today ? 0 : 1));
    return day.isBefore(saved.start) ? saved.start : day;
  }

  /// The next dose of the current schedule after [now]; the default first
  /// dose when an interval schedule is edited (keeps the same spacing).
  static DateTime? nextDose(Medicine saved, DateTime now) {
    final doses = saved.allDoses(
        horizon: now.add(const Duration(days: 8)), from: now, limit: 2);
    for (final dose in doses) {
      if (!dose.isBefore(now)) return dose;
    }
    return null;
  }

  /// Problems that block saving [next] from [effectiveFrom].
  static List<String> errors(
      Medicine saved, Medicine next, DateTime effectiveFrom, DateTime now) {
    final errors = [...next.validationErrors()];
    if (effectiveFrom.isBefore(dayStart(now))) {
      errors.add('Changes cannot start in the past.');
    }
    final isInterval = next.scheduleKind == ScheduleKind.interval;
    if (!isInterval && next.start.isBefore(effectiveFrom)) {
      errors.add('The new schedule cannot start before the change takes '
          'effect.');
    }
    final takenKey = Medicine.keyOf(effectiveFrom);
    if (saved.taken.any((key) => key.compareTo(takenKey) >= 0)) {
      errors.add('A dose at or after this time is already marked taken. '
          'Choose a later time, or undo that dose first.');
    }
    if (isInterval && next.intervalHours != null && next.intervalHours! > 0) {
      if (next.start.isBefore(effectiveFrom) || next.start.isBefore(now)) {
        errors.add('Choose a first dose time that is not in the past.');
      }
      // Doses before the change are history; the new first dose must keep
      // the full interval after the last of them.
      final earlier = saved
          .allDoses(horizon: effectiveFrom)
          .where((d) => d.isBefore(effectiveFrom))
          .toList();
      if (earlier.isNotEmpty) {
        final gap = next.start.difference(earlier.last);
        if (gap < Duration(hours: next.intervalHours!)) {
          errors.add('The first new dose must be at least '
              '${next.intervalHours} hours after the previous dose. '
              'Choose a later time.');
        }
      }
    }
    return errors;
  }

  /// For a finite course, the end that keeps the same number of remaining
  /// doses under [next], so moving reminder times or an interval start never
  /// shortens or extends the prescribed course.
  static DateTime? preservedEnd(
      Medicine saved, Medicine next, DateTime effectiveFrom) {
    final end = saved.scheduleEnd;
    if (end == null || saved.isPrn || next.isPrn) return next.end;
    final remaining = saved
        .allDoses(horizon: end, from: effectiveFrom)
        .where((d) => d.isBefore(end) && !d.isBefore(effectiveFrom))
        .length;
    if (remaining == 0) return next.end;
    final open = next.copy()
      ..revisions = []
      ..days = null
      ..end = null
      ..durationConfirmed = true;
    final doses = open.allDoses(
        horizon: end.add(const Duration(days: 3650)),
        from: effectiveFrom,
        limit: remaining);
    if (doses.length < remaining) return next.end;
    return doses.last.add(const Duration(minutes: 1));
  }

  /// Applies proposed routine times to a routine-linked daily medicine from
  /// the earliest safe day. Returns the revised medicine (history kept).
  static Medicine applyTimes(Medicine saved, List<String> times, DateTime now,
      {RoutineLink? link}) {
    final effective =
        clockEffectiveFrom(saved, now, today: canApplyToday(saved, times, now));
    final draft = draftOf(saved)
      ..times = [...times]
      ..frequencyPerDay = times.length
      ..routineLink = link ?? saved.routineLink
      ..start = effective;
    draft.end = preservedEnd(saved, draft, effective);
    return saved.withScheduleFrom(draft, effective);
  }
}
