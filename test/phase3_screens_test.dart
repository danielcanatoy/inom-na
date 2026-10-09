import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/models/routine.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/screens/edit_schedule_screen.dart';
import 'package:inom_na/screens/home_screen.dart';
import 'package:inom_na/screens/routine_screen.dart';
import 'package:inom_na/services/rx_parser.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final clockNow = DateTime(2030, 1, 10, 10); // 10:00 AM

/// Synthetic medicine (SAMPLE – FOR DEMO ONLY).
Medicine twiceDaily({
  ScheduleKind kind = ScheduleKind.daily,
  List<String> times = const ['08:00', '20:00'],
  RoutineLink? link,
}) =>
    Medicine(
      id: 'sample',
      name: 'Losartan',
      dose: '50mg',
      qtyPerIntake: 1,
      scheduleKind: kind,
      frequencyPerDay: times.length,
      times: [...times],
      durationConfirmed: true,
      start: DateTime(2030, 1, 1, 7),
      routineLink: link,
    );

Future<void> initStore(
    {DailyRoutine? routine, List<Medicine> meds = const []}) async {
  SharedPreferences.setMockInitialValues({
    if (routine != null) 'daily_routine_v1': jsonEncode(routine.toJson()),
    if (meds.isNotEmpty)
      'meds': jsonEncode(meds.map((m) => m.toJson()).toList()),
  });
  await Store.init();
}

/// Opens [screen] from a host page and records what it returns.
class Host {
  Object? result;
  bool returned = false;
}

Future<Host> open(WidgetTester tester, Widget screen,
    {double width = 393, double textScale = 1, double height = 2400}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, height * 3);
  addTearDown(tester.view.reset);
  final host = Host();
  await tester.pumpWidget(const SizedBox()); // Fresh navigator each time.
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
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

/// Enters a time in the Material time picker using its keyboard mode.
Future<void> enterTime(WidgetTester tester, int hour, int minute,
    {bool pm = false}) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
      of: find.byType(Dialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), '$hour');
  await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await tester.tap(find.text(pm ? 'PM' : 'AM'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Taps "Verify Medication" and confirms the dialog when it appears.
Future<void> verifyMedication(WidgetTester tester) async {
  final button = find.text('Verify Medication').last;
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pumpAndSettle();
  final confirm = find.descendant(
      of: find.byType(AlertDialog), matching: find.text("I've Verified This"));
  if (confirm.evaluate().isNotEmpty) {
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('My Daily Routine', () {
    testWidgets('first save stores the routine; cancel saves nothing',
        (tester) async {
      await initStore();
      var host = await open(tester, const RoutineScreen(medicines: []));
      expect(find.text('My Daily Routine'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(host.returned, isTrue);
      expect(host.result, isNull);
      expect(Store.routine, isNull);

      host = await open(tester, const RoutineScreen(medicines: []));
      await tapText(tester, 'Save Changes');
      expect(host.result, isA<RoutineResult>());
      expect((host.result! as RoutineResult).updated, isEmpty);
      expect(Store.routine, DailyRoutine.pickerDefaults);
    });

    testWidgets(
        'a routine change proposes updates and applies only on '
        'confirmation', (tester) async {
      final linked = twiceDaily(
          times: ['06:00', '21:00'],
          link: const RoutineLink(mode: RoutineMode.spread));
      await initStore(routine: DailyRoutine.pickerDefaults, meds: [linked]);
      Future<Host> changeWake() async {
        final host = await open(
            tester, RoutineScreen(medicines: [linked], clock: () => clockNow));
        await tapText(tester, 'Wake-up Time');
        await enterTime(tester, 6, 30);
        await tapText(tester, 'Save Changes');
        expect(find.text('Your daily routine has changed'), findsOneWidget);
        expect(
            find.textContaining('Previous: 6:00 AM, 9:00 PM'), findsOneWidget);
        expect(
            find.textContaining('Proposed: 6:30 AM, 9:00 PM'), findsOneWidget);
        return host;
      }

      // Cancel: nothing saved, still editing.
      var host = await changeWake();
      await tapText(tester, 'Cancel');
      expect(host.returned, isFalse);
      expect(Store.routine, DailyRoutine.pickerDefaults);

      // Keep current schedules: routine saved, no medicine changed.
      host = await changeWake();
      await tapText(tester, 'Keep Current Schedules');
      expect((host.result! as RoutineResult).updated, isEmpty);
      expect(Store.routine![RoutineEvent.wake], '06:30');

      // Apply: the confirmed medicine changes from the next safe day.
      await initStore(routine: DailyRoutine.pickerDefaults, meds: [linked]);
      host = await changeWake();
      await tapText(tester, 'Apply Selected Changes');
      final updated = (host.result! as RoutineResult).updated.single;
      expect(updated.id, linked.id);
      expect(updated.times, ['06:30', '21:00']);
      expect(updated.revisions, hasLength(1));
      expect(linked.times, ['06:00', '21:00']);
    });
  });

  group('Edit Schedule', () {
    testWidgets('cancel without changes returns nothing', (tester) async {
      await initStore();
      final saved = twiceDaily();
      final host = await open(
          tester, EditScheduleScreen(medicine: saved, clock: () => clockNow));
      expect(find.text('Original directions'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(host.returned, isTrue);
      expect(host.result, isNull);
    });

    testWidgets('a changed time is previewed, confirmed, and keeps history',
        (tester) async {
      await initStore();
      final saved = twiceDaily()..markTaken(DateTime(2030, 1, 10, 8));
      final host = await open(
          tester, EditScheduleScreen(medicine: saved, clock: () => clockNow));
      await tapText(tester, '8:00 AM');
      await enterTime(tester, 9, 0);
      // 8:00 AM (taken) stays; today's remaining dose follows the new
      // times, so today still has exactly two doses.
      expect(find.textContaining('remaining doses follow the new times'),
          findsOneWidget);
      expect(find.text('Upcoming Reminders'), findsOneWidget);
      await tapText(tester, 'Save Changes');
      expect(find.text('Save schedule changes?'), findsOneWidget);
      expect(find.textContaining('New: 9:00 AM, 8:00 PM'), findsOneWidget);

      // Go Back keeps editing; nothing returned yet.
      await tapText(tester, 'Go Back');
      expect(host.returned, isFalse);

      await tapText(tester, 'Save Changes');
      await tapText(tester, 'Confirm Changes');
      final revised = host.result! as Medicine;
      expect(revised.id, saved.id);
      expect(revised.times, ['09:00', '20:00']);
      expect(revised.start, clockNow); // Applies from now, today.
      expect(revised.isTaken(DateTime(2030, 1, 10, 8)), isTrue);
      expect(
          revised.allDoses(
              horizon: DateTime(2030, 1, 10, 23, 59),
              from: DateTime(2030, 1, 10)),
          [DateTime(2030, 1, 10, 8), DateTime(2030, 1, 10, 20)]);
      expect(revised.taken, saved.taken);
      expect(revised.revisions, hasLength(1));
      expect(revised.routineLink, isNull); // Customized times.
      expect(saved.times, ['08:00', '20:00']);
    });

    testWidgets('discarding an edit returns nothing and changes nothing',
        (tester) async {
      await initStore();
      final saved = twiceDaily();
      final before = saved.toJson().toString();
      final host = await open(
          tester, EditScheduleScreen(medicine: saved, clock: () => clockNow));
      await tapText(tester, '8:00 PM');
      await enterTime(tester, 9, 0, pm: true);
      await tapText(tester, 'Cancel');
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapText(tester, 'Discard');
      expect(host.returned, isTrue);
      expect(host.result, isNull);
      expect(saved.toJson().toString(), before);
    });

    testWidgets('prescribed times are locked unless corrected and verified',
        (tester) async {
      await initStore();
      final saved = twiceDaily(kind: ScheduleKind.explicit);
      await open(
          tester, EditScheduleScreen(medicine: saved, clock: () => clockNow));
      expect(find.text('Prescribed Time'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
      await tapText(tester, 'Correct prescription details');
      expect(find.byType(InputChip), findsNWidgets(2));
      await tapText(tester, '8:00 AM');
      await enterTime(tester, 9, 0);
      await tapText(tester, 'Save Changes');
      // Corrections must be verified before they can be saved.
      expect(find.text('Save schedule changes?'), findsNothing);
      expect(find.textContaining('Confirm that you checked the corrected'),
          findsWidgets);
    });

    for (final textScale in [1.0, 2.0]) {
      testWidgets('no overflow on a small phone, text x$textScale',
          (tester) async {
        await initStore(routine: DailyRoutine.pickerDefaults);
        await open(tester,
            EditScheduleScreen(medicine: twiceDaily(), clock: () => clockNow),
            width: 320, textScale: textScale, height: 6000);
        expect(tester.takeException(), isNull);
        await tapText(tester, 'Correct prescription details');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('routine screen fits a small phone at large text',
      (tester) async {
    await initStore();
    await open(tester, const RoutineScreen(medicines: []),
        width: 320, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review screen applies routine suggestions only on request',
      (tester) async {
    await initStore(routine: DailyRoutine.pickerDefaults);
    final parsed = twiceDaily()
      ..id = 'new'
      ..start = DateTime(2030, 1, 10, 9);
    final host = await open(
        tester,
        ConfirmScreen(
            result: ParseResult([parsed], RxParser.srcOffline),
            rawText: 'SAMPLE – FOR DEMO ONLY'));
    expect(find.text('Suggested Schedule'), findsOneWidget);
    expect(find.textContaining('Suggested times: 6:00 AM, 9:00 PM'),
        findsOneWidget);
    // Nothing changes until the user asks.
    expect(find.text('8:00 AM'), findsOneWidget);
    await tapText(tester, 'Use These Times');
    expect(find.text('6:00 AM'), findsWidgets);
    expect(find.text('Based on My Daily Routine'), findsWidgets);
    await verifyMedication(tester);
    await tapText(tester, 'Save and Set Reminders');
    final saved = (host.result! as List<Medicine>).single;
    expect(saved.times, ['06:00', '21:00']);
    expect(saved.routineLink?.mode, RoutineMode.spread);
  });

  testWidgets('home shows the routine prompt and Edit Schedule on cards',
      (tester) async {
    await initStore(meds: [twiceDaily()]);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393 * 3, 4000 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const HomeScreen()));
    await tester.pumpAndSettle();
    // Saved medicines and the routine prompt live on the Medications tab.
    await tester.tap(find.text('Medications'));
    await tester.pumpAndSettle();
    expect(find.text('Set Up My Daily Routine'), findsOneWidget);
    expect(find.text('Edit Schedule'), findsOneWidget);
    expect(find.text('Custom times'), findsOneWidget);
  });
}
