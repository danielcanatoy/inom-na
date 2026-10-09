import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/medicine.dart';
import 'fallback_parser.dart';
import 'med_names.dart';
import 'store.dart';

class ParseResult {
  ParseResult(this.meds, this.source, [this.note, this.warnings = const {}]);
  final List<Medicine> meds;
  final String source; // tingnan ang RxParser.srcVision / srcText / srcOffline
  final String? note;
  final Map<String, String> warnings; // Medicine.id -> babala (kailangang suriin ng user)
}

/// Pagkakasunod: (1) Ollama vision (larawan + OCR text), (2) Ollama text (OCR text),
/// (3) offline parser sa phone. Lahat local: laptop sa parehong WiFi/hotspot o phone mismo.
class RxParser {
  static const srcVision = 'Local AI – binasa ang larawan (Ollama vision)';
  static const srcText = 'Local AI – binasa ang text (Ollama)';
  static const srcOffline = 'Offline parser (sa phone)';

  static const _system = '''
You read Philippine medical prescriptions and pharmacy labels. The text comes from OCR and may contain errors.
Text may be English, Tagalog, or Taglish.
Extract EVERY medicine. Expand abbreviations:
OD/QD/once a day/1x = 1 per day; BID/2x/twice = 2; TID/3x/thrice = 3; QID/4x = 4;
q12h = 2; q8h = 3; q6h = 4; q4h = 6; HS/at bedtime = 1 per day with bedtime=true;
PRN/as needed = times_per_day 0; AC = before meals; PC = after meals.
"x 7 days", "for 1 week" -> days (weeks x 7). No duration, "maintenance", or "continue" -> days = null.
"#21", "qty 21", "no. 21" -> stock (pieces bought). "1 tab", "1/2 tab", "2 caps" -> qty_per_intake.
Never invent medicines. Ignore patient name, doctor, clinic, address, dates, license numbers.
Write instructions in simple Tagalog (e.g. "pagkatapos kumain", "bago kumain").
Only include instructions that are actually written. If none are written, use "".
Reply with JSON only:
{"medicines":[{"name":"Amoxicillin","dose":"500mg","qty_per_intake":1,"times_per_day":3,"bedtime":false,"days":7,"instructions":"pagkatapos kumain","stock":21}]}''';

  static const _visionHints = '''
The image is a photo of a prescription, often HANDWRITTEN by a Filipino doctor.
How to read it:
- Medicines are usually listed after "Rx" or numbered 1., 2., 3. Each has a generic name (sometimes a brand in parentheses), a strength like 500mg, and a quantity like #21 or #30.
- The directions usually start with "Sig:" or "S:" on the next line, e.g. "1 cap TID x 7 days", "1 tab OD", "1/2 tab BID", "1 tab q8h PRN for fever", "1 tab HS".
- Doctors write "3x a day", "TID", "t.i.d." the same way. A circled or underlined number may be the quantity.
- Handwriting confusions: "l" vs "1", "O" vs "0", "rn" vs "m", "q" vs "g".
- Copy each drug name letter by letter as written. NEVER replace it with a different drug that looks similar (e.g. Carbocisteine is not Cefixime). If unsure of some letters, still write your best reading of what is written.
- Use the OCR text below only as a hint; it is often wrong for handwriting. Trust the image more.
- If a medicine is unreadable, skip it. Do not guess medicines that are not written.''';

  /// Para sa tina-type na reseta (walang larawan).
  static Future<ParseResult> parse(String text) => _run(text, null);

  /// Para sa scan: [imagePath] = larawan, [ocrText] = nabasa ng ML Kit.
  static Future<ParseResult> parseImage(String imagePath, String ocrText) =>
      _run(ocrText, imagePath);

  static Future<ParseResult> _run(String text, String? imagePath) async {
    final hasText = text.trim().isNotEmpty;
    // TEMP DEBUG: tingnan sa terminal ng `flutter run` (hanapin ang [RX])
    debugPrint('[RX] Ollama: ${Store.ollamaUrl} text=${Store.ollamaModel} '
        'vision=${Store.visionModel} image=${imagePath != null}');

    String? note;
    final models = await _models();
    if (models == null) {
      debugPrint('[RX] OLLAMA ERROR: hindi maabot ang ${Store.ollamaUrl}');
      note = 'Hindi maabot ang Ollama sa laptop, kaya offline parser ang ginamit.';
    } else {
      // 1. Vision: nakikita ng model ang mismong larawan (pinakamaganda sa sulat-kamay)
      if (imagePath != null) {
        if (_has(models, Store.visionModel)) {
          try {
            final bytes = await File(imagePath).readAsBytes();
            debugPrint('[RX] vision: nagpapadala ng ${bytes.length ~/ 1024} KB na larawan');
            final meds = await _ollama(
              Store.visionModel,
              '$_visionHints\n\nOCR text (hint only):\n${hasText ? text : '(wala)'}',
              image: base64Encode(bytes),
              timeout: const Duration(seconds: 150),
            );
            debugPrint('[RX] vision model -> ${meds.length} gamot');
            if (meds.isNotEmpty) return _done(meds, srcVision, null, text);
            note = 'Walang nakuhang gamot ang vision model sa larawan.';
          } catch (e) {
            debugPrint('[RX] OLLAMA VISION ERROR: $e');
            note = 'Nag-error ang vision model.';
          }
        } else {
          debugPrint('[RX] wala ang vision model na ${Store.visionModel}. Meron: $models');
        }
      }
      // 2. Text: OCR text lang
      if (hasText && _has(models, Store.ollamaModel)) {
        try {
          final meds = await _ollama(Store.ollamaModel, text);
          debugPrint('[RX] text model -> ${meds.length} gamot');
          if (meds.isNotEmpty) return _done(meds, srcText, note);
          note = 'Walang nakuhang gamot ang Local AI, kaya offline parser ang ginamit.';
        } catch (e) {
          debugPrint('[RX] OLLAMA TEXT ERROR: $e');
          note = 'Nag-error ang Local AI, kaya offline parser ang ginamit.';
        }
      } else if (!_has(models, Store.ollamaModel)) {
        debugPrint('[RX] wala ang text model na ${Store.ollamaModel}. Meron: $models');
      }
    }

    // 3. Offline parser sa phone (laging gumagana)
    if (!hasText) {
      debugPrint('[RX] PARSER USED: wala (walang OCR text)');
      return ParseResult([], srcOffline,
          'Walang nabasang text. Subukan ulit sa mas maliwanag, o i-type na lang.');
    }
    return _done(FallbackParser.parse(text), srcOffline, note);
  }

  /// Sinusuri ang bawat pangalan (maliit na typo lang ang inaayos) at nilalagyan
  /// ng babala ang kailangang i-check ng user. [ocrText]: para sa vision lang,
  /// para mahuli kung pinalitan/inimbento ng model ang gamot.
  static ParseResult _done(List<Medicine> meds, String source,
      [String? note, String? ocrText]) {
    final warnings = <String, String>{};
    for (final m in meds) {
      final c = MedNames.check(m.name);
      m.name = c.name;
      final w = [
        if (c.warning != null) c.warning!,
        if (ocrText != null &&
            ocrText.trim().isNotEmpty &&
            !MedNames.foundInText(m.name, ocrText))
          "⚠️ Hindi makita sa text ng larawan ang '${m.name}'. Baka mali ang basa ng AI. "
              'Ikumpara sa reseta.',
      ];
      if (w.isNotEmpty) warnings[m.id] = w.join('\n');
    }
    debugPrint('[RX] PARSER USED: $source -> ${meds.length} gamot');
    for (final m in meds) {
      debugPrint('[RX]   ${m.name} ${m.dose} ${m.timesPerDay}x/araw '
          '${warnings[m.id]?.replaceAll('\n', ' | ') ?? 'OK'}');
    }
    return ParseResult(meds, source, note, warnings);
  }

  static Future<List<Medicine>> _ollama(String model, String userContent,
      {String? image, Duration timeout = const Duration(seconds: 90)}) async {
    final res = await http
        .post(
          Uri.parse('${Store.ollamaUrl}/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': _system},
              {
                'role': 'user',
                'content': userContent,
                if (image != null) 'images': [image],
              },
            ],
            'format': 'json',
            'stream': false,
            'options': {'temperature': 0},
          }),
        )
        .timeout(timeout);
    if (res.statusCode != 200) throw Exception('Ollama ${res.statusCode}: ${res.body}');
    final content = (jsonDecode(res.body) as Map)['message']['content'] as String;
    return medsFromContent(content);
  }

  /// Ginagawang Medicine ang JSON na sagot ng model.
  @visibleForTesting
  static List<Medicine> medsFromContent(String content) {
    final list = (jsonDecode(content) as Map)['medicines'] as List? ?? [];
    final out = <Medicine>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final perDay = _int(raw['times_per_day']) ?? 1;
      out.add(Medicine(
        id: '${Medicine.newId()}${out.length}',
        name: name,
        dose: (raw['dose'] ?? '').toString(),
        qtyPerIntake: _num(raw['qty_per_intake']) ?? 1,
        // Oras ay galing sa Dart (mas maaasahan kaysa hayaan ang LLM)
        times: Medicine.defaultTimes(perDay, bedtime: raw['bedtime'] == true),
        days: _int(raw['days']),
        instructions: (raw['instructions'] ?? '').toString(),
        stock: _int(raw['stock']),
      ));
    }
    return out;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// Listahan ng models sa Ollama, o null kung hindi maabot (mabilis, 4 seconds).
  static Future<List<String>?> _models() async {
    try {
      final res = await http
          .get(Uri.parse('${Store.ollamaUrl}/api/tags'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      return ((jsonDecode(res.body) as Map)['models'] as List? ?? [])
          .map((m) => (m as Map)['name'].toString())
          .toList();
    } catch (e) {
      debugPrint('[RX] ping error: $e');
      return null;
    }
  }

  static bool _has(List<String> models, String name) =>
      name.isNotEmpty && (models.contains(name) || models.contains('$name:latest'));

  /// Para sa settings: naka-on ba ang Ollama at nandiyan ang mga model?
  static Future<String> ping() async {
    final models = await _models();
    if (models == null) {
      return '❌ Hindi maabot. Tingnan ang IP at kung naka-OLLAMA_HOST=0.0.0.0.';
    }
    String line(String label, String m) =>
        _has(models, m) ? '✅ $label: $m' : '⚠️ $label: wala ang "$m"';
    return 'Konektado.\n${line('Text', Store.ollamaModel)}\n${line('Vision', Store.visionModel)}'
        '\nMeron: ${models.join(', ')}';
  }
}
