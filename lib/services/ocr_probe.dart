import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'ocr.dart';
import 'rx_parser.dart';

/// DEBUG BUILDS ONLY. Developer measurement of real on-device ML Kit OCR on
/// SYNTHETIC images that a developer places in `<app cache>/ocr_probe/` via
/// `adb shell run-as`. Never runs in release builds, never reads the user's
/// photos, and deletes the probe files after measuring them.
class OcrProbe {
  static Future<void> runIfPresent() async {
    if (!kDebugMode) return;
    try {
      final dir = Directory('${Directory.systemTemp.path}/ocr_probe');
      if (!dir.existsSync()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        await _measure(name, file.path);
        // Phase 5A: the same image after on-device enhancement.
        for (final (label, contrast) in [('gray', 1.5), ('hicontrast', 3.0)]) {
          final enhanced = await _enhance(file, contrast, label);
          if (enhanced != null) {
            await _measure('$name@$label', enhanced.path);
            enhanced.deleteSync();
          }
        }
        file.deleteSync();
      }
      debugPrint('IMEDSU_PROBE done ${files.length} files');
    } catch (e) {
      debugPrint('IMEDSU_PROBE failed: ${e.runtimeType}');
    }
  }

  static Future<void> _measure(String name, String path) async {
    final watch = Stopwatch()..start();
    final ocr = await Ocr.read(path);
    final ocrMs = watch.elapsedMilliseconds;
    void dump(String label, String text) {
      for (final line in text.split('\n')) {
        debugPrint('IMEDSU_PROBE $name $label| $line');
      }
    }

    dump('RAW', ocr.raw);
    dump('ARRANGED', ocr.text);
    for (final (label, text) in [('arranged', ocr.text), ('raw', ocr.raw)]) {
      final meds = RxParser.readOnPhone(text).meds;
      debugPrint('IMEDSU_PROBE $name PARSE[$label] found=${meds.length} '
          'ocrMs=$ocrMs');
      for (final m in meds) {
        debugPrint('IMEDSU_PROBE $name MED[$label] name="${m.name}" '
            'dose="${m.dose}" qty=${m.qtyPerIntake} kind=${m.scheduleKind.name} '
            'perDay=${m.frequencyPerDay} interval=${m.intervalHours} '
            'days=${m.days} maint=${m.isMaintenance} stock=${m.stock} '
            'unresolved=${m.validationErrors().length}');
      }
    }
  }

  /// Grayscale + contrast stretch around mid-gray, using only dart:ui.
  static Future<File?> _enhance(File file, double c, String label) async {
    try {
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final src = (await codec.getNextFrame()).image;
      final o = 128 * (1 - c);
      final r = 0.299 * c, g = 0.587 * c, b = 0.114 * c;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImage(
          src,
          ui.Offset.zero,
          ui.Paint()
            ..colorFilter = ui.ColorFilter.matrix([
              r, g, b, 0, o, //
              r, g, b, 0, o,
              r, g, b, 0, o,
              0, 0, 0, 1, 0,
            ]));
      final image =
          await recorder.endRecording().toImage(src.width, src.height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final out = File('${file.path}.$label.png');
      out.writeAsBytesSync(data.buffer.asUint8List());
      return out;
    } catch (_) {
      return null;
    }
  }
}
