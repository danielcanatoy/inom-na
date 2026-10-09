import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/services/rx_parser.dart';

/// Medicines whose selected dropdown values are the longest in each menu.
Map<String, Medicine> layoutCases() => {
      'interval + days': Medicine(
        id: 'interval',
        name: 'Amoxicillin',
        dose: '500mg',
        qtyPerIntake: 1,
        scheduleKind: ScheduleKind.interval,
        intervalHours: 8,
        times: ['08:00'],
        days: 7,
        durationConfirmed: true,
        start: DateTime(2026, 10, 9, 8),
      ),
      'prn + maintenance': Medicine(
        id: 'prn',
        name: 'Paracetamol',
        dose: '500mg',
        qtyPerIntake: 1,
        scheduleKind: ScheduleKind.prn,
        durationConfirmed: true,
        start: DateTime(2026, 10, 9, 8),
      ),
      'daily + end date': Medicine(
        id: 'daily',
        name: 'Losartan',
        dose: '50mg',
        qtyPerIntake: 1,
        scheduleKind: ScheduleKind.daily,
        frequencyPerDay: 1,
        times: ['08:00'],
        end: DateTime(2026, 10, 16),
        durationConfirmed: true,
        start: DateTime(2026, 10, 9, 8),
      ),
      'unresolved draft': Medicine(id: 'draft', name: 'Cetirizine'),
    };

Future<void> pumpConfirm(
  WidgetTester tester,
  Medicine medicine, {
  required double width,
  required double textScale,
  double height = 4000,
}) async {
  // Overflow is only reported for painted widgets. A tall view paints the
  // whole form (no lazy off-screen items); width is the real phone width.
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, height * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ConfirmScreen(
      result: ParseResult([medicine], RxParser.srcOffline),
      rawText: 'SAMPLE – FOR DEMO ONLY',
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // 320 dp is a small phone; 393 dp is typical (e.g. Poco X7 Pro at default
  // display size). 2.0 approximates Android's largest font setting.
  for (final width in [320.0, 393.0]) {
    for (final textScale in [1.0, 1.3, 2.0]) {
      for (final entry in layoutCases().entries) {
        testWidgets(
            'no horizontal overflow: ${entry.key}, '
            '${width.toInt()} dp, text x$textScale', (tester) async {
          await pumpConfirm(tester, entry.value,
              width: width, textScale: textScale);
          // Any RenderFlex overflow is reported as a FlutterError here.
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('open dropdown menus fit at large text on a small phone',
      (tester) async {
    await pumpConfirm(tester, layoutCases()['interval + days']!,
        width: 320, textScale: 2.0);
    final dropdowns =
        find.byWidgetPredicate((widget) => widget is DropdownButtonFormField);
    expect(dropdowns, findsNWidgets(2)); // schedule type, duration
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(dropdowns.at(i));
      await tester.pump();
      // 'Hindi pa malinaw' is not selected in either dropdown, so it is only
      // on screen while a menu is open.
      expect(find.text('Hindi pa malinaw'), findsNothing);
      await tester.tap(dropdowns.at(i));
      await tester.pumpAndSettle();
      expect(find.text('Hindi pa malinaw'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Close the menu without changing the reviewed value.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Hindi pa malinaw'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('selected schedule values stay fully readable, not truncated',
      (tester) async {
    await pumpConfirm(tester, layoutCases()['interval + days']!,
        width: 320, textScale: 2.0);
    for (final label in ['Eksaktong pagitan (q6h/q8h)', 'Bilang ng araw']) {
      final text = tester.widget<Text>(find.text(label).first);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, isNull);
    }
  });
}
