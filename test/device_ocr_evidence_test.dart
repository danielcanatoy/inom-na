// Fixtures are the exact ML Kit text returned ON THE POCO X7 PRO for
// SYNTHETIC rendered prescriptions (tool/probe_images_test.dart + the
// debug-only OcrProbe). No real patient data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/services/rx_parser.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A_table.png: Medicine | Strength columns. Device raw order vs processed.
const tableRaw = 'SAMPLE/ NOT FOR MEDICAL USE\nMedicine\nAmoxicilin\n'
    'Strength\n500 mg\nTake 1 capsule every 8 hours for 7 days.\nQuantity: 21';
const tableArranged = 'SAMPLE/ NOT FOR MEDICAL USE\nMedicine  Strength\n'
    'Amoxicilin  500 mg\nTake 1 capsule every 8 hours for 7 days.\n'
    'Quantity: 21';

// F_header_times.png: clinic header; device raw order interleaves lines.
const headerRaw = 'SAMPLE/ NOT FOR MEDICALUSE\nSunrise Family Clinic\n'
    '123 Mabini St., Quezon City Tel: 8123 4567\nPatient: Test Patient\nRx\n'
    '1. Metformin 500 mg\nAge: 60\n2. Atorvastatin 20 mg\n'
    'Sig: I tab twice daily after meals, ongoing\nDate: 10/10/2026\n'
    'Sig: 1 tab at bedtime, ongoing';
const headerArranged = 'SAMPLE/ NOT FOR MEDICALUSE\nSunrise Family Clinic\n'
    '123 Mabini St., Quezon City Tel: 8123 4567\n'
    'Patient: Test Patient  Age: 60  Date: 10/10/2026\nRx\n'
    '1. Metformin 500 mg\nSig: I tab twice daily after meals, ongoing\n'
    '2. Atorvastatin 20 mg\nSig: 1 tab at bedtime, ongoing';

// C_print.png: ML Kit dropped the final "L" of "5 mL".
const syrupDevice = 'SAMPLE / NOT FOR MEDICAL USE\n'
    'Medicine: Dextromethorphan 15 mg/5 m\nSig: 5 mL as needed for cough';

void main() {
  group('Real device OCR output (synthetic prints)', () {
    test('table headings in raw order are never taken as medicines', () {
      final raw = RxParser.readOnPhone(tableRaw).meds;
      expect(raw.map((m) => m.name), isNot(contains('Strength')));
      expect(raw.map((m) => m.name), isNot(contains('Medicine')));
    });

    test('processed reading order keeps name and strength together', () {
      final m = RxParser.readOnPhone(tableArranged).meds.single;
      expect(m.name, 'Amoxicilin'); // Kept exactly as read (no auto-fix).
      expect(m.dose, '500mg');
      expect(m.intervalHours, 8);
      expect(m.days, 7);
      expect(m.stock, 21);
    });

    test('processed order assigns directions to the right medicine', () {
      final meds = RxParser.readOnPhone(headerArranged).meds;
      expect(meds.map((m) => m.name), ['Metformin', 'Atorvastatin']);
      expect(meds[0].frequencyPerDay, 2);
      expect(meds[0].isMaintenance, isTrue);
      expect(meds[1].frequencyPerDay, 1);
      // In raw order the Metformin directions are misplaced, so its schedule
      // stays unresolved instead of being guessed.
      final raw = RxParser.readOnPhone(headerRaw).meds;
      expect(raw.first.name, 'Metformin');
      expect(raw.first.validationErrors(), isNotEmpty);
    });

    test('"I tab" is read as 1 but flagged for review', () {
      final metformin = RxParser.readOnPhone(headerArranged).meds.first;
      expect(metformin.qtyPerIntake, 1);
      expect(metformin.reviewNotes.join(' '), contains('unclear character'));
    });

    test('a truncated unit is not completed by guessing', () {
      final m = RxParser.readOnPhone(syrupDevice).meds.single;
      expect(m.dose, '15mg'); // Not silently turned into "15mg/5mL".
      expect(m.scheduleKind.name, 'prn');
    });
  });

  group('Scan details view', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 5000 * 3);
      addTearDown(tester.view.reset);
      await tester
          .pumpWidget(MaterialApp(theme: AppTheme.light(), home: screen));
      await tester.pumpAndSettle();
    }

    testWidgets('switches between processed and raw ML Kit text',
        (tester) async {
      await pump(
          tester,
          ConfirmScreen(
              result: RxParser.readOnPhone(tableArranged),
              rawText: tableArranged,
              ocrRaw: tableRaw));
      await tester.tap(find.text('Scan details'));
      await tester.pumpAndSettle();
      Finder shown(String part) => find.byWidgetPredicate(
          (w) => w is SelectableText && (w.data ?? '').contains(part));
      expect(shown('Amoxicilin  500 mg'), findsOneWidget);
      await tester.tap(find.text('Raw ML Kit text'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Medicine\nAmoxicilin\nStrength'),
          findsOneWidget);
      // The q8h medicine still needs its first dose confirmed.
      expect(find.textContaining('1 field(s) still to fix'), findsOneWidget);
    });

    testWidgets('corrected text is re-read and replaces the candidates',
        (tester) async {
      await pump(
          tester,
          ConfirmScreen(
              result: RxParser.readOnPhone(tableArranged),
              rawText: tableArranged,
              ocrRaw: tableRaw));
      await tester.tap(find.text('Scan details'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(
              TextField, 'Correct the text, then read it again'),
          'Amoxicillin 500 mg\n1 capsule every 8 hours for 7 days');
      await tester.tap(find.text('Read Corrected Text'));
      await tester.pumpAndSettle();
      expect(find.text('Amoxicillin 500mg'), findsWidgets);
      expect(find.text('Amoxicilin 500mg'), findsNothing);
      expect(find.text('Verified'), findsNothing); // Must be verified again.
    });
  });
}
