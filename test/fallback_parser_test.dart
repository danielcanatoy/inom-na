// Parser test: `flutter test`
// Dagdagan ng sariling cases. Gamitin ang resulta para sa accuracy table sa README.
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/fallback_parser.dart';

void main() {
  test('Antibiotic na may araw at bilang', () {
    final m = FallbackParser.parse('Amoxicillin 500mg\n1 cap TID x 7 days #21').single;
    expect(m.name, 'Amoxicillin');
    expect(m.dose, '500mg');
    expect(m.timesPerDay, 3);
    expect(m.days, 7);
    expect(m.stock, 21);
  });

  test('Maintenance, isang beses kada araw', () {
    final m = FallbackParser.parse('Losartan 50mg 1 tab OD maintenance').single;
    expect(m.timesPerDay, 1);
    expect(m.days, isNull);
  });

  test('q8h preserves a fixed eight-hour interval', () {
    final m = FallbackParser.parse('Cefalexin 500 mg 1 cap q8h for 1 week').single;
    expect(m.timesPerDay, 3);
    expect(m.days, 7);
    expect(m.scheduleKind, ScheduleKind.interval);
    expect(m.intervalHours, 8);
    final doses = m.allDoses(horizon: m.start.add(const Duration(days: 2)));
    for (var index = 1; index < doses.length; index++) {
      expect(doses[index].difference(doses[index - 1]), const Duration(hours: 8));
    }
  });

  test('Bedtime', () {
    final m = FallbackParser.parse('Atorvastatin 20mg 1 tab HS').single;
    expect(m.times, ['21:00']);
  });

  test('PRN walang paalala', () {
    final m = FallbackParser.parse('Paracetamol 500mg 1 tab q4h PRN for fever').single;
    expect(m.isPrn, isTrue);
  });

  test('Kalahating tableta, bago kumain', () {
    final m = FallbackParser.parse('Metformin 500mg 1/2 tab BID before meals').single;
    expect(m.qtyPerIntake, 0.5);
    expect(m.timesPerDay, 2);
    expect(m.instructions, contains('before meals'));
    expect(m.reviewNotes, isNotEmpty);
  });

  test('Dalawang gamot sa isang reseta', () {
    final meds = FallbackParser.parse(
      'Rx\n1. Amoxicillin 500mg #21\nSig: 1 cap TID x 7 days\n'
      '2. Paracetamol 500mg #10\nSig: 1 tab q6h PRN',
    );
    expect(meds.length, 2);
    expect(meds[0].timesPerDay, 3);
    expect(meds[0].stock, 21);
    expect(meds[1].isPrn, isTrue);
  });

  test('missing frequency, quantity and duration stay unresolved', () {
    final medicine = FallbackParser.parse('Amoxicillin 500mg').single;
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.isPrn, isFalse);
    expect(medicine.qtyPerIntake, 0);
    expect(medicine.durationConfirmed, isFalse);
    expect(medicine.isMaintenance, isFalse);
    expect(medicine.validationErrors(), isNotEmpty);
  });

  test('known bare name does not establish dose correctness', () {
    final medicine = FallbackParser.parse('Losartan\n1 tab OD maintenance').single;
    expect(medicine.dose, isEmpty);
    expect(medicine.validationErrors(), isNotEmpty);
  });

  test('continue alone does not establish maintenance', () {
    final medicine = FallbackParser.parse('Losartan 50mg 1 tab OD continue').single;
    expect(medicine.durationConfirmed, isFalse);
    expect(medicine.isMaintenance, isFalse);
    expect(medicine.instructions, contains('continue'));
  });

  test('daily frequency remains separate from fixed intervals', () {
    final medicine = FallbackParser.parse('Amoxicillin 500mg 1 cap TID x 7 days').single;
    expect(medicine.scheduleKind, ScheduleKind.daily);
    expect(medicine.frequencyPerDay, 3);
    expect(medicine.intervalHours, isNull);
  });

  test('q6h does not use unequal QID times', () {
    final medicine = FallbackParser.parse('Cefalexin 500mg 1 cap q6h for 2 days').single;
    expect(medicine.scheduleKind, ScheduleKind.interval);
    expect(medicine.intervalHours, 6);
    expect(medicine.times, isEmpty);
  });

  test('written 24-hour and am/pm times are preserved', () {
    final medicine = FallbackParser.parse('Losartan 50mg 1 tab at 07:30 and 7:30 pm for 3 days').single;
    expect(medicine.scheduleKind, ScheduleKind.explicit);
    expect(medicine.times, ['07:30', '19:30']);
  });

  test('duplicate times fail schedule validation', () {
    final medicine = FallbackParser.parse('Losartan 50mg 1 tab at 08:00 and 08:00 maintenance').single;
    expect(medicine.scheduleErrors(), isNotEmpty);
  });

  test('invalid clock time does not fall back to a daily schedule', () {
    final medicine = FallbackParser.parse('Losartan 50mg 1 tab OD at 25:00 maintenance').single;
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.scheduleErrors(), isNotEmpty);
  });

  test('contradictory intervals and frequencies remain unresolved', () {
    final medicine = FallbackParser.parse('Amoxicillin 500mg 1 cap BID q8h x 7 days').single;
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.instructions, contains('BID q8h'));
  });

  test('ambiguous timing directions remain visible and unresolved', () {
    final medicine = FallbackParser.parse('Losartan 50mg 1 tab daily except Sunday maintenance').single;
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.instructions, contains('except Sunday'));
  });

  test('contradictory duration cannot silently become maintenance', () {
    final medicine = FallbackParser.parse('Losartan 50mg 1 tab OD x 7 days maintenance').single;
    expect(medicine.durationConfirmed, isFalse);
    expect(medicine.isMaintenance, isFalse);
  });

  test('conflicting quantity remains unresolved', () {
    final medicine = FallbackParser.parse('Losartan 50mg\n1 tab OD\n2 tabs maintenance').single;
    expect(medicine.qtyPerIntake, 0);
    expect(medicine.validationErrors(), isNotEmpty);
  });

  test('written clock times conflicting with q8h require resolution', () {
    final medicine = FallbackParser.parse('Amoxicillin 500mg 1 cap q8h at 08:00 14:00 20:00 x 7 days').single;
    expect(medicine.scheduleKind, ScheduleKind.unknown);
    expect(medicine.reviewNotes.join(' '), contains('Hindi tugma'));
  });

  test('one explicit interval anchor is preserved for review', () {
    final medicine = FallbackParser.parse('Amoxicillin 500mg 1 cap q8h starting 07:30 x 7 days').single;
    expect(medicine.scheduleKind, ScheduleKind.interval);
    expect(medicine.times, ['07:30']);
  });

  test('contradictory meal directions do not silently choose one', () {
    final medicine = FallbackParser.parse('Metformin 500mg 1 tab BID before meals after meals maintenance').single;
    expect(medicine.scheduleKind, ScheduleKind.unknown);
  });

  test('negative strength and quantity are not converted to positive values', () {
    final medicine = FallbackParser.parse('Amoxicillin -500mg\n-1 cap TID x 7 days').single;
    expect(medicine.dose, '-500mg');
    expect(medicine.qtyPerIntake, 0);
    expect(medicine.validationErrors(), isNotEmpty);
  });
}
