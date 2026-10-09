// Pagsuri ng pangalan ng gamot at pagbasa ng JSON mula sa Ollama: `flutter test`
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/services/med_names.dart';
import 'package:inom_na/services/rx_parser.dart';

void main() {
  test('Carbocisteine ay nananatiling Carbocisteine (hindi Cefixime)', () {
    final c = MedNames.check('Carbocisteine');
    expect(c.name, 'Carbocisteine');
    expect(c.status, NameStatus.known);
    expect(c.warning, isNull);
  });

  test('Maliit na typo: inaayos pero may babala pa rin', () {
    final c = MedNames.check('Amoxicilin');
    expect(c.name, 'Amoxicillin');
    expect(c.status, NameStatus.corrected);
    expect(c.warning, contains("'Amoxicilin' → ginawang 'Amoxicillin'"));
    expect(MedNames.correct('Metformln'), 'Metformin');
    expect(MedNames.correct('losartan'), 'Losartan');
  });

  test('Malabo (Losartan vs Valsartan): hindi binabago, may babala', () {
    final c = MedNames.check('Lasartan');
    expect(c.name, 'Lasartan');
    expect(c.status, NameStatus.uncertain);
    expect(c.warning, contains('Losartan'));
  });

  test('Malaking edit: hindi binabago', () {
    // 2 letra ang layo sa Amlodipine, 9 letra lang -> suggestion lang
    final c = MedNames.check('Amlodipme');
    expect(c.name, 'Amlodipme');
    expect(c.status, NameStatus.uncertain);
  });

  test('Magkaibang tunay na gamot ay hindi pinagpapalit', () {
    expect(MedNames.check('Prednisolone').name, 'Prednisolone');
    expect(MedNames.check('Prednisone').name, 'Prednisone');
    expect(MedNames.check('Cefixime').name, 'Cefixime');
  });

  test('Hindi kilala o maikli: hindi ginagalaw, may babala', () {
    final c = MedNames.check('Xylophonix');
    expect(c.name, 'Xylophonix');
    expect(c.status, NameStatus.unknown);
    expect(c.warning, isNotNull);
    expect(MedNames.check('Rx').name, 'Rx');
  });

  test('Cross-check sa OCR text (para sa vision model)', () {
    const ocr = 'SAMPLE FOR DEMO ONLY\nRx Carbocistiene 500mg #15\nSig 1 cap TID';
    expect(MedNames.foundInText('Carbocisteine', ocr), isTrue);
    expect(MedNames.foundInText('Cefixime', ocr), isFalse);
  });

  test('Levenshtein distance', () {
    expect(MedNames.distance('kitten', 'sitting'), 3);
    expect(MedNames.distance('abc', 'abc'), 0);
  });

  test('JSON ng model -> Medicine', () {
    final meds = RxParser.medsFromContent(
      '{"medicines":[{"name":"Amoxicillin","dose":"500mg","qty_per_intake":1,'
      '"times_per_day":3,"bedtime":false,"days":7,"instructions":"pagkatapos kumain","stock":21},'
      '{"name":"Atorvastatin","dose":"20mg","times_per_day":1,"bedtime":true,"days":null},'
      '{"name":"","times_per_day":2}]}',
    );
    expect(meds.length, 2);
    expect(meds[0].timesPerDay, 3);
    expect(meds[0].days, 7);
    expect(meds[0].stock, 21);
    expect(meds[1].times, ['21:00']);
    expect(meds[1].isMaintenance, isTrue);
  });

  test('Walang medicines key -> walang laman', () {
    expect(RxParser.medsFromContent('{}'), isEmpty);
  });
}
