import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/screens/calendar_screen.dart';
import 'package:inom_na/screens/settings_screen.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final clockNow = DateTime(2030, 1, 10, 13); // Thursday, 1:00 PM

/// Synthetic medicines (SAMPLE – FOR DEMO ONLY).
Medicine med(String id, String name, List<String> times, {int? days}) =>
    Medicine(
      id: id,
      name: name,
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: times.length,
      times: times,
      days: days,
      durationConfirmed: true,
      start: DateTime(2030, 1, 8, 7),
    );

Future<void> pumpCalendar(WidgetTester tester, List<Medicine> meds,
    {double width = 393,
    double textScale = 1,
    List<(String, DateTime, bool)>? taps}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 4000 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: CalendarScreen(
      medicines: () => meds,
      clock: () => clockNow,
      onTake: (m, dose, value) async {
        taps?.add((m.id, dose, value));
        m.markTaken(dose, value: value, at: clockNow);
      },
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the week of today with a chronological timeline',
      (tester) async {
    await pumpCalendar(tester, [
      med('a', 'Amoxicillin', ['20:00', '08:00']),
      med('b', 'Losartan', ['12:00']),
    ]);
    expect(find.text('January 2030'), findsOneWidget);
    for (final day in ['6', '7', '8', '9', '10', '11', '12']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('Thursday, January 10'), findsOneWidget);
    final times = tester
        .widgetList<Text>(
            find.textContaining(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')))
        .map((t) => t.data)
        .toList();
    expect(times, ['8:00 AM', '12:00 PM', '8:00 PM']);
    // 8:00 AM is missed (5 h unconfirmed), 12:00 PM overdue, 8:00 PM upcoming.
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.textContaining('consult your pharmacist'), findsWidgets);
  });

  testWidgets('navigates weeks and selects days, including empty days',
      (tester) async {
    await pumpCalendar(tester, [
      med('a', 'Amoxicillin', ['08:00'], days: 3)
    ]);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('Thursday, January 3'), findsOneWidget);
    expect(find.text('No doses scheduled'), findsOneWidget); // Before start.
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.text('Saturday, January 12'), findsOneWidget);
    expect(find.text('No doses scheduled'), findsOneWidget); // After end.
    await tester.tap(find.text('Go to Today'));
    await tester.pumpAndSettle();
    expect(find.text('Thursday, January 10'), findsOneWidget);
  });

  testWidgets('future doses cannot be confirmed in advance', (tester) async {
    await pumpCalendar(tester, [
      med('a', 'Amoxicillin', ['08:00'])
    ]);
    await tester.tap(find.text('11'));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.textContaining('Mark as Taken'), findsNothing);
  });

  testWidgets('a past missed dose can be confirmed late, keeping its time',
      (tester) async {
    final taps = <(String, DateTime, bool)>[];
    final m = med('a', 'Amoxicillin', ['08:00']);
    await pumpCalendar(tester, [m], taps: taps);
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    expect(find.text('Missed'), findsOneWidget);
    await tester.tap(find.text('Mark as Taken (late)'));
    await tester.pumpAndSettle();
    expect(taps.single, ('a', DateTime(2030, 1, 9, 8), true));
    expect(find.text('Taken'), findsOneWidget);
    expect(find.textContaining('Marked taken late'), findsOneWidget);
    expect(m.takenTimeOf(DateTime(2030, 1, 9, 8)), clockNow);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('no overflow on a small phone, text x$textScale',
        (tester) async {
      await pumpCalendar(
          tester,
          [
            med('a', 'Isosorbide Mononitrate Extended-Release Tablet',
                ['08:00', '20:00']),
          ],
          width: 320,
          textScale: textScale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('follow-up setting is disclosed, persisted and adjustable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    expect(Store.followUpDelay, 30); // Default: on, 30 minutes.
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393 * 3, 4000 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()));
    await tester.pump(const Duration(seconds: 6)); // Permission check timeout.
    await tester.pumpAndSettle();
    expect(find.text('Follow-Up Reminders'), findsOneWidget);
    expect(find.textContaining('On by default, 30 minutes'), findsOneWidget);
    await tester.tap(find.text('60 min'));
    await tester.pumpAndSettle();
    expect(Store.followUpDelay, 60);
    await tester.tap(find.text('Follow-Up Reminders'));
    await tester.pumpAndSettle();
    expect(Store.followUpEnabled, isFalse);
    expect(Store.followUpDelay, isNull);
    await Store.init(); // Simulated restart.
    expect(Store.followUpEnabled, isFalse);
    expect(Store.followUpMinutes, 60);
  });
}
