import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/services/med_names.dart';
import 'package:inom_na/services/ocr_layout.dart';
import 'package:inom_na/services/rx_parser.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic text only (SAMPLE / NOT FOR MEDICAL USE).
Medicine one(String text) => RxParser.readOnPhone(text).meds.single;

OcrLine line(String text, double top, double left, [double height = 20]) =>
    OcrLine(text, top: top, bottom: top + height, left: left);

void main() {
  group('OCR layout (reading order)', () {
    test('name and strength printed side by side stay on one line', () {
      // ML Kit may return them as separate blocks, in any order.
      final text = OcrLayout.arrange([
        line('500 mg', 100, 400),
        line('Amoxicillin', 102, 40),
        line('Take 1 capsule every 8 hours', 140, 40),
      ]);
      expect(text, 'Amoxicillin  500 mg\nTake 1 capsule every 8 hours');
      expect(one(text).dose, '500mg');
    });

    test('rows are ordered top to bottom even if blocks are not', () {
      final text = OcrLayout.arrange([
        line('for 7 days', 180, 40),
        line('Losartan 50 mg', 100, 40),
        line('1 tab once daily', 140, 40),
      ]);
      expect(text.split('\n'),
          ['Losartan 50 mg', '1 tab once daily', 'for 7 days']);
    });

    test('empty or degenerate layout yields empty text', () {
      expect(OcrLayout.arrange([]), '');
      expect(OcrLayout.arrange([line('  ', 0, 0)]), '');
    });
  });

  group('Offline reader formats', () {
    test('spacing and case variations around strengths', () {
      for (final text in [
        'Amoxicillin 500mg 1 cap TID',
        'Amoxicillin 500 mg 1 cap TID',
        'AMOXICILLIN 500 MG 1 CAP TID',
        'Medicine: Amoxicillin 500 mg\n1 cap TID',
        'Medicine: Amoxicillin\n500 mg\n1 cap TID',
      ]) {
        final m = one(text);
        expect(m.name.toLowerCase(), 'amoxicillin', reason: text);
        expect(m.dose.toLowerCase(), '500mg', reason: text);
        expect(m.frequencyPerDay, 3, reason: text);
      }
    });

    test('word frequencies do not conflict with "daily"', () {
      expect(one('Cefuroxime 500mg\n1 tab twice daily').frequencyPerDay, 2);
      expect(
          one('Cefuroxime 500mg\n1 tab three times daily').frequencyPerDay, 3);
      expect(one('Cefuroxime 500mg\n1 tab once daily').frequencyPerDay, 1);
      expect(
          one('Cefuroxime 500mg\n1 tab four times a day').frequencyPerDay, 4);
    });

    test('fixed intervals from abbreviations and words', () {
      for (final text in [
        'Paracetamol 500mg 1 tab q6h',
        'Paracetamol 500mg 1 tab every 6 hours',
      ]) {
        final m = one(text);
        expect(m.scheduleKind, ScheduleKind.interval, reason: text);
        expect(m.intervalHours, 6, reason: text);
      }
    });

    test('PRN keeps its wording and never creates scheduled doses', () {
      final m = one('Dextromethorphan 15 mg/5 mL\n5 mL as needed for cough');
      expect(m.scheduleKind, ScheduleKind.prn);
      expect(m.instructions, contains('as needed for cough'));
      expect(m.allDoses(horizon: DateTime(2100)), isEmpty);
    });

    test('quantity and duration labels', () {
      final m = one('Amoxicillin 500 mg\nTake 1 capsule every 8 hours\n'
          'Duration: 7 days\nQuantity: 21');
      expect(m.days, 7);
      expect(m.stock, 21);
      expect(one('Amoxicillin 500 mg 1 cap TID\nDisp: #21').stock, 21);
      expect(one('Losartan 50mg 1 tab OD\nDuration: ongoing').isMaintenance,
          isTrue);
      // "continue" alone is still not treated as maintenance.
      expect(one('Losartan 50mg 1 tab OD continue').durationConfirmed, isFalse);
    });

    test('decimals and units are never changed', () {
      expect(one('Levothyroxine 0.05 mg 1 tab OD').dose, '0.05mg');
      expect(one('Warfarin 2.5 mg 1 tab OD').dose, '2.5mg');
      expect(one('Colchicine 0.5 mg 1 tab OD').dose, '0.5mg');
    });

    test('missing strength keeps the medicine with the field unresolved', () {
      final m = one('Medicine: Cetirizine\nTake 1 tablet once daily');
      expect(m.name, 'Cetirizine');
      expect(m.dose, isEmpty);
      expect(m.validationErrors().join(' '), contains('strength'));
    });

    test('clinic, address, phone and patient lines are not medicines', () {
      final meds = RxParser.readOnPhone(
              'SAMPLE / NOT FOR MEDICAL USE\nSunrise Family Clinic\n'
              '123 Mabini St., Quezon City\nTel: 8123 4567\n'
              'Patient: Test Patient Age: 60\nLosartan 50 mg 1 tab OD')
          .meds;
      expect(meds.map((m) => m.name), ['Losartan']);
    });

    test('OD keeps a caution note; nothing is assumed silently', () {
      expect(one('Losartan 50mg 1 tab OD').reviewNotes.join(' '),
          contains('right eye'));
    });

    test('OCR text whose layout order fails falls back to ML Kit order',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
      final result = await RxParser.parseImage(
          '/x.jpg', 'SAMPLE / NOT FOR MEDICAL USE',
          alternateText: 'Losartan 50 mg\n1 tab once daily');
      expect(result.meds.single.name, 'Losartan');
    });
  });

  group('Name suggestions (never automatic)', () {
    test('a close misread is kept as read with one suggestion', () {
      final m = one('Amoxicilin 500 mg 1 cap TID');
      expect(m.name, 'Amoxicilin'); // Not replaced.
      expect(MedNames.suggestions('Amoxicilin'), ['Amoxicillin']);
      expect(MedNames.reviewNote('Amoxicilin'), contains('Did you mean'));
    });

    test('no suggestion for listed, unrelated or very uncertain names', () {
      expect(MedNames.suggestions('Amoxicillin'), isEmpty);
      expect(MedNames.suggestions('Xylophonix'), isEmpty);
      expect(MedNames.suggestions('Amx'), isEmpty);
    });

    testWidgets('a suggestion must be tapped, and then verified',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 5000 * 3);
      addTearDown(tester.view.reset);
      final result =
          RxParser.readOnPhone('Amoxicilin 500 mg\n1 cap TID x 7 days');
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: ConfirmScreen(result: result, rawText: 'x')));
      await tester.pumpAndSettle();
      expect(find.text('Amoxicilin 500mg'), findsOneWidget);
      expect(find.text("Use 'Amoxicillin'"), findsOneWidget);
      await tester.tap(find.text("Use 'Amoxicillin'"));
      await tester.pumpAndSettle();
      expect(find.text('Amoxicillin 500mg'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
      // The open editor's name field shows the chosen name too.
      expect(find.widgetWithText(TextFormField, 'Amoxicillin'), findsOneWidget);
    });

    testWidgets('Save is disabled while there are no medications',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: ConfirmScreen(
              result: ParseResult([], RxParser.srcOffline), rawText: '')));
      await tester.pumpAndSettle();
      final save = tester.widget<FilledButton>(find.ancestor(
          of: find.text('Save and Set Reminders'),
          matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(save.onPressed, isNull);
      expect(find.text('Add or identify at least one medication to save.'),
          findsOneWidget);
    });
  });
}
