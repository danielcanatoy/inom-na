import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/models/routine.dart';
import 'package:inom_na/services/routine_schedule.dart';
import 'package:inom_na/services/schedule_edit.dart';
import 'package:inom_na/services/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

DailyRoutine routine(String wake, String breakfast, String lunch, String dinner,
        String bedtime) =>
    DailyRoutine({
      RoutineEvent.wake: wake,
      RoutineEvent.breakfast: breakfast,
      RoutineEvent.lunch: lunch,
      RoutineEvent.dinner: dinner,
      RoutineEvent.bedtime: bedtime,
    });

final standard = routine('06:00', '07:00', '12:00', '18:00', '21:00');

/// Synthetic daily medicine (SAMPLE – FOR DEMO ONLY).
Medicine daily(String id, List<String> times,
        {RoutineLink? link,
        ScheduleKind kind = ScheduleKind.daily,
        DateTime? start}) =>
    Medicine(
      id: id,
      name: 'Sample $id',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: kind,
      frequencyPerDay: times.length,
      times: times,
      durationConfirmed: true,
      start: start ?? DateTime(2030, 1, 1),
      routineLink: link,
    );

List<String> suggest(int perDay, RoutineLink link, [DailyRoutine? r]) {
  final result = RoutineScheduler.suggest(
      perDay: perDay, link: link, routine: r ?? standard);
  expect(result.problems, isEmpty, reason: result.problems.join('; '));
  return result.times;
}

void main() {
  group('Daily routine validation', () {
    test('standard and picker-default routines are valid', () {
      expect(standard.validationErrors(), isEmpty);
      expect(DailyRoutine.pickerDefaults.validationErrors(), isEmpty);
    });

    test('a bedtime after midnight is valid', () {
      final late = routine('07:00', '08:00', '13:00', '20:00', '00:30');
      expect(late.validationErrors(), isEmpty);
      expect(late.awakeMinutes, 17 * 60 + 30);
    });

    test('a night-shift day crossing midnight is valid', () {
      final night = routine('18:00', '19:00', '00:00', '05:00', '10:00');
      expect(night.validationErrors(), isEmpty);
      expect(night.awakeMinutes, 16 * 60);
    });

    test('out-of-order, duplicate, invalid and too-short days are rejected',
        () {
      expect(
          routine('06:00', '12:00', '07:00', '18:00', '21:00')
              .validationErrors()
              .join(' '),
          contains('Lunch should come after breakfast'));
      expect(
          routine('06:00', '07:00', '07:00', '18:00', '21:00')
              .validationErrors()
              .join(' '),
          contains('must be different'));
      expect(
          routine('06:00', '25:00', '12:00', '18:00', '21:00')
              .validationErrors(),
          isNotEmpty);
      expect(
          routine('06:00', '06:30', '07:00', '08:00', '09:00')
              .validationErrors()
              .join(' '),
          contains('at least 4 hours'));
    });
  });

  group('Routine storage', () {
    test('nothing is treated as saved until the user saves', () async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
      expect(Store.routine, isNull);
    });

    test('saved routine survives an app restart', () async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
      final mine = routine('05:30', '06:15', '11:45', '17:30', '22:15');
      await Store.saveRoutine(mine);
      await Store.init(); // Simulated restart.
      expect(Store.routine, mine);
    });

    test('invalid routine is refused and the saved one is kept', () async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
      await Store.saveRoutine(standard);
      await expectLater(
          Store.saveRoutine(
              routine('06:00', '06:00', '12:00', '18:00', '21:00')),
          throwsFormatException);
      expect(Store.routine, standard);
    });

    test('corrupt routine data reads as not set and leaves medicines alone',
        () async {
      final med = daily('m', ['08:00']);
      SharedPreferences.setMockInitialValues({
        'daily_routine_v1': '{broken',
        'meds': jsonEncode([med.toJson()]),
      });
      await Store.init();
      expect(Store.routine, isNull);
      expect(Store.meds().single.id, 'm');
      expect(Store.loadError, isNull);
    });
  });

  group('Routine-based suggestions', () {
    const spread = RoutineLink(mode: RoutineMode.spread);

    test('once a day uses wake-up time', () {
      expect(suggest(1, spread), ['06:00']);
    });

    test('BID/TID/QID spread from wake-up to bedtime', () {
      expect(suggest(2, spread), ['06:00', '21:00']);
      expect(suggest(3, spread), ['06:00', '13:30', '21:00']);
      expect(suggest(4, spread), ['06:00', '11:00', '16:00', '21:00']);
    });

    test('spread suggestions wrap correctly across midnight', () {
      final night = routine('18:00', '19:00', '00:00', '05:00', '10:00');
      expect(suggest(3, spread, night), ['02:00', '10:00', '18:00']);
    });

    test('verified bedtime uses the saved bedtime, once a day only', () {
      expect(
          suggest(1, const RoutineLink(mode: RoutineMode.bedtime)), ['21:00']);
      final twice = RoutineScheduler.suggest(
          perDay: 2,
          link: const RoutineLink(mode: RoutineMode.bedtime),
          routine: standard);
      expect(twice.usable, isFalse);
    });

    test('meal-linked times use the entered offset exactly', () {
      expect(
          suggest(
              3,
              const RoutineLink(
                  mode: RoutineMode.beforeMeals,
                  meals: mealEvents,
                  offsetMinutes: 30)),
          ['06:30', '11:30', '17:30']);
      expect(
          suggest(
              2,
              const RoutineLink(
                  mode: RoutineMode.afterMeals,
                  meals: [RoutineEvent.breakfast, RoutineEvent.dinner],
                  offsetMinutes: 0)),
          ['07:00', '18:00']);
    });

    test('a before-meal offset can cross midnight', () {
      final early = routine('23:00', '00:10', '06:00', '12:00', '16:00');
      expect(
          suggest(
              1,
              const RoutineLink(
                  mode: RoutineMode.beforeMeals,
                  meals: [RoutineEvent.breakfast],
                  offsetMinutes: 30),
              early),
          ['23:40']);
    });

    test('no meal offset is ever assumed', () {
      final result = RoutineScheduler.suggest(
          perDay: 3,
          link: const RoutineLink(
              mode: RoutineMode.beforeMeals, meals: mealEvents),
          routine: standard);
      expect(result.usable, isFalse);
      expect(result.times, isEmpty);
      expect(result.problems.join(' '), contains('minutes'));
    });

    test('meal count must match the prescribed frequency', () {
      final wrongCount = RoutineScheduler.suggest(
          perDay: 2,
          link: const RoutineLink(
              mode: RoutineMode.afterMeals,
              meals: [RoutineEvent.lunch],
              offsetMinutes: 10),
          routine: standard);
      expect(wrongCount.usable, isFalse);
      final four = RoutineScheduler.suggest(
          perDay: 4,
          link: const RoutineLink(
              mode: RoutineMode.afterMeals,
              meals: mealEvents,
              offsetMinutes: 10),
          routine: standard);
      expect(four.usable, isFalse);
      expect(four.problems.join(' '), contains('cannot be matched'));
    });

    test('an invalid routine blocks suggestions instead of guessing', () {
      final same = RoutineScheduler.suggest(
          perDay: 2,
          link: const RoutineLink(mode: RoutineMode.spread),
          routine: routine('06:00', '07:00', '12:00', '18:00', '06:00'));
      expect(same.usable, isFalse);
      expect(same.times, isEmpty);
    });

    test('only verified daily frequencies are eligible', () {
      expect(RoutineScheduler.ineligibleReason(daily('a', ['08:00'])), isNull);
      for (final kind in [
        ScheduleKind.explicit,
        ScheduleKind.interval,
        ScheduleKind.prn,
        ScheduleKind.unknown,
      ]) {
        expect(
            RoutineScheduler.ineligibleReason(
                daily('a', ['08:00'], kind: kind)),
            isNotNull,
            reason: kind.name);
      }
    });

    test('written directions only pre-select a mode', () {
      final m = daily('a', ['08:00']);
      expect(
          RoutineScheduler.suggestedMode(m,
              bedtime: true, beforeMeals: false, afterMeals: false),
          RoutineMode.bedtime);
      final tid = daily('b', ['08:00', '13:00', '18:00']);
      expect(
          RoutineScheduler.suggestedMode(tid,
              bedtime: false, beforeMeals: true, afterMeals: false),
          RoutineMode.beforeMeals);
      expect(
          RoutineScheduler.suggestedMode(tid,
              bedtime: false, beforeMeals: true, afterMeals: true),
          RoutineMode.spread);
    });
  });

  group('Routine change proposals', () {
    final now = DateTime(2030, 1, 10, 10);
    const spread = RoutineLink(mode: RoutineMode.spread);
    final later = routine('07:00', '08:00', '12:30', '18:30', '22:00');

    test('only routine-linked daily schedules are proposed', () {
      final linked = daily('linked', ['06:00', '21:00'], link: spread);
      final custom = daily('custom', ['06:00', '21:00']);
      final prescribed = daily('explicit', ['06:00', '21:00'],
          kind: ScheduleKind.explicit, link: spread);
      final interval = Medicine(
        id: 'q8h',
        name: 'Interval',
        dose: '500mg',
        qtyPerIntake: 1,
        scheduleKind: ScheduleKind.interval,
        intervalHours: 8,
        durationConfirmed: true,
        start: DateTime(2030, 1, 1, 6),
      );
      final unchanged = daily('same', ['06:00'], link: spread);
      final proposals = RoutineScheduler.proposals(
          [linked, custom, prescribed, interval, unchanged], later, now);
      expect(proposals.map((p) => p.medicine.id), ['linked', 'same']);
      expect(proposals.first.newTimes, ['07:00', '22:00']);
      expect(proposals.last.newTimes, ['07:00']);
    });

    test('applying a proposal changes only future doses and keeps history', () {
      final med = daily('linked', ['06:00', '21:00'], link: spread);
      med.markTaken(DateTime(2030, 1, 10, 6));
      final updated = ScheduleEdit.applyTimes(med, ['07:00', '22:00'], now);
      expect(updated.id, med.id);
      expect(updated.taken, med.taken);
      expect(updated.routineLink, spread);
      // Today's 6:00 AM dose (taken) stays; today's remaining dose moves to
      // 10:00 PM, so today still has exactly two doses.
      final doses = updated.allDoses(
          horizon: DateTime(2030, 1, 11, 23, 59), from: DateTime(2030, 1, 10));
      expect(doses, [
        DateTime(2030, 1, 10, 6),
        DateTime(2030, 1, 10, 22),
        DateTime(2030, 1, 11, 7),
        DateTime(2030, 1, 11, 22),
      ]);
      expect(updated.isTaken(DateTime(2030, 1, 10, 6)), isTrue);
      expect(med.times, ['06:00', '21:00']); // Original object unchanged.
    });
  });
}
