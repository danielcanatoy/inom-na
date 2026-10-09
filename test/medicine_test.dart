import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';

Medicine intervalMedicine({
  int hours = 8,
  DateTime? start,
  int? days = 2,
  DateTime? end,
}) =>
    Medicine(
      id: 'rx-interval',
      name: 'Amoxicillin',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.interval,
      intervalHours: hours,
      durationConfirmed: true,
      days: days,
      end: end,
      start: start ?? DateTime(2026, 10, 9, 8),
    );

Medicine dailyMedicine({DateTime? start, int? days = 1}) => Medicine(
      id: 'rx-daily',
      name: 'Paracetamol',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: 1,
      times: ['08:00'],
      durationConfirmed: true,
      days: days,
      start: start ?? DateTime(2026, 10, 9, 8),
    );

void main() {
  group('fixed intervals', () {
    for (final hours in [6, 8]) {
      test('q${hours}h keeps equal intervals across midnight', () {
        final medicine = intervalMedicine(hours: hours);
        final doses = medicine.allDoses(horizon: DateTime(2026, 10, 20));
        expect(doses.length, 48 ~/ hours);
        expect(doses.first, medicine.start);
        for (var index = 1; index < doses.length; index++) {
          expect(doses[index].difference(doses[index - 1]),
              Duration(hours: hours));
        }
        expect(doses.last.isBefore(medicine.scheduleEnd!), isTrue);
      });
    }

    test('finite schedules honor the supplied horizon', () {
      final medicine = intervalMedicine();
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 9, 16)), [
        DateTime(2026, 10, 9, 8),
        DateTime(2026, 10, 9, 16),
      ]);
      expect(medicine.totalDoses, 6);
    });

    test('opt-in capacity query stops interval and clock-time generation', () {
      final interval = intervalMedicine(days: null);
      expect(interval.allDoses(horizon: DateTime(9999), limit: 2), [
        DateTime(2026, 10, 9, 8),
        DateTime(2026, 10, 9, 16),
      ]);
      final daily = dailyMedicine(days: null);
      expect(daily.allDoses(horizon: DateTime(9999), limit: 2), [
        DateTime(2026, 10, 9, 8),
        DateTime(2026, 10, 10, 8),
      ]);
    });

    test('upcoming query preserves original anchor', () {
      final medicine = intervalMedicine(days: null);
      expect(
          medicine.allDoses(
            from: DateTime(2026, 10, 10, 9),
            horizon: DateTime(2026, 10, 11),
          ),
          [DateTime(2026, 10, 10, 16), DateTime(2026, 10, 11)]);
    });

    test('explicit end is exclusive, including partial interval courses', () {
      final medicine = intervalMedicine(
        days: null,
        end: DateTime(2026, 10, 9, 19),
      );
      expect(medicine.totalDoses, 2);
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 10)), [
        DateTime(2026, 10, 9, 8),
        DateTime(2026, 10, 9, 16),
      ]);
      medicine.end = DateTime(2026, 10, 9, 16);
      expect(medicine.totalDoses, 1);
    });
  });

  group('daily and explicit times', () {
    test('saving after a dose does not backdate new prescriptions', () {
      final medicine = dailyMedicine(start: DateTime(2026, 10, 9, 8, 20));
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 12)),
          [DateTime(2026, 10, 10, 8)]);
      expect(medicine.scheduleEnd, DateTime(2026, 10, 10, 8, 20));
      expect(medicine.totalDoses, 1);
    });

    test('explicit clock times are preserved rather than replaced', () {
      final medicine = dailyMedicine()
        ..scheduleKind = ScheduleKind.explicit
        ..frequencyPerDay = null
        ..times = ['09:15', '17:45'];
      expect(medicine.validationErrors(), isEmpty);
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 10)), [
        DateTime(2026, 10, 9, 9, 15),
        DateTime(2026, 10, 9, 17, 45),
      ]);
    });

    test('daily frequency remains distinct from interval instructions', () {
      final medicine = dailyMedicine()
        ..frequencyPerDay = 3
        ..times = ['08:00', '14:00', '20:00'];
      expect(medicine.scheduleKind, ScheduleKind.daily);
      expect(medicine.intervalHours, isNull);
      expect(medicine.totalDoses, 3);
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 10)).length, 3);
    });

    test('all supported suggested daily schedules contain unique valid times', () {
      for (var count = 1; count <= 24; count++) {
        final times = Medicine.defaultTimes(count);
        expect(times.length, count);
        expect(times.toSet().length, count);
        expect(times.every(Medicine.validTime), isTrue);
      }
    });
  });

  group('required prescription validation', () {
    test('new drafts do not invent frequency, quantity, duration or PRN', () {
      final medicine = Medicine(id: 'draft', name: 'Paracetamol');
      expect(medicine.scheduleKind, ScheduleKind.unknown);
      expect(medicine.qtyPerIntake, 0);
      expect(medicine.durationConfirmed, isFalse);
      expect(medicine.isPrn, isFalse);
      expect(medicine.isMaintenance, isFalse);
      expect(medicine.validationErrors().length, greaterThanOrEqualTo(4));
      expect(medicine.allDoses(horizon: DateTime(2099)), isEmpty);
    });

    test('missing duration does not silently become maintenance', () {
      final medicine = dailyMedicine(days: null)..durationConfirmed = false;
      expect(medicine.isMaintenance, isFalse);
      expect(medicine.validationErrors(), isNotEmpty);
      medicine.durationConfirmed = true;
      expect(medicine.isMaintenance, isTrue);
      expect(medicine.validationErrors(), isEmpty);
    });

    test('dosage requires a positive value and unit', () {
      for (final invalid in ['', '?', 'unknown', '0mg', '-5mg', '500']) {
        expect(Medicine.validDose(invalid), isFalse, reason: invalid);
      }
      for (final valid in ['500mg', '5 mg/5 ml', '0.5mg', '5%', '100 units']) {
        expect(Medicine.validDose(valid), isTrue, reason: valid);
      }
    });

    test('invalid quantities are blocked instead of accepted', () {
      final medicine = dailyMedicine();
      for (final quantity in [0.0, -1.0, double.nan, double.infinity]) {
        medicine.qtyPerIntake = quantity;
        expect(medicine.validationErrors(), isNotEmpty);
        expect(medicine.qtyLabel, '?');
      }
    });

    test('duplicates, invalid times and daily count conflicts are rejected', () {
      final medicine = dailyMedicine()..times = ['08:00', '08:00'];
      expect(medicine.scheduleErrors(), isNotEmpty);
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 10)), isEmpty);
      for (final time in ['24:00', '08:60', '8:00', 'garbage']) {
        medicine.times = [time];
        expect(medicine.scheduleErrors(), isNotEmpty, reason: time);
      }
      medicine.times = ['08:00'];
      medicine.frequencyPerDay = 2;
      expect(medicine.scheduleErrors(), isNotEmpty);
    });

    test('bad intervals, duration and end bounds are rejected', () {
      final medicine = intervalMedicine();
      for (final hours in [0, -1, 169]) {
        medicine.intervalHours = hours;
        expect(medicine.scheduleErrors(), isNotEmpty);
      }
      medicine.intervalHours = 8;
      medicine.days = 0;
      expect(medicine.scheduleErrors(), isNotEmpty);
      medicine.days = null;
      medicine.end = medicine.start;
      expect(medicine.scheduleErrors(), isNotEmpty);
      expect(medicine.scheduleEnd, isNull);
      medicine.end = medicine.start.add(const Duration(days: 2));
      medicine.days = 2;
      expect(medicine.scheduleErrors(), isNotEmpty);
    });

    test('invalid or duplicate extracted interval anchors require review', () {
      final medicine = intervalMedicine()..times = ['25:00'];
      expect(medicine.scheduleErrors(), isNotEmpty);
      medicine.times = ['08:00', '08:00'];
      expect(medicine.scheduleErrors(), isNotEmpty);
      medicine.times = ['08:00'];
      expect(medicine.scheduleErrors(), isEmpty);
    });

    test('PRN must be explicit, not inferred from empty times', () {
      final medicine = dailyMedicine()..times = [];
      expect(medicine.isPrn, isFalse);
      expect(medicine.validationErrors(), isNotEmpty);
      medicine.scheduleKind = ScheduleKind.prn;
      expect(medicine.validationErrors(), isEmpty);
      expect(medicine.allDoses(horizon: DateTime(2099)), isEmpty);
    });

    test('explicit end cannot bypass the maximum finite duration', () {
      final medicine = intervalMedicine(days: null, end: DateTime(9999));
      expect(medicine.scheduleErrors(), isNotEmpty);
      expect(medicine.allDoses(horizon: DateTime(9999)), isEmpty);
      expect(medicine.totalDoses, isNull);
    });
  });

  group('legacy persistence and intake identity', () {
    Map<String, dynamic> legacyRecord() => {
          'id': 'saved-rx',
          'name': 'Paracetamol',
          'dose': '500mg',
          'times': ['08:00', '20:00'],
          'days': 1,
          'start': DateTime(2026, 10, 9, 20, 1).toIso8601String(),
          'taken': ['2026-10-09 20:00'],
        };

    test('legacy course count and scheduled keys survive a versioned roundtrip', () {
      final medicine = Medicine.fromJson(legacyRecord());
      expect(medicine.legacy, isTrue);
      expect(medicine.qtyPerIntake, 1);
      expect(medicine.totalDoses, 2);
      final doses = medicine.allDoses(horizon: DateTime(2026, 10, 12));
      expect(doses, [DateTime(2026, 10, 9, 20), DateTime(2026, 10, 10, 8)]);
      expect(medicine.isTaken(doses.first), isTrue);
      final decoded = Medicine.fromJson(medicine.toJson());
      expect(decoded.allDoses(horizon: DateTime(2026, 10, 12)), doses);
      expect(decoded.taken, medicine.taken);
      expect(decoded.toJson().containsKey('takenAt'), isFalse);
      expect(decoded.toJson()['schemaVersion'], 2);
    });

    test('legacy dose generation respects horizon without losing future count', () {
      final medicine = Medicine.fromJson(legacyRecord());
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 10)),
          [DateTime(2026, 10, 9, 20)]);
      expect(medicine.totalDoses, 2);
    });

    test('legacy backdating never generates a preceding calendar-day dose', () {
      final record = legacyRecord()
        ..['start'] = DateTime(2026, 10, 9, 0, 10).toIso8601String()
        ..['times'] = ['23:50'];
      final medicine = Medicine.fromJson(record);
      expect(medicine.allDoses(horizon: DateTime(2026, 10, 11)),
          [DateTime(2026, 10, 9, 23, 50)]);
    });

    test('mark taken is idempotent and identity includes the medicine', () {
      final medicine = dailyMedicine();
      final scheduled = medicine.start;
      expect(medicine.markTaken(scheduled), isTrue);
      expect(medicine.markTaken(scheduled), isFalse);
      expect(medicine.taken.length, 1);
      expect(medicine.doseId(scheduled), 'rx-daily|2026-10-09 08:00');
      expect(medicine.markTaken(scheduled, value: false), isTrue);
      expect(medicine.markTaken(scheduled, value: false), isFalse);
      expect(medicine.taken, isEmpty);
    });

    test('legacy duplicate keys are deduplicated without fabricating timestamps', () {
      final record = legacyRecord()
        ..['taken'] = ['2026-10-09 20:00', '2026-10-09 20:00'];
      final medicine = Medicine.fromJson(record);
      expect(medicine.taken, ['2026-10-09 20:00']);
      expect(medicine.toJson().containsKey('takenAt'), isFalse);
    });

    test('missing or corrupt start cannot invent a prescription start date', () {
      final record = legacyRecord()..['start'] = 'invalid';
      expect(() => Medicine.fromJson(record), throwsFormatException);
    });

    test('modern interval semantics survive persistence', () {
      final medicine = intervalMedicine()..reviewNotes = ['Suriin ang tagubilin'];
      final decoded = Medicine.fromJson(medicine.toJson());
      expect(decoded.scheduleKind, ScheduleKind.interval);
      expect(decoded.intervalHours, 8);
      expect(decoded.reviewNotes, medicine.reviewNotes);
      expect(decoded.totalDoses, 6);
      expect(decoded.allDoses(horizon: DateTime(2026, 10, 20)),
          medicine.allDoses(horizon: DateTime(2026, 10, 20)));
    });

    test('review drafts do not share mutable lists with original medicines', () {
      final original = dailyMedicine()..reviewNotes = ['Original note'];
      final draft = Medicine.fromJson(original.toJson());
      draft.times.add('20:00');
      draft.reviewNotes.add('Draft note');
      draft.markTaken(draft.start);
      expect(original.times, ['08:00']);
      expect(original.reviewNotes, ['Original note']);
      expect(original.taken, isEmpty);
    });
  });

  test('schedule ended and all doses taken are independent states', () {
    final past = dailyMedicine(start: DateTime(2020, 1, 1, 8));
    expect(past.isFinished, isTrue);
    expect(past.allTaken, isFalse);
    for (final scheduled in past.allDoses(horizon: DateTime(2020, 1, 3))) {
      past.markTaken(scheduled);
    }
    expect(past.allTaken, isTrue);

    final future = dailyMedicine(start: DateTime(2099, 1, 1, 8));
    future.markTaken(future.start);
    expect(future.allTaken, isTrue);
    expect(future.isFinished, isFalse);
  });
}
