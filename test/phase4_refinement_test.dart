import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/screens/calendar_screen.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/screens/edit_schedule_screen.dart';
import 'package:inom_na/screens/home_screen.dart';
import 'package:inom_na/screens/settings_screen.dart';
import 'package:inom_na/services/rx_parser.dart';
import 'package:inom_na/services/scan_control.dart';
import 'package:inom_na/services/schedule_edit.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:inom_na/ui/scan_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic sample (SAMPLE – FOR DEMO ONLY), no real patient data.
const sample = 'SAMPLE – FOR DEMO ONLY\nAmoxicillin 500mg\n'
    '1 cap q8h x 7 days #21';

Future<void> initStore({Map<String, Object> values = const {}}) async {
  SharedPreferences.setMockInitialValues(values);
  await Store.init();
}

Medicine twice(
        {String id = 'bid', List<String> times = const ['08:00', '20:00']}) =>
    Medicine(
      id: id,
      name: 'Losartan',
      dose: '50mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: times.length,
      times: [...times],
      durationConfirmed: true,
      start: DateTime(2030, 1, 1, 7),
    );

class Host {
  Object? result;
  bool returned = false;
}

Future<Host> open(WidgetTester tester, Widget screen,
    {double width = 393}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 5000 * 3);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phone-only processing (no laptop)', () {
    setUp(() => initStore());

    test('typed sample is read on the phone without contacting the laptop',
        () async {
      expect(Store.processingMode, ProcessingMode.phoneOnly);
      final watch = Stopwatch()..start();
      final result = await RxParser.parse(sample);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      final m = result.meds.single;
      expect(m.name, 'Amoxicillin');
      expect(m.dose, '500mg');
      expect(m.scheduleKind, ScheduleKind.interval);
      expect(m.intervalHours, 8);
      expect(m.days, 7);
      expect(m.stock, 21);
      expect(result.source, RxParser.srcOffline);
      expect(result.diagnostics!.usedLaptop, isFalse);
      expect(result.diagnostics!.found, 1);
    });

    test('scan mode hands OCR text to the phone reader', () async {
      // The photo itself is not needed in Phone Only mode.
      final result = await RxParser.parseImage('/no/such/photo.jpg', sample);
      expect(result.meds.single.name, 'Amoxicillin');
      expect(result.diagnostics!.textLength, sample.trim().length);
      expect(result.source, RxParser.srcOffline);
    });

    test('common phone-OCR misreads still produce a medicine to review', () {
      for (final text in [
        'Amoxicillin 5OOmg\n1 cap q8h x 7 days #21',
        'Amoxicillin 500 rng\n1 cap q8h x 7 days #21',
        'Amoxicillin (Amoxil) 500mg\n1 cap q8h x 7 days #21',
        'Amoxicillin\n500mg\n1 cap q8h x 7 days #21',
      ]) {
        final m = RxParser.readOnPhone(text).meds.single;
        expect(m.name, 'Amoxicillin', reason: text);
        expect(m.dose, '500mg', reason: text);
        expect(m.intervalHours, 8, reason: text);
      }
      final unclear =
          RxParser.readOnPhone('Amoxicillin 5OOmg\n1 cap q8h').meds.single;
      expect(unclear.reviewNotes.join(' '), contains('unclear in the scan'));
      final unlisted =
          RxParser.readOnPhone('Cefaclor\n250 mg\n1 cap TID').meds.single;
      expect(unlisted.name, 'Cefaclor');
      expect(unlisted.dose, '250mg');
    });

    test('header lines are not mistaken for medicines', () {
      final meds = RxParser.readOnPhone(
              'Patient: Test Person\nDate: Jan 10\nAmoxicillin 500mg\n1 cap TID')
          .meds;
      expect(meds.map((m) => m.name), ['Amoxicillin']);
    });

    test('zero, empty and failed OCR are reported separately', () async {
      final none = await RxParser.parseImage(
          '/x.jpg', 'SAMPLE – FOR DEMO ONLY\nThank you');
      expect(none.meds, isEmpty);
      expect(none.diagnostics!.textLength, greaterThan(0));
      final empty = await RxParser.parseImage('/x.jpg', '');
      expect(empty.note, contains('No text was found'));
      final failed = await RxParser.parseImage('/x.jpg', '', ocrFailed: true);
      expect(failed.note, contains('Text recognition failed'));
      expect(failed.diagnostics!.ocrFailed, isTrue);
    });

    test('enhanced mode falls back honestly when Ollama is unreachable',
        () async {
      await Store.setProcessingMode(ProcessingMode.enhanced);
      final result = await RxParser.parse(sample);
      expect(result.meds.single.name, 'Amoxicillin');
      expect(result.source, RxParser.srcOffline); // No false AI claim.
      expect(result.note, contains('could not be reached'));
      await Store.setProcessingMode(ProcessingMode.phoneOnly);
      expect(Store.processingMode, ProcessingMode.phoneOnly);
    });
  });

  group('Scan cancellation', () {
    setUp(() => initStore());

    test('a cancelled scan never returns a result', () async {
      final control = ScanControl()..cancel();
      await expectLater(RxParser.parse(sample, control: control),
          throwsA(isA<ScanCancelled>()));
    });

    test('cancel while contacting Ollama aborts and discards', () async {
      await Store.setProcessingMode(ProcessingMode.enhanced);
      late final ScanControl control;
      control = ScanControl(onStage: (stage) {
        if (stage.contains('Connecting')) control.cancel();
      });
      await expectLater(RxParser.parse(sample, control: control),
          throwsA(isA<ScanCancelled>()));
    });

    test('a late result after cancelling during reading is discarded',
        () async {
      late final ScanControl control;
      control = ScanControl(onStage: (stage) {
        if (stage.contains('rule-based')) control.cancel();
      });
      await expectLater(RxParser.parse(sample, control: control),
          throwsA(isA<ScanCancelled>()));
    });

    testWidgets('progress dialog shows stage, elapsed time and Cancel Scan',
        (tester) async {
      final stage = ValueNotifier<String>('Reading text on this phone');
      var cancelled = false;
      await tester.pumpWidget(MaterialApp(
          home: ScanProgressDialog(
              title: 'Reading your prescription',
              stage: stage,
              onCancel: () => cancelled = true)));
      expect(find.text('Reading text on this phone'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Elapsed: 2 s'), findsOneWidget);
      stage.value = "Interpreting with this phone's rule-based reader";
      await tester.pump();
      expect(find.textContaining('rule-based reader'), findsOneWidget);
      await tester.tap(find.text('Cancel Scan'));
      expect(cancelled, isTrue);
      await tester.pumpWidget(const SizedBox()); // Stops the timer.
    });
  });

  group('Simplified review', () {
    setUp(() => initStore());

    testWidgets('several medicines start compact with matching summaries',
        (tester) async {
      final result =
          RxParser.readOnPhone('$sample\nLosartan 50mg\n1 tab OD maintenance');
      await open(tester, ConfirmScreen(result: result, rawText: sample));
      expect(find.text('Amoxicillin 500mg'), findsOneWidget);
      expect(find.text('Every 8 hours'), findsOneWidget);
      expect(find.text('For 7 days'), findsOneWidget);
      expect(find.text('Once a day'), findsOneWidget);
      // Details are hidden until requested.
      expect(find.text('Strength / dose'), findsNothing);
      await tapText(tester, 'Edit Details');
      expect(find.text('Strength / dose'), findsOneWidget);
      expect(find.text('0 of 2 verified. Verify every medication to save.'),
          findsOneWidget);
    });

    testWidgets('verification needs explicit confirmation in a dialog',
        (tester) async {
      final result =
          RxParser.readOnPhone('Losartan 50mg\n1 tab OD maintenance');
      await open(tester, ConfirmScreen(result: result, rawText: 'x'));
      await tapText(tester, 'Verify Medication');
      expect(find.text('Verify Losartan 50mg?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(find.text('Verified'), findsNothing);
      await tapText(tester, 'Verify Medication');
      await tapText(tester, "I've Verified This");
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('no medicine found: recognized text can be corrected and read',
        (tester) async {
      // Unreadable even after OCR clean-up (no unit, unknown name).
      const ocr = 'SAMPLE – FOR DEMO ONLY\nAmxcl 5OO';
      final result = RxParser.readOnPhone(ocr);
      expect(result.meds, isEmpty);
      final host =
          await open(tester, ConfirmScreen(result: result, rawText: ocr));
      expect(find.text('No medicine identified yet'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(
              TextField, 'Recognized text (you can correct it)'),
          sample);
      await tapText(tester, 'Read Text Again');
      expect(find.text('Amoxicillin 500mg'), findsOneWidget);
      expect(find.text('Verified'), findsNothing); // Still needs review.
      await tapText(tester, 'Save and Set Reminders');
      expect(host.returned, isFalse);
    });

    testWidgets('no text: retake and type options are offered', (tester) async {
      final host = await open(
          tester,
          ConfirmScreen(
              result: ParseResult([], RxParser.srcOffline, 'No text was found'),
              rawText: ''));
      expect(find.text('No text found'), findsOneWidget);
      expect(find.text('Add Medicine Manually'), findsOneWidget);
      await tapText(tester, 'Retake Photo');
      expect(host.result, ScanRetry.photo);
    });
  });

  group('Today rule (exact daily dose count)', () {
    final now = DateTime(2030, 1, 10, 10);

    test('once daily: a passed dose blocks an extra dose today', () {
      final od = twice(times: ['08:00']);
      expect(ScheduleEdit.todayBlockReason(od, ['21:00'], now),
          contains('2 doses instead of 1'));
      expect(
          ScheduleEdit.todayBlockReason(
              od, ['09:00'], DateTime(2030, 1, 10, 7)),
          isNull);
    });

    test('BID: moving the remaining dose today is allowed', () {
      final bid = twice()..markTaken(DateTime(2030, 1, 10, 8));
      expect(
          ScheduleEdit.todayBlockReason(bid, ['09:00', '21:00'], now), isNull);
      expect(ScheduleEdit.todayBlockReason(bid, ['11:00', '21:00'], now),
          contains('3 doses instead of 2'));
    });

    test('TID: a change that would drop a dose today waits for tomorrow', () {
      final tid = twice(times: ['08:00', '14:00', '20:00']);
      final afternoon = DateTime(2030, 1, 10, 15);
      expect(
          ScheduleEdit.todayBlockReason(
              tid, ['08:00', '12:00', '16:00'], afternoon),
          isNull);
      expect(
          ScheduleEdit.todayBlockReason(
              tid, ['07:00', '11:00', '13:00'], afternoon),
          contains('2 doses instead of 3'));
    });

    test('a later dose already taken blocks today', () {
      final bid = twice()..markTaken(DateTime(2030, 1, 10, 20));
      expect(ScheduleEdit.todayBlockReason(bid, ['09:00', '21:00'], now),
          contains('already marked taken'));
    });

    test('applying today keeps past doses and never adds a dose', () {
      final bid = twice()..markTaken(DateTime(2030, 1, 10, 8));
      final effective = ScheduleEdit.clockEffectiveFrom(bid, now, today: true);
      final draft = ScheduleEdit.draftOf(bid)
        ..times = ['09:00', '21:00']
        ..start = effective;
      final revised = bid.withScheduleFrom(draft, effective);
      expect(
          revised.allDoses(
              horizon: DateTime(2030, 1, 10, 23, 59),
              from: DateTime(2030, 1, 10)),
          [DateTime(2030, 1, 10, 8), DateTime(2030, 1, 10, 21)]);
      expect(revised.isTaken(DateTime(2030, 1, 10, 8)), isTrue);
    });
  });

  group('Edit Medication', () {
    setUp(() => initStore());

    testWidgets('corrections need verification and keep identity and history',
        (tester) async {
      final saved = twice()
        ..markTaken(DateTime(2030, 1, 10, 8), at: DateTime(2030, 1, 10, 8, 2))
        ..sourceText = 'SAMPLE – FOR DEMO ONLY\nLosartan 50mg BID'
        ..instructions = '1 tab BID';
      final host = await open(
          tester,
          EditScheduleScreen(
              medicine: saved,
              correctPrescription: true,
              clock: () => DateTime(2030, 1, 10, 10)));
      expect(find.text('Edit Medication'), findsOneWidget);
      expect(find.text('Original prescription text (kept as read)'),
          findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Medication name'), 'Losartan K');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Strength / dose'), '100mg');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Directions (as interpreted)'),
          '1 tablet twice daily');
      await tester.pumpAndSettle();
      await tapText(tester, 'Save Changes');
      expect(find.text('Save schedule changes?'), findsNothing); // Unverified.
      await tapText(tester, "I've Verified This");
      await tapText(tester, 'Save Changes');
      await tapText(tester, 'Confirm Changes');
      final revised = host.result! as Medicine;
      expect(revised.id, saved.id);
      expect(revised.name, 'Losartan K');
      expect(revised.dose, '100mg');
      expect(revised.instructions, '1 tablet twice daily');
      expect(revised.sourceText, saved.sourceText); // Evidence unchanged.
      expect(revised.takenTimeOf(DateTime(2030, 1, 10, 8)),
          DateTime(2030, 1, 10, 8, 2));
    });

    testWidgets('cancel discards all corrections', (tester) async {
      final saved = twice();
      final before = saved.toJson().toString();
      final host = await open(
          tester,
          EditScheduleScreen(
              medicine: saved,
              correctPrescription: true,
              clock: () => DateTime(2030, 1, 10, 10)));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Medication name'), 'Other');
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');
      await tapText(tester, 'Discard');
      expect(host.result, isNull);
      expect(saved.toJson().toString(), before);
    });

    test('a corrected frequency keeps the course end, not the dose count', () {
      final course = twice()
        ..days = 7
        ..start = DateTime(2030, 1, 8, 7);
      final draft = ScheduleEdit.draftOf(course)
        ..frequencyPerDay = 3
        ..times = ['08:00', '14:00', '20:00']
        ..start = DateTime(2030, 1, 11);
      final revised = course.withScheduleFrom(draft, DateTime(2030, 1, 11));
      expect(revised.scheduleEnd, course.scheduleEnd);
      // 3 days at BID before the change + 4 days at TID after it.
      expect(revised.totalDoses, 3 * 2 + 4 * 3);
    });
  });

  group('Navigation and calendar', () {
    testWidgets('bottom tabs switch screens and back returns to Home',
        (tester) async {
      await initStore(values: {
        'meds': jsonEncode([twice().toJson()]),
      });
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 2400 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(), home: const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text("Today's Medication Schedule"), findsOneWidget);
      await tester.tap(find.text('Medications'));
      await tester.pumpAndSettle();
      expect(find.text('My Medications'), findsOneWidget);
      expect(find.text('Scan Prescription'), findsNothing); // Home only.
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Previous week'), findsOneWidget);
      // Android back from a tab returns to Home instead of leaving the app.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("Today's Medication Schedule"), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('calendar opens on today and can jump to a date',
        (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 2400 * 3);
      addTearDown(tester.view.reset);
      final meds = [twice()];
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: CalendarScreen(
              medicines: () => meds,
              clock: () => DateTime(2030, 1, 10, 13),
              onTake: (_, __, ___) async {})));
      await tester.pumpAndSettle();
      expect(find.text('Thursday, January 10'), findsOneWidget);
      await tester.tap(find.text('January 2030'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Sunday, January 20'), findsOneWidget);
      await tester.tap(find.text('Go to Today'));
      await tester.pumpAndSettle();
      expect(find.text('Thursday, January 10'), findsOneWidget);
      expect(meds.single.start, DateTime(2030, 1, 1, 7)); // Unchanged.
    });

    testWidgets('settings: processing mode is Phone Only by default',
        (tester) async {
      await initStore();
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 5000 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.textContaining('Phone Only (default)'), findsOneWidget);
      await tester.tap(find.text('Enhanced AI'));
      await tester.pumpAndSettle();
      expect(Store.processingMode, ProcessingMode.enhanced);
      expect(find.textContaining("uses this phone's rule-based reader"),
          findsOneWidget);
    });
  });

  group('Small screens at large text', () {
    Future<void> pumpAt(WidgetTester tester, Widget home) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(320 * 3, 6000 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: home,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('compact review cards fit', (tester) async {
      await initStore();
      final result = RxParser.readOnPhone(
          '$sample\nIsosorbide Mononitrate 30mg\n1 tab OD x 30 days');
      await pumpAt(tester, ConfirmScreen(result: result, rawText: sample));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Medications tab fits', (tester) async {
      await initStore(values: {
        'meds': jsonEncode([twice().toJson()]),
      });
      await pumpAt(tester, const HomeScreen());
      await tester.tap(find.text('Medications'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
