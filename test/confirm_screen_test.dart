import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/screens/confirm_screen.dart';
import 'package:inom_na/services/rx_parser.dart';

Medicine reviewedCandidate() => Medicine(
      id: 'candidate',
      name: 'Paracetamol',
      dose: '500mg',
      qtyPerIntake: 1,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: 1,
      times: ['08:00'],
      days: 3,
      durationConfirmed: true,
      start: DateTime(2026, 10, 9, 8),
    );

Finder fieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

Future<void> openConfirmation(
  WidgetTester tester,
  Medicine medicine,
  void Function(List<Medicine>?) onResult,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(
      body: Center(child: ElevatedButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<List<Medicine>>(
            MaterialPageRoute(builder: (_) => ConfirmScreen(
              result: ParseResult([medicine], RxParser.srcOffline),
              rawText: 'Synthetic prescription text',
            )),
          );
          onResult(result);
        },
        child: const Text('Open review'),
      )),
    )),
  ));
  await tester.tap(find.text('Open review'));
  await tester.pumpAndSettle();
}

Future<void> tapReview(WidgetTester tester) async {
  final review = find.byType(CheckboxListTile);
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Tama na, i-set ang paalala'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unresolved required fields cannot be verified or saved',
      (tester) async {
    var returned = false;
    final medicine = Medicine(id: 'draft', name: 'Paracetamol');
    await openConfirmation(tester, medicine, (_) => returned = true);
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tapSave(tester);
    expect(returned, isFalse);
    expect(find.byType(ConfirmScreen), findsOneWidget);
  });

  testWidgets('a recognized name still requires explicit prescription review',
      (tester) async {
    List<Medicine>? returned;
    await openConfirmation(tester, reviewedCandidate(), (value) => returned = value);
    await tapSave(tester);
    expect(returned, isNull);
    expect(find.byType(ConfirmScreen), findsOneWidget);

    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await tapSave(tester);
    expect(returned, hasLength(1));
    expect(returned!.single.name, 'Paracetamol');
  });

  testWidgets('editing a verified dosage resets review and revalidates fields',
      (tester) async {
    var returned = false;
    await openConfirmation(tester, reviewedCandidate(), (_) => returned = true);
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);

    final doseField = fieldWithLabel('Dose / strength');
    await tester.ensureVisible(doseField);
    await tester.enterText(doseField, '0mg');
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tapSave(tester);
    expect(returned, isFalse);

    await tester.ensureVisible(doseField);
    await tester.enterText(doseField, '250mg');
    await tester.pumpAndSettle();
    await tapReview(tester);
    await tapSave(tester);
    expect(returned, isTrue);
  });

  testWidgets('canceling edited prescription leaves the original unchanged',
      (tester) async {
    final original = reviewedCandidate();
    var returned = false;
    List<Medicine>? returnedValue;
    await openConfirmation(tester, original, (value) {
      returned = true;
      returnedValue = value;
    });
    final nameField = fieldWithLabel('Gamot');
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Amoxicillin');
    final doseField = fieldWithLabel('Dose / strength');
    await tester.ensureVisible(doseField);
    await tester.enterText(doseField, '250mg');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(returnedValue, isNull);
    expect(original.name, 'Paracetamol');
    expect(original.dose, '500mg');
    expect(original.times, ['08:00']);
  });

  testWidgets('fixed interval requires choosing the first dose anchor',
      (tester) async {
    final medicine = reviewedCandidate()
      ..scheduleKind = ScheduleKind.interval
      ..frequencyPerDay = null
      ..intervalHours = 8
      ..times = [];
    List<Medicine>? returned;
    await openConfirmation(tester, medicine, (value) => returned = value);
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tapSave(tester);
    expect(returned, isNull);

    final anchor = find.textContaining('Simula / unang dose:');
    await tester.ensureVisible(anchor);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await tapSave(tester);
    expect(returned, hasLength(1));
    expect(returned!.single.intervalHours, 8);
  });

  testWidgets('contradictory written interval time blocks review until corrected',
      (tester) async {
    final medicine = reviewedCandidate()
      ..scheduleKind = ScheduleKind.interval
      ..frequencyPerDay = null
      ..intervalHours = 8
      ..times = ['09:00'];
    List<Medicine>? returned;
    await openConfirmation(tester, medicine, (value) => returned = value);

    final anchor = find.textContaining('Simula / unang dose:');
    await tester.ensureVisible(anchor);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tapSave(tester);
    expect(returned, isNull);

    // Correct the extracted hint through its visible delete control. The
    // explicitly selected 08:00 anchor remains and must be reviewed again.
    final chip = find.byType(InputChip);
    await tester.ensureVisible(chip);
    final chipBounds = tester.getRect(chip);
    await tester.tapAt(Offset(chipBounds.right - 16, chipBounds.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
    await tapReview(tester);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await tapSave(tester);
    expect(returned, hasLength(1));
    expect(returned!.single.times, isEmpty);
    expect(returned!.single.start.hour, 8);
    expect(medicine.times, ['09:00']);
  });
}
