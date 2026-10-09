import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/models/routine.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/screens/edit_schedule_screen.dart';
import 'package:inom_na/screens/medication_details_screen.dart';
import 'package:inom_na/services/rx_parser.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/services/strength_check.dart';
import 'package:inom_na/ui/app_strings.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic medicines (SAMPLE – FOR DEMO ONLY).
Medicine candidate({
  String id = 'm1',
  String name = 'Losartan',
  String dose = '50mg',
  ScheduleKind kind = ScheduleKind.daily,
  List<String> times = const ['08:00'],
  int? interval,
  int? days = 7,
}) =>
    Medicine(
      id: id,
      name: name,
      dose: dose,
      qtyPerIntake: 1,
      scheduleKind: kind,
      frequencyPerDay: kind == ScheduleKind.daily ? times.length : null,
      intervalHours: interval,
      times: [...times],
      days: days,
      durationConfirmed: true,
      start: DateTime(2026, 10, 9, 8),
    );

class Host {
  Object? result;
  bool returned = false;
}

Future<Host> open(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 5000 * 3);
  addTearDown(tester.view.reset);
  final host = Host();
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              host.result = await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => screen));
              host.returned = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return host;
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Widget review(List<Medicine> meds,
        {String raw = 'SAMPLE – FOR DEMO ONLY',
        Map<String, String> warnings = const {}}) =>
    ConfirmScreen(
        result: ParseResult(meds, RxParser.srcOffline, null, warnings),
        rawText: raw);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  group('Strength check', () {
    test('flags strengths above usual single-tablet strengths', () {
      expect(StrengthCheck.concerns('Levothyroxine', '500 mcg').single,
          contains('up to 300 mcg'));
      expect(StrengthCheck.concerns('Levothyroxine', '100mcg'), isEmpty);
      expect(StrengthCheck.concerns('Amlodipine', '100 mg'), isNotEmpty);
      expect(StrengthCheck.concerns('Amlodipine', '10 mg'), isEmpty);
    });

    test('flags unusually large strengths for other medicines', () {
      expect(StrengthCheck.concerns('Paracetamol', '5000mg'), isNotEmpty);
      expect(StrengthCheck.concerns('Paracetamol', '500mg'), isEmpty);
      expect(StrengthCheck.concerns('Cefuroxime', '2 g'), isNotEmpty);
      expect(StrengthCheck.concerns('Salbutamol', '100 mcg'), isEmpty);
      expect(StrengthCheck.concerns('Unknownmed', ''), isEmpty);
    });

    test('flags a strength that differs from the prescription text', () {
      const raw = 'SAMPLE – FOR DEMO ONLY\nLosartan 50mg 1 tab OD';
      expect(
          StrengthCheck.concerns('Losartan', '500mg', sourceText: raw)
              .join(' '),
          allOf(contains('shows 50mg'), contains('up to 100 mg')));
      expect(StrengthCheck.concerns('Losartan', '50 mg', sourceText: raw),
          isEmpty);
      expect(
          StrengthCheck.concerns('Warfarin', '5 mg',
              sourceText: 'Warfarin 0.5mg'),
          isNotEmpty);
    });
  });

  test('last dose describes the end of a course in plain terms', () {
    final course = candidate(times: ['08:00', '20:00'], days: 3);
    expect(course.lastDose, DateTime(2026, 10, 11, 20));
    expect(candidate(days: null).lastDose, isNull); // Ongoing.
  });

  group('Review Prescription', () {
    testWidgets('interval first dose is provisional until the user chooses',
        (tester) async {
      final med =
          candidate(kind: ScheduleKind.interval, interval: 8, times: ['08:00']);
      final host = await open(tester, review([med]));
      expect(find.text('Not confirmed'), findsOneWidget);
      expect(find.text('Choose First Dose'), findsOneWidget);
      expect(find.text('Add Time'), findsNothing);
      expect(find.text('Add Reminder Time'), findsNothing);
      expect(find.text('Schedule preview (not confirmed yet)'), findsOneWidget);
      // Verifying is blocked while the first dose is only a suggestion.
      await tapText(tester, AppStrings.iveVerifiedThis);
      expect(find.text(AppStrings.verified), findsNothing);

      await tapText(tester, 'First dose at 8:00 AM');
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Change First Dose'), findsOneWidget);
      expect(
          find.text('Every 8 hours: 8:00 AM, 4:00 PM, 12:00 AM, '
              'repeating daily.'),
          findsOneWidget);
      await tapText(tester, AppStrings.iveVerifiedThis);
      expect(find.text('Schedule preview'), findsOneWidget);
      await tapText(tester, AppStrings.saveAndSetReminders);
      final saved = (host.result! as List<Medicine>).single;
      expect(saved.intervalHours, 8);
      expect(saved.start.hour, 8);
      final doses = saved.allDoses(
          horizon: saved.start.add(const Duration(hours: 24)),
          from: saved.start);
      for (var i = 1; i < doses.length; i++) {
        expect(doses[i].difference(doses[i - 1]), const Duration(hours: 8));
      }
    });

    testWidgets('an unusual strength blocks verification until compared',
        (tester) async {
      final med = candidate(name: 'Levothyroxine', dose: '500 mcg');
      final host = await open(tester, review([med]));
      expect(find.text('Check the strength'), findsOneWidget);
      await tapText(tester, AppStrings.iveVerifiedThis);
      expect(find.text(AppStrings.verified), findsNothing);
      await tapText(tester, AppStrings.saveAndSetReminders);
      expect(host.returned, isFalse);

      await tapText(tester, 'I compared this strength');
      await tapText(tester, AppStrings.iveVerifiedThis);
      expect(find.text(AppStrings.verified), findsOneWidget);
      await tapText(tester, AppStrings.saveAndSetReminders);
      // Never substituted: the strength is saved exactly as entered.
      expect((host.result! as List<Medicine>).single.dose, '500 mcg');
    });

    testWidgets('editing a compared strength requires comparing it again',
        (tester) async {
      final med = candidate(name: 'Levothyroxine', dose: '500 mcg');
      await open(tester, review([med]));
      await tapText(tester, 'I compared this strength');
      final field = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Strength / dose');
      await tester.enterText(field, '600 mcg');
      await tester.pumpAndSettle();
      final box = tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, 'I compared this strength'));
      expect(box.value, isFalse);
    });

    testWidgets('save is blocked until every medication is verified',
        (tester) async {
      final host =
          await open(tester, review([candidate(id: 'a'), candidate(id: 'b')]));
      expect(find.text('0 of 2 verified. Verify every medication to save.'),
          findsOneWidget);
      await tapText(tester, AppStrings.iveVerifiedThis);
      expect(find.text('1 of 2 verified. Verify every medication to save.'),
          findsOneWidget);
      await tapText(tester, AppStrings.saveAndSetReminders);
      expect(host.returned, isFalse);
    });

    testWidgets('repeated and outdated warnings are not shown twice',
        (tester) async {
      final med = candidate(name: '');
      final initialError = med.validationErrors().first;
      await open(
          tester,
          review([
            med
          ], warnings: {
            med.id: [
              RxParser.genericReviewNote,
              initialError,
              'Mismatch: the written times do not match the frequency.',
            ].join('\n'),
          }));
      expect(find.text('Check these details'), findsOneWidget);
      expect(
          find.textContaining('A recognized name does not mean'), findsNothing);
      expect(
          find.text('Mismatch: the written times do not match the frequency.'),
          findsOneWidget);
      // The current error is listed once, under "Fix before verifying".
      expect(find.text(initialError), findsOneWidget);
    });

    testWidgets('duration choices are described in plain terms',
        (tester) async {
      await open(
          tester,
          review([
            candidate(times: ['08:00', '20:00'], days: 3)
          ]));
      expect(find.text('For a number of days'), findsOneWidget);
      expect(find.textContaining('Last dose: Oct 11, 2026 · 8:00 PM'),
          findsOneWidget);
      await open(tester, review([candidate(days: null)]));
      expect(find.text('Ongoing, no end date (maintenance)'), findsOneWidget);
      expect(
          find.textContaining('Reminders continue every day'), findsOneWidget);
    });
  });

  group('Edit Schedule', () {
    testWidgets('interval next dose shows whether the user chose it',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'daily_routine_v1': jsonEncode(DailyRoutine.pickerDefaults.toJson()),
      });
      await Store.init();
      final saved = Medicine(
        id: 'q8h',
        name: 'Amoxicillin',
        dose: '500mg',
        qtyPerIntake: 1,
        scheduleKind: ScheduleKind.interval,
        intervalHours: 8,
        durationConfirmed: true,
        start: DateTime(2030, 1, 10, 6),
      );
      await open(
          tester,
          EditScheduleScreen(
              medicine: saved, clock: () => DateTime(2030, 1, 10, 10)));
      expect(find.text('Unchanged'), findsOneWidget);
      expect(find.text('Jan 10, 2030 · 2:00 PM'), findsOneWidget);
      expect(find.text('Add Time'), findsNothing);
      await tapText(tester, 'Use my wake-up time (6:00 AM)');
      expect(find.text('You chose this'), findsOneWidget);
      expect(find.text('Jan 11, 2030 · 6:00 AM'), findsOneWidget);
    });

    testWidgets('details show the last dose instead of an exclusive end',
        (tester) async {
      await open(
          tester,
          MedicationDetailsScreen(
              medicine: candidate(times: ['08:00', '20:00'], days: 3)));
      expect(find.text('Last dose'), findsOneWidget);
      expect(find.text('Oct 11, 2026 · 8:00 PM'), findsOneWidget);
      expect(find.textContaining('No more doses from'), findsNothing);
      expect(find.text('Check the strength'), findsNothing);
    });

    testWidgets('details flag an unusual saved strength without changing it',
        (tester) async {
      final saved = candidate(name: 'Levothyroxine', dose: '500 mcg');
      await open(tester, MedicationDetailsScreen(medicine: saved));
      expect(find.text('Check the strength'), findsOneWidget);
      expect(find.textContaining('up to 300 mcg'), findsOneWidget);
      expect(saved.dose, '500 mcg');
    });
  });
}
