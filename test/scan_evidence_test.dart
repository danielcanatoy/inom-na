// Synthetic, de-identified fixtures ("SAMPLE / NOT FOR MEDICAL USE").
// An AI or OCR result must never add schedule facts that are not written.
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/med_names.dart';
import 'package:inom_na/services/rx_parser.dart';

const compoundText = 'SAMPLE / NOT FOR MEDICAL USE\nRx\n'
    'Dextromethorphan 15 mg/5 mL\nGuaifenesin syrup 100 mg/5 mL\n'
    'Alcohol 5%\nFlavored syrup q.s. ad 60 mL\nM. ft. syrup\n'
    'Sig: 5 mL as needed for cough';

String _ai(List<String> meds) => '{"medicines":[${meds.join(',')}]}';

String _med(String name,
        {String type = 'interval',
        int? interval = 8,
        int? perDay,
        int? days = 7,
        String instructions = '1 cap q8h x 7 days'}) =>
    '{"name":"$name","dose":"","qty_per_intake":1,"frequency_type":"$type",'
    '"times_per_day":${perDay ?? 'null'},"interval_hours":${interval ?? 'null'},'
    '"times":[],"bedtime":false,"days":${days ?? 'null'},"maintenance":false,'
    '"start_date":null,"end_date":null,"instructions":"$instructions",'
    '"uncertainties":[],"stock":null}';

bool _scheduled(Medicine m) =>
    m.scheduleKind == ScheduleKind.interval ||
    m.scheduleKind == ScheduleKind.daily ||
    m.scheduleKind == ScheduleKind.explicit;

void main() {
  test('AI q8h / 7 days not written in a PRN prescription is not applied', () {
    // A model that copied an example schedule onto a PRN syrup.
    final meds = RxParser.medsFromContent(_ai([_med('Dextromethorphan')]));
    final result = RxParser.reviewAiResult(meds, compoundText);
    final m = result.meds.single;
    expect(m.scheduleKind, isNot(ScheduleKind.interval));
    expect(m.intervalHours, isNull);
    expect(m.days, isNull);
    expect(m.durationConfirmed, isFalse);
    expect(m.instructions, isNot(contains('q8h')));
    expect(m.validationErrors(), isNotEmpty);
    expect(result.warnings[m.id], contains('every 8 hours'));
  });

  test('a missing duration never becomes seven days', () {
    final meds = RxParser.medsFromContent(_ai([
      _med('Losartan',
          type: 'daily', interval: null, perDay: 1, instructions: '1 tab OD')
    ]));
    final m = RxParser.reviewAiResult(
            meds, 'SAMPLE / NOT FOR MEDICAL USE\nLosartan 50 mg\n1 tab OD')
        .meds
        .single;
    expect(m.scheduleKind, ScheduleKind.daily);
    expect(m.frequencyPerDay, 1);
    expect(m.days, isNull);
    expect(m.durationConfirmed, isFalse);
  });

  test('an AI schedule supported by the read text is kept', () {
    final meds = RxParser.medsFromContent(_ai([_med('Amoxicillin')]));
    final m = RxParser.reviewAiResult(
            meds,
            'SAMPLE / NOT FOR MEDICAL USE\nAmoxicillin 500 mg\n'
            '1 cap every 8 hours x 7 days #21')
        .meds
        .single;
    expect(m.scheduleKind, ScheduleKind.interval);
    expect(m.intervalHours, 8);
    expect(m.days, 7);
    expect(m.durationConfirmed, isTrue);
  });

  test('with no readable text, an AI schedule cannot be verified as-is', () {
    final meds = RxParser.medsFromContent(_ai([_med('Amoxicillin')]));
    final m = RxParser.reviewAiResult(meds, '').meds.single;
    expect(_scheduled(m), isFalse);
    expect(m.validationErrors(), isNotEmpty);
  });

  test('compounded ingredients do not become separate scheduled medicines', () {
    final ai = RxParser.reviewAiResult(
        RxParser.medsFromContent(_ai([
          _med('Dextromethorphan'),
          _med('Guaifenesin'),
          _med('Alcohol'),
        ])),
        compoundText);
    expect(ai.meds, hasLength(3));
    for (final m in ai.meds) {
      expect(_scheduled(m), isFalse, reason: m.name);
      expect(m.validationErrors(), isNotEmpty, reason: m.name);
      expect(ai.warnings[m.id], contains('compounded'), reason: m.name);
    }
    final phone = RxParser.readOnPhone(compoundText);
    expect(phone.meds.length, greaterThan(1));
    for (final m in phone.meds) {
      expect(_scheduled(m), isFalse, reason: m.name);
      expect(phone.warnings[m.id], contains('compounded'), reason: m.name);
    }
  });

  test('an OCR-uncertain name is kept as read, unverified, with suggestions',
      () {
    final result = RxParser.readOnPhone('Anoxicillin\n1 cap every 8 hours');
    final m = result.meds.single;
    expect(m.name, 'Anoxicillin');
    expect(m.dose, isEmpty);
    expect(m.validationErrors(), isNotEmpty);
    expect(MedNames.suggestions(m.name), contains('Amoxicillin'));
    expect(result.warnings[m.id], contains("Did you mean 'Amoxicillin'"));
  });

  test('missing or unreadable units leave the strength blank', () {
    final bare = RxParser.readOnPhone('Metformin 500\n1 tab BID').meds.single;
    expect(bare.dose, isEmpty);
    expect(bare.validationErrors(), isNotEmpty);
    final garbled =
        RxParser.readOnPhone('Colchicine O.5 mg\n1 tab OD').meds.single;
    expect(garbled.dose, isEmpty);
    expect(garbled.validationErrors(), isNotEmpty);
  });

  test('a new scan never reuses fields from the previous one', () {
    final first = RxParser.readOnPhone(
            'Amoxicillin 500 mg\n1 cap every 8 hours x 7 days #21')
        .meds
        .single;
    final second = RxParser.readOnPhone('Losartan 50 mg').meds.single;
    expect(second.id, isNot(first.id));
    expect(second.intervalHours, isNull);
    expect(second.days, isNull);
    expect(second.stock, isNull);
    expect(second.scheduleKind, ScheduleKind.unknown);
  });

  test('unreadable text gives no medicines (manual recovery path)', () {
    final result = RxParser.readOnPhone('~~ ## lI1 .. ,,');
    expect(result.meds, isEmpty);
    expect(result.source, RxParser.srcOffline);
  });

  test('printed prescriptions still read fully on the phone', () {
    final meds = RxParser.readOnPhone('SAMPLE / NOT FOR MEDICAL USE\nRx\n'
            'Amoxicillin 500 mg\n1 cap every 8 hours x 7 days  #21\n'
            'Colchicine 0.5 mg\n1 tab once daily  #30')
        .meds;
    expect(meds.map((m) => m.name), ['Amoxicillin', 'Colchicine']);
    expect(meds[0].intervalHours, 8);
    expect(meds[0].days, 7);
    expect(meds[1].dose, '0.5mg');
    expect(meds[1].frequencyPerDay, 1);
  });

  test('real qwen2.5vl:3b output (old prompt, synthetic image) is contained',
      () {
    // Captured from the laptop model on a synthetic handwriting-style image
    // of compoundText: it copied the prompt example "1 cap q8h x 7 days".
    String m(String name, String dose, int? interval, int? days,
            String instructions) =>
        '{"name":"$name","dose":"$dose","qty_per_intake":null,'
        '"frequency_type":"interval","times_per_day":null,'
        '"interval_hours":${interval ?? 'null'},"times":[],"bedtime":false,'
        '"days":${days ?? 'null'},"maintenance":false,"start_date":null,'
        '"end_date":null,"instructions":"$instructions","uncertainties":[],'
        '"stock":null}';
    final result = RxParser.reviewAiResult(
        RxParser.medsFromContent(_ai([
          m('Dextromethorphan', '15 mg', 8, 7, '1 cap q8h x 7 days'),
          m('Guaifenesin syrup', '100 mg', 8, 7, '100 mg/5 mL'),
          m('Alcohol', '5%', null, null, '5%'),
          m('Flavored syrup', 'q.s. ad', null, null, '60 mL'),
          m('M. ft. syrup', 'as needed', null, null,
              '5 mL as needed for cough'),
        ])),
        compoundText);
    for (final med in result.meds) {
      expect(_scheduled(med), isFalse, reason: med.name);
      expect(med.intervalHours, isNull, reason: med.name);
      expect(med.days, isNull, reason: med.name);
      expect(med.validationErrors(), isNotEmpty, reason: med.name);
      expect(med.instructions, isNot(contains('q8h')), reason: med.name);
    }
  });
}
