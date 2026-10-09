// Scanner benchmark: synthetic, printed-style prescription text (no real
// patient data). Scores what the phone-only reader extracts per field so
// before/after changes can be compared honestly. Run with:
//   flutter test test/scanner_benchmark_test.dart --reporter expanded
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/rx_parser.dart';

/// Expected fields for one medicine. null = must stay unresolved/absent.
class Expect {
  const Expect(this.name,
      {this.dose,
      this.qty,
      this.kind,
      this.perDay,
      this.interval,
      this.days,
      this.maintenance = false,
      this.stock});
  final String name;
  final String? dose;
  final double? qty;
  final ScheduleKind? kind;
  final int? perDay;
  final int? interval;
  final int? days;
  final bool maintenance;
  final int? stock;
}

class Fixture {
  const Fixture(this.label, this.text, this.expected);
  final String label;
  final String text;
  final List<Expect> expected;
}

const fixtures = [
  Fixture(
      'A  simple printed',
      'SAMPLE / NOT FOR MEDICAL USE\nAmoxicillin 500 mg\n'
          'Take 1 capsule every 8 hours for 7 days.\nQuantity: 21',
      [
        Expect('Amoxicillin',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.interval,
            interval: 8,
            days: 7,
            stock: 21)
      ]),
  Fixture(
      'B  abbreviated (OD)',
      'SAMPLE / NOT FOR MEDICAL USE\nMedicine: Losartan 50 mg\n'
          'Sig: 1 tab PO OD\nDuration: ongoing',
      [
        Expect('Losartan',
            dose: '50mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 1,
            maintenance: true)
      ]),
  Fixture(
      'C  PRN syrup',
      'SAMPLE / NOT FOR MEDICAL USE\nMedicine: Dextromethorphan 15 mg/5 mL\n'
          'Sig: 5 mL as needed for cough',
      [
        Expect('Dextromethorphan',
            dose: '15mg/5mL', qty: 5, kind: ScheduleKind.prn)
      ]),
  Fixture(
      'D  caps, OCR spacing',
      'SAMPLE / NOT FOR MEDICAL USE\nAMOXICILLIN   500   MG  CAPSULE\n'
          'Take  1  capsule   three times daily  for 7 days',
      [
        Expect('AMOXICILLIN',
            dose: '500MG', qty: 1, kind: ScheduleKind.daily, perDay: 3, days: 7)
      ]),
  Fixture(
      'E  "Medicine:" label, strength next line',
      'SAMPLE / NOT FOR MEDICAL USE\nMedicine: Cefuroxime\n500 mg tablet\n'
          'Take 1 tablet twice daily for 7 days\nQty: 14',
      [
        Expect('Cefuroxime',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 2,
            days: 7,
            stock: 14)
      ]),
  Fixture(
      'F  clinic + patient header, two medicines',
      'SAMPLE / NOT FOR MEDICAL USE\nSunrise Family Clinic\n'
          '123 Mabini St., Quezon City\nTel: 8123 4567\n'
          'Patient: Test Patient   Age: 60\nDate: 10/10/2026\nRx\n'
          '1. Metformin 500 mg\nSig: 1 tab twice daily after meals, ongoing\n'
          '2. Atorvastatin 20 mg\nSig: 1 tab at bedtime, ongoing',
      [
        Expect('Metformin',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 2,
            maintenance: true),
        Expect('Atorvastatin',
            dose: '20mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 1,
            maintenance: true),
      ]),
  Fixture(
      'G  flattened OCR (one line)',
      'SAMPLE / NOT FOR MEDICAL USE Amoxicillin 500 mg Take 1 capsule '
          'every 8 hours for 7 days Quantity: 21',
      [
        Expect('Amoxicillin',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.interval,
            interval: 8,
            days: 7,
            stock: 21)
      ]),
  Fixture(
      'H  decimal strength',
      'SAMPLE / NOT FOR MEDICAL USE\nLevothyroxine 0.05 mg\n'
          'Take 1 tablet once daily before breakfast, ongoing',
      [
        Expect('Levothyroxine',
            dose: '0.05mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 1,
            maintenance: true)
      ]),
  Fixture(
      'I  q6h, every 6 hours words',
      'SAMPLE / NOT FOR MEDICAL USE\nParacetamol 500 mg\n'
          '1 tablet every 6 hours for 3 days',
      [
        Expect('Paracetamol',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.interval,
            interval: 6,
            days: 3)
      ]),
  Fixture(
      'J  no medicine (header only)',
      'SAMPLE / NOT FOR MEDICAL USE\nSunrise Family Clinic\nTel: 8123 4567',
      []),
  Fixture(
      'K  missing strength (partial)',
      'SAMPLE / NOT FOR MEDICAL USE\nMedicine: Cetirizine\n'
          'Take 1 tablet once daily for 5 days',
      [
        Expect('Cetirizine',
            qty: 1, kind: ScheduleKind.daily, perDay: 1, days: 5)
      ]),
  Fixture(
      'L  OCR misread digits/units',
      'SAMPLE / NOT FOR MEDICAL USE\nAmoxicillin 5OO rng\n'
          'Take 1 capsule every 8 hours for 7 days',
      [
        Expect('Amoxicillin',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.interval,
            interval: 8,
            days: 7)
      ]),
];

/// Held-out inputs written AFTER the parser changes and not tuned for.
/// Their score is reported as-is.
const heldOut = [
  Fixture(
      'M  PRN with interval',
      'SAMPLE / NOT FOR MEDICAL USE\nRx: Mefenamic Acid 500 mg cap\n'
          '1 cap every 8 hours as needed for pain',
      [
        Expect('Mefenamic Acid', dose: '500mg', qty: 1, kind: ScheduleKind.prn)
      ]),
  Fixture(
      'N  OD x 3 days with #',
      'SAMPLE / NOT FOR MEDICAL USE\nAzithromycin 500mg tab\n'
          'Sig: 1 tab OD x 3 days\n#3',
      [
        Expect('Azithromycin',
            dose: '500mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 1,
            days: 3,
            stock: 3)
      ]),
  Fixture(
      'O  address line + once a day',
      'SAMPLE / NOT FOR MEDICAL USE\nPatient: Test Patient\n'
          'Address: 45 Rizal Ave, Manila\n'
          'Amlodipine 5mg 1 tab once a day maintenance',
      [
        Expect('Amlodipine',
            dose: '5mg',
            qty: 1,
            kind: ScheduleKind.daily,
            perDay: 1,
            maintenance: true)
      ]),
  Fixture(
      'P  syrup TID x 5 days',
      'SAMPLE / NOT FOR MEDICAL USE\nSalbutamol 2mg/5ml syrup\n'
          '5 ml TID x 5 days',
      [
        Expect('Salbutamol',
            dose: '2mg/5ml',
            qty: 5,
            kind: ScheduleKind.daily,
            perDay: 3,
            days: 5)
      ]),
];

/// Returns (correct fields, total fields, wrong-field labels).
(int, int, List<String>) score(Expect e, Medicine m) {
  final wrong = <String>[];
  var total = 0, ok = 0;
  void check(String field, bool good) {
    total++;
    good ? ok++ : wrong.add(field);
  }

  check('name', m.name.toLowerCase() == e.name.toLowerCase());
  check('strength', (e.dose ?? '').toLowerCase() == m.dose.toLowerCase());
  check(
      'amount', e.qty == null ? m.qtyPerIntake == 0 : m.qtyPerIntake == e.qty);
  check(
      'schedule',
      e.kind == null
          ? m.scheduleKind == ScheduleKind.unknown
          : m.scheduleKind == e.kind &&
              (e.perDay == null || m.frequencyPerDay == e.perDay) &&
              (e.interval == null || m.intervalHours == e.interval));
  check(
      'duration',
      e.maintenance
          ? m.isMaintenance
          : e.days == null
              ? !m.durationConfirmed || m.days == null
              : m.days == e.days && m.durationConfirmed);
  check('stock', m.stock == e.stock);
  return (ok, total, wrong);
}

void main() {
  test('held-out inputs (reported, not tuned)', () => run(heldOut, 'HELDOUT'));
  test('phone-only reader benchmark (synthetic printed text)',
      () => run(fixtures, 'BENCH'));
}

void run(List<Fixture> fixtures, String tag) {
  {
    var fieldsOk = 0, fieldsTotal = 0, medsFound = 0, medsExpected = 0;
    var falsePositives = 0;
    final watch = Stopwatch();
    final lines = <String>[];
    for (final f in fixtures) {
      watch.start();
      final meds = RxParser.readOnPhone(f.text).meds;
      watch.stop();
      medsExpected += f.expected.length;
      final details = <String>[];
      var used = <Medicine>{};
      for (final e in f.expected) {
        final match = meds
            .where((m) =>
                !used.contains(m) &&
                m.name.toLowerCase().contains(e.name.toLowerCase()))
            .firstOrNull;
        if (match == null) {
          fieldsTotal += 6;
          details.add('${e.name}: NOT FOUND');
          continue;
        }
        used.add(match);
        medsFound++;
        final (ok, total, wrong) = score(e, match);
        fieldsOk += ok;
        fieldsTotal += total;
        details.add('${e.name}: $ok/$total'
            '${wrong.isEmpty ? '' : ' wrong: ${wrong.join(', ')}'}');
      }
      final extra = meds.where((m) => !used.contains(m)).toList();
      falsePositives += extra.length;
      if (extra.isNotEmpty) {
        details.add('false positives: ${extra.map((m) => m.name).join(', ')}');
      }
      lines.add('${f.label.padRight(42)} found ${meds.length}/'
          '${f.expected.length}  ${details.join('; ')}');
    }
    // ignore: avoid_print
    print('$tag\n${lines.join('\n')}\n'
        'TOTAL medicines found $medsFound/$medsExpected, '
        'fields $fieldsOk/$fieldsTotal, false positives $falsePositives, '
        'time ${watch.elapsedMicroseconds ~/ fixtures.length} µs/input');
  }
}
