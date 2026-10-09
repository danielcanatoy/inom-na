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

  /// The change point for "Today": the current minute.
  static DateTime _todayPoint(DateTime now) =>
      DateTime(now.year, now.month, now.day, now.hour, now.minute);

  /// Why new clock times cannot apply from now (today), or null if they can.
  /// Today's earlier doses (and anything already taken) stay as they were;
  /// only today's remaining doses follow the new times. Allowed only when
  /// today still ends up with exactly the prescribed number of doses and no
  /// later dose today was already marked taken.
  static String? todayBlockReason(
      Medicine saved, List<String> newTimes, DateTime now) {
    final point = _todayPoint(now);
    final today = dayStart(now);
    final tomorrow = today.add(const Duration(days: 1));
    var earlier = 0;
    for (final dose in saved.allDoses(horizon: tomorrow, from: today)) {
      if (!dose.isBefore(tomorrow)) break;
      if (dose.isBefore(point)) {
        earlier++;
      } else if (saved.isTaken(dose)) {
        return 'A later dose today is already marked taken. Undo it first, '
            'or apply the change from tomorrow.';
      }
    }
    final valid = newTimes.where(Medicine.validTime).toList();
    final later =
        valid.where((t) => !Medicine.atTime(today, t).isBefore(point)).length;
    final total = earlier + later;
    if (total != valid.length) {
      return 'Today would have $total ${total == 1 ? "dose" : "doses"} '
          'instead of ${valid.length}, so the new times start tomorrow. '
          "Today's schedule stays as it was.";
    }
    return null;
  }

  static bool canApplyToday(
          Medicine saved, List<String> newTimes, DateTime now) =>
      todayBlockReason(saved, newTimes, now) == null;

  /// When new clock times take effect: from now (today, if allowed and
  /// chosen) or from tomorrow, never earlier than the current rule's start.
  static DateTime clockEffectiveFrom(Medicine saved, DateTime now,
      {required bool today}) {
    final point =
        today ? _todayPoint(now) : dayStart(now).add(const Duration(days: 1));
    return point.isBefore(saved.start) ? saved.start : point;
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
