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
    {required double width,
    required double height,
    Color background = Colors.white,
    double padding = 0.06,
    GlobalKey? cropKey}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(
      key: key,
      child: Material(
        color: background,
        child: Container(
            color: background,
            width: width,
            height: height,
            padding: EdgeInsets.all(width * padding),
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
    // Pixel-identical crop of the paper region (simulates user cropping).
    if (cropKey != null) {
      final paper =
          cropKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final cropped = await paper.toImage(pixelRatio: 1);
      final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
      await File('build/ocr_probe/${name}_cropped.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    }
  });
}

Widget text(String body,
        {String font = 'Arial', double size = 40, Color ink = Colors.black}) =>
    Text(body,
        style: TextStyle(
            fontFamily: font, fontSize: size, color: ink, height: 1.4));

// Handwriting-STYLE fonts are a proxy only; they are not real handwriting.
const sampleH = 'SAMPLE / NOT FOR MEDICAL USE\nRx\n'
    'Amoxicillin 500 mg\n1 cap every 8 hours x 7 days  #21\n'
    'Colchicine 0.5 mg\n1 tab once daily  #30';
const ballpoint = Color(0xFF1F2F66);
const paperColor = Color(0xFFF3EEE2);

/// A photo-like scene: the paper on a dark desk with unrelated text around it.
Widget scene(Widget paper, GlobalKey paperKey) => Stack(children: [
      Positioned(
          left: 10,
          top: 10,
          child: text('NOTEBOOK  2026', size: 46, ink: Colors.white70)),
      Positioned(
          right: 10,
          bottom: 10,
          child: text('Receipt TOTAL 1,250.00', size: 40, ink: Colors.white60)),
      Center(
        child: RepaintBoundary(
          key: paperKey,
          child: Container(
              color: paperColor,
              padding: const EdgeInsets.all(40),
              child: paper),
        ),
      ),
    ]);

void main() {
  testWidgets('render synthetic prescription images', (tester) async {
    await tester.runAsync(() async {
      await loadFont('Arial', 'C:/Windows/Fonts/arial.ttf');
      await loadFont('Times', 'C:/Windows/Fonts/times.ttf');
      await loadFont('InkFree', 'C:/Windows/Fonts/Inkfree.ttf');
      await loadFont('SegoePrint', 'C:/Windows/Fonts/segoepr.ttf');
      await loadFont('SegoeScript', 'C:/Windows/Fonts/segoesc.ttf');
    });
    if (Platform.environment['PROBE_SET'] == 'compound') {
      // A fictional compounded cough syrup: ONE preparation, PRN only.
      const compound = 'SAMPLE / NOT FOR MEDICAL USE\nRx\n'
          'Dextromethorphan 15 mg/5 mL\nGuaifenesin syrup 100 mg/5 mL\n'
          'Alcohol 5%\nFlavored syrup q.s. ad 60 mL\nM. ft. syrup\n'
          'Sig: 5 mL as needed for cough';
      await render(tester, 'X_compound_inkfree',
          text(compound, font: 'InkFree', size: 40, ink: ballpoint),
          width: 1600, height: 1000, background: paperColor);
      await render(tester, 'X_compound_print', text(compound, size: 36),
          width: 1600, height: 1000);
      return;
    }
    if (Platform.environment['PROBE_SET'] == 'handwriting') {
      // Same content in every image so methods can be compared.
      await render(tester, 'P_print', text(sampleH, size: 38),
          width: 1600, height: 1000);
      await render(tester, 'N_inkfree',
          text(sampleH, font: 'InkFree', size: 42, ink: ballpoint),
          width: 1600, height: 1000, background: paperColor);
      await render(tester, 'N_segoeprint',
          text(sampleH, font: 'SegoePrint', size: 36, ink: ballpoint),
          width: 1600, height: 1000, background: paperColor);
      await render(tester, 'M_script',
          text(sampleH, font: 'SegoeScript', size: 38, ink: ballpoint),
          width: 1600, height: 1000, background: paperColor);
      await render(
          tester,
          'M_inkfree_tilt_faint',
          Transform.rotate(
              angle: 0.05,
              child: text(sampleH,
                  font: 'InkFree', size: 34, ink: const Color(0xFF6A7390))),
          width: 1600,
          height: 1000,
          background: paperColor);
      for (final (name, font, size) in [
        ('S_print', 'Arial', 30.0),
        ('S_inkfree', 'InkFree', 32.0),
      ]) {
        final key = GlobalKey();
        await render(tester, name,
            scene(text(sampleH, font: font, size: size, ink: ballpoint), key),
            width: 1600,
            height: 1200,
            background: const Color(0xFF4A3B2E),
            padding: 0,
            cropKey: key);
      }
      return;
    }
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
