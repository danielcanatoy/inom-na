import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/screens/home_screen.dart';
import 'package:inom_na/screens/settings_screen.dart';
import 'package:inom_na/services/store.dart';
import 'package:inom_na/ui/app_theme.dart';
import 'package:inom_na/ui/brand.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic medicine (SAMPLE – FOR DEMO ONLY) with two doses every day.
Medicine twiceDaily({String name = 'Losartan'}) {
  final now = DateTime.now();
  return Medicine(
    id: 'sample-1',
    name: name,
    dose: '50mg',
    qtyPerIntake: 1,
    scheduleKind: ScheduleKind.daily,
    frequencyPerDay: 2,
    times: ['00:01', '23:58'],
    durationConfirmed: true, // Confirmed maintenance.
    instructions: 'After breakfast and at bedtime',
    start: DateTime(now.year, now.month, now.day),
  );
}

Future<void> initStore(List<Medicine> meds) async {
  SharedPreferences.setMockInitialValues({
    if (meds.isNotEmpty)
      'meds': jsonEncode(meds.map((m) => m.toJson()).toList()),
  });
  await Store.init();
}

Future<void> pumpScreen(WidgetTester tester, Widget screen,
    {double width = 393, double height = 4000, double textScale = 1}) async {
  // A tall view paints the whole page, so any overflow is reported.
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, height * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: screen,
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('Home', () {
    testWidgets('empty state offers Scan Prescription and its three options',
        (tester) async {
      await initStore([]);
      await pumpScreen(tester, const HomeScreen());
      expect(find.text('Welcome to IMedsU'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Scan Prescription'));
      await tester.pumpAndSettle();
      expect(find.text('Take a Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Type Prescription'), findsOneWidget);
    });

    testWidgets('progress and Mark as Taken use and update saved data',
        (tester) async {
      await initStore([twiceDaily()]);
      await pumpScreen(tester, const HomeScreen());
      expect(find.text("Today's Medication Schedule"), findsOneWidget);
      expect(find.text('0 of 2 doses taken today'), findsOneWidget);
      // Scan is a fixed bar, not a floating button over dose actions.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Scan Prescription'), findsOneWidget);
      // The 12:01 AM dose has passed, so its button says "(late)".
      expect(find.textContaining('Mark as Taken'), findsNWidgets(2));

      await tester.tap(find.textContaining('Mark as Taken').first);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 doses taken today'), findsOneWidget);
      expect(find.text('Taken'), findsOneWidget);
      // Saved as the scheduled dose key; no actual-intake timestamp invented.
      final saved = Store.meds().single;
      final today = DateTime.now();
      expect(saved.taken,
          [Medicine.keyOf(DateTime(today.year, today.month, today.day, 0, 1))]);

      await tester.tap(find.text('Undo: Mark as Not Taken'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 doses taken today'), findsOneWidget);
      expect(Store.meds().single.taken, isEmpty);
    });

    for (final textScale in [1.0, 2.0]) {
      testWidgets('no overflow on a small phone, text x$textScale',
          (tester) async {
        await initStore([
          twiceDaily(name: 'Isosorbide Mononitrate Extended-Release Tablet')
        ]);
        await pumpScreen(tester, const HomeScreen(),
            width: 320, textScale: textScale);
        expect(tester.takeException(), isNull);

        await initStore([]);
        await pumpScreen(tester, const HomeScreen(),
            width: 320, textScale: textScale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Settings', () {
    testWidgets('shows sections and real (not simulated) permission status',
        (tester) async {
      await initStore([]);
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('AI Connection'), findsOneWidget);
      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Save and Test Connection'), findsOneWidget);
      // No notification plugin in tests: after the bounded check the status
      // must be honest ("Not allowed"/"Could not check"), never "Allowed".
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Checking…'), findsNothing);
      expect(find.text('Allowed'), findsNothing);
      expect(
          find.text('Not allowed').evaluate().length +
              find.text('Could not check').evaluate().length,
          2);
      // No connection status is shown before a real test is run.
      expect(find.text('Connected'), findsNothing);
    });

    for (final textScale in [1.0, 2.0]) {
      testWidgets('no overflow on a small phone, text x$textScale',
          (tester) async {
        await initStore([]);
        await pumpScreen(tester, const SettingsScreen(),
            width: 320, textScale: textScale);
        await tester.pump(const Duration(seconds: 6)); // Final status badges.
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('logo reads as "IMedsU" for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: IMedsULogo()))));
    expect(find.bySemanticsLabel('IMedsU'), findsOneWidget);
    expect(find.byType(CapsuleMark), findsOneWidget);
    semantics.dispose();
  });
}
