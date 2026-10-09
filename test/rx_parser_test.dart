import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/rx_parser.dart';

Medicine extract(Map<String, Object?> fields) => RxParser.medsFromContent(
      jsonEncode({'medicines': [{'name': 'Amoxicillin', ...fields}]}),
    ).single;

void main() {
  test('missing required fields never become once daily or maintenance', () {
    final medicine = extract({});
    expect(medicine.dose, isEmpty);
    expect(medicine.qtyPerIntake, 0);
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.times, isEmpty);
    expect(medicine.isPrn, isFalse);
    expect(medicine.isMaintenance, isFalse);
    expect(medicine.durationConfirmed, isFalse);
    expect(medicine.validationErrors(), isNotEmpty);
  });

  test('null duration does not mean maintenance', () {
    final medicine = extract({'times_per_day': 1, 'days': null});
    expect(medicine.durationConfirmed, isFalse);
    expect(medicine.isMaintenance, isFalse);
  });

  test('maintenance is accepted only explicitly', () {
    final medicine = extract({'times_per_day': 1, 'maintenance': true});
    expect(medicine.isMaintenance, isTrue);
  });

  test('new interval schema preserves q8h', () {
    final medicine = extract({
      'dose': '500mg', 'qty_per_intake': 1,
      'frequency_type': 'interval', 'interval_hours': 8, 'days': 7,
    });
    expect(medicine.scheduleKind, ScheduleKind.interval);
    expect(medicine.intervalHours, 8);
    expect(medicine.times, isEmpty);
    expect(medicine.validationErrors(), isEmpty);
  });

  test('written q8h corrects old-model general frequency interpretation', () {
    final medicine = extract({
      'times_per_day': 3, 'instructions': '1 cap q8h x 7 days',
    });
    expect(medicine.scheduleKind, ScheduleKind.interval);
    expect(medicine.intervalHours, 8);
    expect(medicine.times, isEmpty);
  });

  test('explicit administration times are not replaced with defaults', () {
    final medicine = extract({
      'frequency_type': 'explicit', 'times': ['07:15', '19:15'],
      'days': 3,
    });
    expect(medicine.times, ['07:15', '19:15']);
    expect(medicine.scheduleKind, ScheduleKind.explicit);
  });

  test('original written times override generated general frequency times', () {
    final medicine = extract({
      'times_per_day': 2, 'instructions': '1 cap at 07:15 and 19:15 x 3 days',
    });
    expect(medicine.times, ['07:15', '19:15']);
    expect(medicine.scheduleKind, ScheduleKind.explicit);
  });

  test('malformed numeric values do not get default values', () {
    final medicine = extract({
      'dose': {'incorrect': 'object'}, 'qty_per_intake': 'NaN',
      'times_per_day': 1.5, 'days': 'unknown',
    });
    expect(medicine.dose, isEmpty);
    expect(medicine.qtyPerIntake, 0);
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.durationConfirmed, isFalse);
  });

  test('negative values are preserved as invalid rather than accepted', () {
    final medicine = extract({
      'dose': '500mg', 'qty_per_intake': -1,
      'frequency_type': 'daily', 'times_per_day': -2, 'days': -3,
    });
    expect(medicine.validationErrors(), isNotEmpty);
    expect(medicine.times, isEmpty);
    expect(medicine.durationConfirmed, isFalse);
  });

  test('duplicate and invalid times fail validation', () {
    final medicine = extract({
      'frequency_type': 'explicit', 'times': ['25:00', '08:00', '08:00'],
      'maintenance': true,
    });
    expect(medicine.scheduleErrors(), isNotEmpty);
  });

  test('malformed time entries cannot be silently discarded', () {
    final medicine = extract({
      'frequency_type': 'explicit', 'times': ['08:00', 20], 'days': 7,
    });
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.scheduleErrors(), isNotEmpty);
  });

  test('conflicting written directions override apparently valid AI fields', () {
    final medicine = extract({
      'frequency_type': 'daily', 'times_per_day': 2,
      'instructions': '1 cap BID q8h x 7 days',
    });
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.instructions, contains('BID q8h'));
  });

  test('contradictory maintenance and finite duration require correction', () {
    final medicine = extract({
      'times_per_day': 1, 'days': 7, 'maintenance': true,
      'instructions': '1 cap OD x 7 days',
    });
    expect(medicine.durationConfirmed, isFalse);
    expect(medicine.isMaintenance, isFalse);
  });

  test('uncertain original instructions remain visible', () {
    final medicine = extract({
      'instructions': 'Sig: unreadable abbreviation',
      'uncertainties': ['Frequency unreadable'],
    });
    expect(medicine.instructions, 'Sig: unreadable abbreviation');
    expect(medicine.reviewNotes, contains('Frequency unreadable'));
    expect(medicine.scheduleKind, ScheduleKind.unknown);
  });

  test('prescribed end calendar date includes its final day', () {
    final medicine = extract({
      'times_per_day': 1, 'start_date': '2026-10-09', 'end_date': '2026-10-12',
    });
    expect(medicine.start, DateTime(2026, 10, 9));
    expect(medicine.end, DateTime(2026, 10, 13));
    expect(medicine.durationConfirmed, isTrue);
    expect(medicine.days, isNull);
  });

  test('impossible calendar dates are not normalized into a different date', () {
    final medicine = extract({'end_date': '2026-02-30'});
    expect(medicine.end, isNull);
    expect(medicine.durationConfirmed, isFalse);
  });

  test('quantity inconsistent with written directions stays unresolved', () {
    final medicine = extract({
      'qty_per_intake': 2, 'times_per_day': 1,
      'instructions': '1 cap OD x 7 days',
    });
    expect(medicine.qtyPerIntake, 0);
    expect(medicine.validationErrors(), isNotEmpty);
  });

  test('PRN is explicit and retains the written minimum interval', () {
    final medicine = extract({
      'frequency_type': 'prn', 'interval_hours': 6,
      'instructions': '1 cap q6h PRN for pain', 'days': 3,
    });
    expect(medicine.isPrn, isTrue);
    expect(medicine.intervalHours, 6);
    expect(medicine.allDoses(horizon: medicine.start.add(const Duration(days: 3))), isEmpty);
  });

  test('unexpected medicines container is handled without a cast error', () {
    expect(RxParser.medsFromContent('{"medicines":{}}'), isEmpty);
    expect(RxParser.medsFromContent('[]'), isEmpty);
  });

  test('interval anchor from structured extraction survives direction checking', () {
    final medicine = extract({
      'frequency_type': 'interval', 'interval_hours': 8, 'times': ['07:30'],
      'instructions': '1 cap q8h x 7 days',
    });
    expect(medicine.scheduleKind, ScheduleKind.interval);
    expect(medicine.times, ['07:30']);
  });
}
