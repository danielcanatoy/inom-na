import '../models/medicine.dart';
import '../models/routine.dart';

class RoutineSuggestion {
  const RoutineSuggestion(this.times, this.problems);
  final List<String> times;

  /// Reasons the suggestion cannot be used yet. Empty means usable.
  final List<String> problems;
  bool get usable => problems.isEmpty && times.isNotEmpty;
}

/// Proposed reminder-time change for one saved medicine after a routine edit.
class RoutineProposal {
  const RoutineProposal(this.medicine, this.newTimes);
  final Medicine medicine;
  final List<String> newTimes;
}

class RoutineScheduler {
  /// Why routine suggestions do not apply, or null if they may be offered.
  /// Only verified general daily frequencies are eligible.
  static String? ineligibleReason(Medicine m) => switch (m.scheduleKind) {
        ScheduleKind.daily => (m.frequencyPerDay ?? 0) <= 0
            ? 'Enter how many times a day first.'
            : null,
        ScheduleKind.explicit =>
          'Prescribed Time: the times written on the prescription are kept.',
        ScheduleKind.interval =>
          'Fixed Interval: doses stay exactly ${m.intervalHours ?? "?"} hours '
              'apart, so routine times are not used.',
        ScheduleKind.prn =>
          'As needed (PRN): no scheduled reminders are created.',
        ScheduleKind.unknown =>
          'The schedule is unclear. Choose the schedule type from your '
              'prescription first.',
      };

  /// Suggested mode from the written directions. A suggestion only — the
  /// user reviews it before any time is applied.
  static RoutineMode suggestedMode(Medicine m,
      {required bool bedtime,
      required bool beforeMeals,
      required bool afterMeals}) {
    final perDay = m.frequencyPerDay ?? 0;
    if (bedtime && perDay == 1) return RoutineMode.bedtime;
    if (beforeMeals && !afterMeals && perDay <= 3) {
      return RoutineMode.beforeMeals;
    }
    if (afterMeals && !beforeMeals && perDay <= 3) {
      return RoutineMode.afterMeals;
    }
    return RoutineMode.spread;
  }

  /// Initial meal selection for meal-linked schedules; shown for review.
  static List<RoutineEvent> defaultMeals(int perDay) => switch (perDay) {
        1 => [RoutineEvent.breakfast],
        2 => [RoutineEvent.breakfast, RoutineEvent.dinner],
        3 => [...mealEvents],
        _ => [],
      };

  static RoutineSuggestion suggest({
    required int perDay,
    required RoutineLink link,
    required DailyRoutine routine,
  }) {
    if (routine.validationErrors().isNotEmpty) {
      return const RoutineSuggestion(
          [], ['Your daily routine needs to be fixed first.']);
    }
    if (perDay <= 0 || perDay > 24) {
      return const RoutineSuggestion([], ['Enter how many times a day first.']);
    }
    final wake = DailyRoutine.minutesOf(routine[RoutineEvent.wake])!;
    final minutes = <int>[];
    switch (link.mode) {
      case RoutineMode.spread:
        // First dose at wake-up, last at bedtime, others evenly in between.
        // A convenience only; it does not create spacing requirements.
        if (perDay == 1) {
          minutes.add(wake);
        } else {
          final awake = routine.awakeMinutes;
          for (var i = 0; i < perDay; i++) {
            final offset = (awake * i / (perDay - 1) / 5).round() * 5;
            minutes.add(wake + offset);
          }
        }
      case RoutineMode.bedtime:
        if (perDay != 1) {
          return const RoutineSuggestion(
              [], ['"At bedtime" can only be used for once-a-day medicines.']);
        }
        minutes.add(DailyRoutine.minutesOf(routine[RoutineEvent.bedtime])!);
      case RoutineMode.beforeMeals:
      case RoutineMode.afterMeals:
        final problems = <String>[];
        if (perDay > 3) {
          problems.add('$perDay times a day cannot be matched to 3 meals. '
              'Set the times yourself or ask your pharmacist.');
        } else if (link.meals.length != perDay ||
            link.meals.toSet().length != link.meals.length) {
          problems.add('Choose $perDay '
              '${perDay == 1 ? "meal" : "different meals"}.');
        }
        final offset = link.offsetMinutes;
        if (offset == null) {
          problems.add('Enter how many minutes '
              '${link.mode == RoutineMode.beforeMeals ? "before" : "after"} '
              'the meal, as instructed by your doctor or pharmacist.');
        } else if (offset < 0 || offset > 180) {
          problems.add('Minutes from the meal must be between 0 and 180.');
        }
        if (problems.isNotEmpty) return RoutineSuggestion(const [], problems);
        for (final meal in link.meals) {
          final mealTime = DailyRoutine.minutesOf(routine[meal])!;
          minutes.add(link.mode == RoutineMode.beforeMeals
              ? mealTime - offset!
              : mealTime + offset!);
        }
    }
    final times = minutes.map(DailyRoutine.format).toList()..sort();
    if (times.toSet().length != times.length) {
      return RoutineSuggestion(times, [
        'Two suggested times are the same. Adjust your routine '
            'or set the times yourself.'
      ]);
    }
    return RoutineSuggestion(times, const []);
  }

  /// Routine-linked daily schedules whose suggested times change under
  /// [routine]. Prescribed times, fixed intervals, PRN, customized times and
  /// finished schedules are never included.
  static List<RoutineProposal> proposals(
      List<Medicine> medicines, DailyRoutine routine, DateTime now) {
    final result = <RoutineProposal>[];
    for (final m in medicines) {
      final link = m.routineLink;
      if (link == null ||
          m.scheduleKind != ScheduleKind.daily ||
          m.isFinished ||
          m.scheduleErrors().isNotEmpty) {
        continue;
      }
      final suggestion =
          suggest(perDay: m.frequencyPerDay ?? 0, link: link, routine: routine);
      if (!suggestion.usable) continue;
      final current = [...m.times]..sort();
      if (current.join(',') != suggestion.times.join(',')) {
        result.add(RoutineProposal(m, suggestion.times));
      }
    }
    return result;
  }
}
