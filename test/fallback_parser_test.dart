// Parser test: `flutter test`
// Dagdagan ng sariling cases. Gamitin ang resulta para sa accuracy table sa README.
import 'package:flutter_test/flutter_test.dart';
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

  test('q8h = 3x', () {
    final m = FallbackParser.parse('Cefalexin 500 mg 1 cap q8h for 1 week').single;
    expect(m.timesPerDay, 3);
    expect(m.days, 7);
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
    expect(m.instructions, 'bago kumain');
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
}
