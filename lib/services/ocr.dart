import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR (Google ML Kit). Hindi umaalis sa phone ang larawan.
class Ocr {
  static Future<String> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}
