// Developer tool (not part of the app or test suite): renders SYNTHETIC
// printed prescriptions to PNG so real ML Kit OCR can be measured on a phone.
//   flutter test tool/probe_images_test.dart
// Output: build/ocr_probe/*.png (no real patient data).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const sampleA = 'SAMPLE / NOT FOR MEDICAL USE\n\nAmoxicillin 500 mg\n'
    'Take 1 capsule every 8 hours for 7 days.\nQuantity: 21';
const sampleB = 'SAMPLE / NOT FOR MEDICAL USE\n\nMedicine: Losartan 50 mg\n'
    'Sig: 1 tab PO OD\nDuration: ongoing';
const sampleC = 'SAMPLE / NOT FOR MEDICAL USE\n\n'
    'Medicine: Dextromethorphan 15 mg/5 mL\nSig: 5 mL as needed for cough';
const sampleF = 'SAMPLE / NOT FOR MEDICAL USE\nSunrise Family Clinic\n'
    '123 Mabini St., Quezon City   Tel: 8123 4567\n'
    'Patient: Test Patient      Age: 60      Date: 10/10/2026\n\nRx\n'
    '1. Metformin 500 mg\n    Sig: 1 tab twice daily after meals, ongoing\n'
    '2. Atorvastatin 20 mg\n    Sig: 1 tab at bedtime, ongoing';

Future<void> loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> render(WidgetTester tester, String name, Widget page,
    {required double width, required double height}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(
      key: key,
      child: Material(
        color: Colors.white,
        child: Container(
            color: Colors.white,
            width: width,
            height: height,
            padding: EdgeInsets.all(width * 0.06),
            child: page),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/ocr_probe/$name.png')..createSync(recursive: true);
    await out.writeAsBytes(data!.buffer.asUint8List());
  });
}

Widget text(String body, {String font = 'Arial', double size = 40}) =>
    Text(body,
        style: TextStyle(
            fontFamily: font,
            fontSize: size,
            color: Colors.black,
            height: 1.4));

void main() {
  testWidgets('render synthetic prescription images', (tester) async {
    await tester.runAsync(() async {
      await loadFont('Arial', 'C:/Windows/Fonts/arial.ttf');
      await loadFont('Times', 'C:/Windows/Fonts/times.ttf');
    });
    await render(tester, 'A_print', text(sampleA), width: 1600, height: 900);
    await render(tester, 'B_print', text(sampleB), width: 1600, height: 900);
    await render(tester, 'C_print', text(sampleC), width: 1600, height: 900);
    await render(tester, 'A_small', text(sampleA, size: 20),
        width: 1600, height: 900);
    await render(tester, 'A_lowres', text(sampleA, size: 20),
        width: 800, height: 450);
    await render(
        tester, 'F_header_times', text(sampleF, font: 'Times', size: 34),
        width: 1600, height: 1100);
    // Table layout: name and strength in separate columns.
    await render(
        tester,
        'A_table',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          text('SAMPLE / NOT FOR MEDICAL USE'),
          const SizedBox(height: 40),
          Row(children: [
            SizedBox(width: 700, child: text('Medicine')),
            text('Strength'),
          ]),
          Row(children: [
            SizedBox(width: 700, child: text('Amoxicillin')),
            text('500 mg'),
          ]),
          const SizedBox(height: 20),
          text('Take 1 capsule every 8 hours for 7 days.\nQuantity: 21'),
        ]),
        width: 1600,
        height: 900);
  });
}
