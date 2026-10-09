import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/reminder_plan.dart';
import 'package:inom_na/services/schedule_edit.dart';

final now = DateTime(2030, 1, 10, 10); // 10:00 AM
final tomorrow = DateTime(2030, 1, 11);

/// Synthetic medicines (SAMPLE – FOR DEMO ONLY).
Medicine twiceDaily({int? days, DateTime? start}) => Medicine(
      id: 'bid',
      name: 'Sample BID',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: 2,
      times: ['08:00', '20:00'],
      days: days,
      durationConfirmed: true,
      start: start ?? DateTime(2030, 1, 1, 7),
    );

Medicine q8h({DateTime? start}) => Medicine(
      id: 'q8h',
      name: 'Sample q8h',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.interval,
      intervalHours: 8,
      durationConfirmed: true,
      start: start ?? DateTime(2030, 1, 10, 6),
    );

Medicine withTimes(Medicine saved, List<String> times, DateTime effective) =>
    ScheduleEdit.draftOf(saved)
      ..times = times
      ..frequencyPerDay = times.length
      ..start = effective;

void main() {
  group('Editing keeps history', () {
    test('only doses from the change onwards follow the new times', () {
      final saved = twiceDaily()
        ..markTaken(DateTime(2030, 1, 9, 8))
        ..markTaken(DateTime(2030, 1, 10, 8));
      final revised = saved.withScheduleFrom(
          withTimes(saved, ['09:00', '21:00'], tomorrow), tomorrow);
      expect(
          revised.allDoses(
              horizon: DateTime(2030, 1, 11, 23, 59),
              from: DateTime(2030, 1, 10)),
          [
            DateTime(2030, 1, 10, 8),
            DateTime(2030, 1, 10, 20),
            DateTime(2030, 1, 11, 9),
            DateTime(2030, 1, 11, 21),
          ]);
      // Past doses and their taken records are untouched.
      expect(revised.id, saved.id);
      expect(revised.taken, saved.taken);
      expect(revised.isTaken(DateTime(2030, 1, 9, 8)), isTrue);
      final dueBefore = saved.allDoses(horizon: now);
      expect(revised.allDoses(horizon: now), dueBefore);
      expect(revised.allDoses(horizon: now).where(revised.isTaken).length, 2);
      expect(revised.originalStart, saved.start);
    });

    test('the saved medicine is never modified by editing a draft', () {
      final saved = twiceDaily();
      final before = saved.toJson().toString();
      final draft = ScheduleEdit.draftOf(saved)..times = ['10:00', '22:00'];
      saved.withScheduleFrom(draft..start = tomorrow, tomorrow);
      expect(saved.toJson().toString(), before);
    });

    test('dose keys stay unique across repeated edits', () {
      final saved = twiceDaily();
      final first = saved.withScheduleFrom(
          withTimes(saved, ['09:00', '21:00'], tomorrow), tomorrow);
      final second = first.withScheduleFrom(
          withTimes(first, ['07:00', '19:00'], tomorrow), tomorrow);
      final doses = second.allDoses(horizon: DateTime(2030, 1, 12, 23, 59));
      expect(doses.map(Medicine.keyOf).toSet().length, doses.length);
      // The second edit at the same boundary replaces the first edit.
      expect(second.revisions, hasLength(1));
      expect(doses.where((d) => d.day == 11).toList(),
          [DateTime(2030, 1, 11, 7), DateTime(2030, 1, 11, 19)]);
    });

    test('a finite course keeps exactly the same number of doses', () {
      final saved = twiceDaily(days: 7, start: DateTime(2030, 1, 8, 8));
      expect(saved.scheduleEnd, DateTime(2030, 1, 15, 8));
      for (final times in [
        ['09:00', '21:00'], // Later: would otherwise lose the last dose.
        ['06:00', '18:00'], // Earlier: would otherwise gain a dose.
      ]) {
        final draft = withTimes(saved, times, tomorrow);
        draft.end = ScheduleEdit.preservedEnd(saved, draft, tomorrow);
        final revised = saved.withScheduleFrom(draft, tomorrow);
        expect(saved.totalDoses, 14);
        expect(revised.totalDoses, 14, reason: times.join(','));
        final last = revised.allDoses(horizon: DateTime(2030, 2, 1)).last;
        expect(last, Medicine.atTime(DateTime(2030, 1, 14), times.last));
      }
    });

    test('history survives JSON persistence', () {
      final saved = twiceDaily()..markTaken(DateTime(2030, 1, 10, 8));
      final revised = saved.withScheduleFrom(
          withTimes(saved, ['09:00', '21:00'], tomorrow), tomorrow);
      final restored = Medicine.fromJson(revised.toJson());
      final horizon = DateTime(2030, 1, 12);
      expect(restored.allDoses(horizon: horizon),
          revised.allDoses(horizon: horizon));
      expect(restored.taken, revised.taken);
      expect(restored.revisions.single.until, tomorrow);
    });

    test('legacy records keep their original past doses after an edit', () {
      // Phase 1 schema: no schemaVersion, started 10 minutes after 08:00.
      final legacy = Medicine.fromJson({
        'id': 'old',
        'name': 'Legacy',
        'dose': '500mg',
        'times': ['08:00', '20:00'],
        'days': 30,
        'start': DateTime(2030, 1, 1, 8, 10).toIso8601String(),
        'taken': ['2030-01-01 08:00'],
      });
      expect(legacy.legacy, isTrue);
      final draft = withTimes(legacy, ['09:00', '21:00'], tomorrow);
      draft.end = ScheduleEdit.preservedEnd(legacy, draft, tomorrow);
      final revised = legacy.withScheduleFrom(draft, tomorrow);
      expect(revised.allDoses(horizon: now), legacy.allDoses(horizon: now));
      expect(revised.allDoses(horizon: now).first, DateTime(2030, 1, 1, 8));
      expect(revised.isTaken(DateTime(2030, 1, 1, 8)), isTrue);
      expect(legacy.totalDoses, 60);
      expect(revised.totalDoses, 60);
      // Older records without the new fields still load.
      expect(Medicine.fromJson(legacy.toJson()).revisions, isEmpty);
      expect(Medicine.fromJson(legacy.toJson()).routineLink, isNull);
    });

    test('a medicine that has not started is replaced without history', () {
      final future = twiceDaily(start: DateTime(2030, 1, 15, 7));
      final draft = withTimes(future, ['09:00', '21:00'], future.start);
      final revised = future.withScheduleFrom(draft, future.start);
      expect(revised.revisions, isEmpty);
      expect(revised.allDoses(horizon: DateTime(2030, 1, 15, 23)),
          [DateTime(2030, 1, 15, 9), DateTime(2030, 1, 15, 21)]);
    });

    test('corrupt history refuses to load rather than inventing a schedule',
        () {
      final json = twiceDaily().toJson()
        ..['revisions'] = [
          {'until': 'not a date', 'rule': {}}
        ];
      expect(() => Medicine.fromJson(json), throwsFormatException);
    });
  });

  group('When changes take effect', () {
    test('today is allowed only before any of today\'s doses', () {
      final saved = twiceDaily();
      // 08:00 already passed at 10:00.
      expect(
          ScheduleEdit.canApplyToday(saved, ['11:00', '21:00'], now), isFalse);
      final early = DateTime(2030, 1, 10, 7);
      expect(
          ScheduleEdit.canApplyToday(saved, ['09:00', '21:00'], early), isTrue);
      // A new time that has already passed today would be missed.
      expect(ScheduleEdit.canApplyToday(saved, ['06:30', '21:00'], early),
          isFalse);
      // A dose marked taken early also blocks today.
      saved.markTaken(DateTime(2030, 1, 10, 8));
      expect(ScheduleEdit.canApplyToday(saved, ['09:00', '21:00'], early),
          isFalse);
    });

    test('a change cannot start before a dose already marked taken', () {
      final saved = twiceDaily()..markTaken(DateTime(2030, 1, 10, 20));
      final draft = withTimes(saved, ['09:00', '21:00'], DateTime(2030, 1, 10));
      final errors =
          ScheduleEdit.errors(saved, draft, DateTime(2030, 1, 10), now);
      expect(errors.join(' '), contains('already marked taken'));
    });

    test('invalid and duplicate times are rejected', () {
      final saved = twiceDaily();
      expect(
          ScheduleEdit.errors(saved,
                  withTimes(saved, ['09:00', '09:00'], tomorrow), tomorrow, now)
              .join(' '),
          contains('same time cannot be added twice'));
      final wrongCount = withTimes(saved, ['09:00'], tomorrow)
        ..frequencyPerDay = 2;
      expect(ScheduleEdit.errors(saved, wrongCount, tomorrow, now), isNotEmpty);
    });

    test('an end date before the change is rejected', () {
      final saved = twiceDaily(days: 3, start: DateTime(2030, 1, 9, 7));
      final draft = withTimes(saved, ['09:00', '21:00'], tomorrow)
        ..end = DateTime(2030, 1, 10, 22);
      expect(ScheduleEdit.errors(saved, draft, tomorrow, now), isNotEmpty);
    });
  });

  group('Fixed intervals', () {
    test('a new first dose keeps exact 8-hour spacing, including overnight',
        () {
      final saved = q8h(); // 06:00, 14:00, 22:00 ...
      final anchor = DateTime(2030, 1, 10, 15); // Replaces the 14:00 dose.
      final draft = ScheduleEdit.draftOf(saved)..start = anchor;
      expect(ScheduleEdit.errors(saved, draft, now, now), isEmpty);
      final revised = saved.withScheduleFrom(draft, now);
      final doses = revised.allDoses(
          horizon: DateTime(2030, 1, 11, 23, 59), from: DateTime(2030, 1, 10));
      expect(doses.first, DateTime(2030, 1, 10, 6)); // Kept from history.
      final upcoming = doses.skip(1).toList();
      expect(upcoming.first, anchor);
      for (var i = 1; i < upcoming.length; i++) {
        expect(
            upcoming[i].difference(upcoming[i - 1]), const Duration(hours: 8));
      }
      expect(upcoming, contains(DateTime(2030, 1, 10, 23)));
      expect(upcoming, contains(DateTime(2030, 1, 11, 7)));
      expect(upcoming, isNot(contains(DateTime(2030, 1, 10, 14))));
    });

    test('a first dose too soon after the previous dose is blocked', () {
      final saved = q8h();
      final anchor = DateTime(2030, 1, 10, 12); // Only 6 h after 06:00.
      final draft = ScheduleEdit.draftOf(saved)..start = anchor;
      expect(ScheduleEdit.errors(saved, draft, now, now).join(' '),
          contains('at least 8 hours'));
    });

    test('q6h correction keeps exact 6-hour spacing', () {
      final saved = q8h();
      final anchor = DateTime(2030, 1, 10, 14);
      final draft = ScheduleEdit.draftOf(saved)
        ..intervalHours = 6
        ..start = anchor;
      expect(ScheduleEdit.errors(saved, draft, now, now), isEmpty);
      final doses = saved
          .withScheduleFrom(draft, now)
          .allDoses(horizon: DateTime(2030, 1, 11, 12), from: anchor);
      expect(doses, [
        DateTime(2030, 1, 10, 14),
        DateTime(2030, 1, 10, 20),
        DateTime(2030, 1, 11, 2),
        DateTime(2030, 1, 11, 8),
      ]);
    });

    test('the default next dose keeps the current spacing', () {
      expect(ScheduleEdit.nextDose(q8h(), now), DateTime(2030, 1, 10, 14));
    });
  });

  group('Reminder plan after an edit', () {
    test('old times become one-off reminders and stop at the change', () {
      final saved = twiceDaily()..markTaken(DateTime(2030, 1, 10, 8));
      final revised = saved.withScheduleFrom(
          withTimes(saved, ['09:00', '21:00'], tomorrow), tomorrow);
      final plan = ReminderPlan.build([revised], now);
      expect(plan.error, isNull);
      final keys = plan.reminders.map((r) => r.key).toList();
      expect(keys, contains('dose:bid|2030-01-10 20:00'));
      expect(keys, containsAll(['daily:bid:09:00', 'daily:bid:21:00']));
      expect(
          keys.where((k) =>
              k.startsWith('daily:bid:08') || k.startsWith('daily:bid:20')),
          isEmpty);
      final series = plan.reminders.where((r) => r.repeatDaily).toList();
      expect(series.map((r) => r.when),
          [DateTime(2030, 1, 11, 9), DateTime(2030, 1, 11, 21)]);
      final oneOff =
          plan.reminders.singleWhere((r) => r.key.startsWith('dose:'));
      expect(oneOff.repeatDaily, isFalse);
    });
  });
}
