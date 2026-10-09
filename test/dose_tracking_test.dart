import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/dose_status.dart';
import 'package:inom_na/services/schedule_edit.dart';

/// Synthetic medicines (SAMPLE – FOR DEMO ONLY).
Medicine daily(String id, List<String> times,
        {ScheduleKind kind = ScheduleKind.daily, int? days}) =>
    Medicine(
      id: id,
      name: 'Sample $id',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: kind,
      frequencyPerDay: times.length,
      times: times,
      days: days,
      durationConfirmed: true,
      start: DateTime(2030, 1, 1),
    );

final dose = DateTime(2030, 1, 10, 8);

void main() {
  group('Dose status', () {
    final m = daily('a', ['08:00']);

    test('upcoming before, overdue after, missed from two hours', () {
      expect(DoseTracking.statusOf(m, dose, DateTime(2030, 1, 10, 7, 59)),
          DoseStatus.upcoming);
      expect(DoseTracking.statusOf(m, dose, DateTime(2030, 1, 10, 8)),
          DoseStatus.overdue);
      expect(DoseTracking.statusOf(m, dose, DateTime(2030, 1, 10, 9, 59)),
          DoseStatus.overdue);
      expect(DoseTracking.statusOf(m, dose, DateTime(2030, 1, 10, 10)),
          DoseStatus.missed);
    });

    test('taken always takes precedence over overdue and missed', () {
      final med = daily('a', ['08:00'])..markTaken(dose);
      for (final now in [
        DateTime(2030, 1, 10, 7),
        DateTime(2030, 1, 10, 8, 30),
        DateTime(2030, 1, 12),
      ]) {
        expect(DoseTracking.statusOf(med, dose, now), DoseStatus.taken);
      }
    });

    test('statuses cross midnight correctly', () {
      final late = daily('n', ['23:30']);
      final night = DateTime(2030, 1, 10, 23, 30);
      expect(DoseTracking.statusOf(late, night, DateTime(2030, 1, 11, 0, 10)),
          DoseStatus.overdue);
      expect(DoseTracking.statusOf(late, night, DateTime(2030, 1, 11, 1, 30)),
          DoseStatus.missed);
      // The dose belongs to the day it was scheduled, not the next day.
      expect(
          DoseTracking.dosesOn([late], DateTime(2030, 1, 10)).single.$2, night);
      expect(DoseTracking.dosesOn([late], DateTime(2030, 1, 11)).single.$2,
          DateTime(2030, 1, 11, 23, 30));
    });
  });

  group('Intake history', () {
    test('a late confirmation keeps the scheduled time and records when', () {
      final m = daily('a', ['08:00']);
      final confirmed = DateTime(2030, 1, 10, 11, 15);
      expect(m.markTaken(dose, at: confirmed), isTrue);
      expect(m.isTaken(dose), isTrue);
      expect(m.takenTimeOf(dose), confirmed);
      expect(m.taken, ['2030-01-10 08:00']); // Scheduled identity unchanged.
    });

    test('repeated confirmations are idempotent and keep the first time', () {
      final m = daily('a', ['08:00']);
      m.markTaken(dose, at: DateTime(2030, 1, 10, 8, 5));
      expect(m.markTaken(dose, at: DateTime(2030, 1, 10, 9)), isFalse);
      expect(m.taken, hasLength(1));
      expect(m.takenTimeOf(dose), DateTime(2030, 1, 10, 8, 5));
    });

    test('undo removes only the selected dose and its timestamp', () {
      final m = daily('a', ['08:00', '20:00']);
      final evening = DateTime(2030, 1, 10, 20);
      m.markTaken(dose, at: DateTime(2030, 1, 10, 8, 1));
      m.markTaken(evening, at: DateTime(2030, 1, 10, 20, 2));
      expect(m.markTaken(dose, value: false), isTrue);
      expect(m.isTaken(dose), isFalse);
      expect(m.takenTimeOf(dose), isNull);
      expect(m.takenTimeOf(evening), DateTime(2030, 1, 10, 20, 2));
    });

    test('legacy taken records keep an unknown intake time', () {
      final legacy = Medicine.fromJson({
        'id': 'old',
        'name': 'Legacy',
        'dose': '500mg',
        'times': ['08:00'],
        'start': DateTime(2030, 1, 1, 8).toIso8601String(),
        'taken': ['2030-01-05 08:00'],
      });
      expect(legacy.isTaken(DateTime(2030, 1, 5, 8)), isTrue);
      expect(legacy.takenTimeOf(DateTime(2030, 1, 5, 8)), isNull);
      expect(legacy.toJson().containsKey('takenAt'), isFalse);
    });

    test('intake history survives persistence and ignores orphan entries', () {
      final m = daily('a', ['08:00'])
        ..markTaken(dose, at: DateTime(2030, 1, 10, 8, 3));
      final json = m.toJson()
        ..['takenAt'] = {
          ...(m.toJson()['takenAt'] as Map),
          '2030-01-09 08:00': DateTime(2030, 1, 9, 8).toIso8601String(),
        };
      final restored = Medicine.fromJson(json);
      expect(restored.takenTimeOf(dose), DateTime(2030, 1, 10, 8, 3));
      // A timestamp without a matching taken record is not resurrected.
      expect(restored.isTaken(DateTime(2030, 1, 9, 8)), isFalse);
      expect(restored.takenAt, hasLength(1));
      expect(() => Medicine.fromJson(m.toJson()..['takenAt'] = 'bad'),
          throwsFormatException);
    });

    test('schedule edits keep intake times and dose identities', () {
      final m = daily('a', ['08:00', '20:00'])
        ..markTaken(dose, at: DateTime(2030, 1, 10, 8, 4));
      final tomorrow = DateTime(2030, 1, 11);
      final draft = ScheduleEdit.draftOf(m)
        ..times = ['09:00', '21:00']
        ..start = tomorrow;
      final revised = m.withScheduleFrom(draft, tomorrow);
      expect(revised.takenTimeOf(dose), DateTime(2030, 1, 10, 8, 4));
      expect(DoseTracking.statusOf(revised, dose, DateTime(2030, 1, 12)),
          DoseStatus.taken);
    });
  });

  group('Progress', () {
    final now = DateTime(2030, 1, 10, 13); // 1:00 PM

    test('daily totals count taken, overdue, missed and upcoming', () {
      final a = daily('a', ['08:00', '12:30', '20:00'])
        ..markTaken(DateTime(2030, 1, 10, 8));
      final b = daily('b', ['09:00']); // Missed (4 h, unconfirmed).
      final counts = DoseTracking.countDay([a, b], DateTime(2030, 1, 10), now);
      expect(counts.total, 4);
      expect(counts.taken, 1);
      expect(counts.overdue, 1); // 12:30 PM, 30 minutes ago.
      expect(counts.missed, 1);
      expect(counts.upcoming, 1);
    });

    test('PRN medicines are excluded from the fixed-dose denominator', () {
      final prn = daily('p', [], kind: ScheduleKind.prn);
      final a = daily('a', ['08:00']);
      expect(
          DoseTracking.countDay([a, prn], DateTime(2030, 1, 10), now).total, 1);
    });

    test('past and future days, and before/after a course', () {
      final course = daily('c', ['08:00'], days: 3)
        ..start = DateTime(2030, 1, 10, 7);
      expect(DoseTracking.dosesOn([course], DateTime(2030, 1, 9)), isEmpty);
      expect(
          DoseTracking.dosesOn([course], DateTime(2030, 1, 12)), hasLength(1));
      expect(DoseTracking.dosesOn([course], DateTime(2030, 1, 13)), isEmpty);
      final future =
          DoseTracking.countDay([course], DateTime(2030, 1, 12), now);
      expect(future.upcoming, 1);
      expect(future.missed, 0);
    });

    test('per-medication counts only include doses already due', () {
      final a = daily('a', ['08:00'])
        ..start = DateTime(2030, 1, 8, 7)
        ..markTaken(DateTime(2030, 1, 8, 8));
      final due = DoseTracking.countDue(a, now);
      expect(due.total, 3); // Jan 8, 9, 10.
      expect(due.taken, 1);
      expect(due.missed, 2);
    });

    test('editing a schedule does not double-count a day', () {
      final a = daily('a', ['08:00', '20:00'])
        ..markTaken(DateTime(2030, 1, 10, 8));
      final tomorrow = DateTime(2030, 1, 11);
      final revised = a.withScheduleFrom(
          ScheduleEdit.draftOf(a)
            ..times = ['09:00', '21:00']
            ..start = tomorrow,
          tomorrow);
      for (final day in [DateTime(2030, 1, 10), DateTime(2030, 1, 11)]) {
        expect(DoseTracking.countDay([revised], day, now).total, 2);
      }
      expect(DoseTracking.countDay([revised], DateTime(2030, 1, 10), now).taken,
          1);
    });

    test('timeline is chronological across medicines', () {
      final a = daily('a', ['20:00', '08:00']);
      final b = daily('b', ['12:00']);
      expect(
          DoseTracking.dosesOn([a, b], DateTime(2030, 1, 10))
              .map((e) => e.$2.hour),
          [8, 12, 20]);
    });
  });
}
