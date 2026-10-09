import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_layout.dart';

/// On-device OCR (Google ML Kit). Text recognition runs on the phone.
/// ML Kit applies the photo's EXIF orientation for file-path images.
class Ocr {
  /// Returns text in visual reading order (rows built from line positions),
  /// so a medicine name and its strength printed side by side stay on one
  /// line. Falls back to ML Kit's own text if layout data is unusable.
  static Future<({String text, String raw})> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      var arranged = '';
      try {
        arranged = OcrLayout.arrange([
          for (final block in result.blocks)
            for (final line in block.lines)
              OcrLine(line.text,
                  top: line.boundingBox.top,
                  bottom: line.boundingBox.bottom,
                  left: line.boundingBox.left),
        ]);
      } catch (_) {
        arranged = '';
      }
      return (
        text: arranged.trim().isEmpty ? result.text : arranged,
        raw: result.text,
      );
    } finally {
      await recognizer.close();
    }
  }
}
