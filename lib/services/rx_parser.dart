import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/medicine.dart';
import 'fallback_parser.dart';
import 'med_names.dart';
import 'review_note.dart';
import 'store.dart';

class ParseResult {
  ParseResult(this.meds, this.source, [this.note, this.warnings = const {}]);
  final List<Medicine> meds;
  final String source; // RxParser.srcVision / srcText / srcOffline
  final String? note;
  final Map<String, String> warnings; // Medicine.id -> warning to review
}

/// Order: (1) Ollama vision (image + OCR text), (2) Ollama text (OCR text),
/// (3) offline parser on the phone. Images/text go to the configured LAN server.
class RxParser {
  static const srcVision =
      'Local AI on your laptop – read the photo (Ollama vision)';
  static const srcText = 'Local AI on your laptop – read the text (Ollama)';
  static const srcOffline = 'Offline reader on this phone (rule-based)';

  static const _system = '''
You read Philippine medical prescriptions and pharmacy labels. The text comes from OCR and may contain errors.
Text may be English, Tagalog, or Taglish.
Extract EVERY medicine and retain uncertainty. Never invent missing fields.
OD/QD/once a day/1x = daily 1 per day; BID/2x/twice = daily 2; TID/3x/thrice = daily 3; QID/4x = daily 4.
q12h/q8h/q6h/q4h are FIXED INTERVALS of 12/8/6/4 hours, not general daily frequencies.
HS/at bedtime = daily 1 with bedtime=true. PRN/as needed = frequency_type prn;
retain any written minimum interval even for PRN. AC = before meals; PC = after meals.
Explicit written clock times -> frequency_type explicit, times in HH:mm. Do not generate times yourself.
Unclear/conflicting frequency -> frequency_type unknown, times_per_day null, with uncertainties.
"x 7 days", "for 1 week" -> days (weeks x 7). No duration -> days null, maintenance false.
Only explicit "maintenance"/"indefinitely" establishes maintenance true; "continue" alone is unresolved.
"#21", "qty 21", "no. 21" -> stock (pieces bought). "1 tab", "1/2 tab", "2 caps" -> qty_per_intake.
Never invent medicines. Ignore patient name, doctor, clinic, address, dates, license numbers.
Keep the original written directions, including ambiguous abbreviations, in instructions.
Only include instructions that are actually written. If none are written, use "".
Missing/uncertain strength or quantity -> dose "" or qty_per_intake null, never default 1.
Use start_date/end_date only for explicitly stated treatment dates in YYYY-MM-DD, otherwise null.
Reply with JSON only:
{"medicines":[{"name":"Amoxicillin","dose":"500mg","qty_per_intake":1,"frequency_type":"interval","times_per_day":null,"interval_hours":8,"times":[],"bedtime":false,"days":7,"maintenance":false,"start_date":null,"end_date":null,"instructions":"1 cap q8h x 7 days","uncertainties":[],"stock":21}]}''';

  static const _visionHints = '''
The image is a photo of a prescription, often HANDWRITTEN by a Filipino doctor.
How to read it:
- Medicines are usually listed after "Rx" or numbered 1., 2., 3. Each has a generic name (sometimes a brand in parentheses), a strength like 500mg, and a quantity like #21 or #30.
- The directions usually start with "Sig:" or "S:" on the next line, e.g. "1 cap TID x 7 days", "1 tab OD", "1/2 tab BID", "1 tab q8h PRN for fever", "1 tab HS".
- Doctors write "3x a day", "TID", "t.i.d." the same way. A circled or underlined number may be the quantity.
- Handwriting confusions: "l" vs "1", "O" vs "0", "rn" vs "m", "q" vs "g".
- Copy each drug name letter by letter as written. NEVER replace it with a different drug that looks similar (e.g. Carbocisteine is not Cefixime). If unsure of some letters, still write your best reading of what is written.
- Use the OCR text below only as a hint; it is often wrong for handwriting. Trust the image more.
- If a medicine is partly unreadable, retain its best reading and explicit uncertainties. Do not silently skip a visible medicine or guess medicines that are not written.''';

  /// Typed prescription text (no image).
  static Future<ParseResult> parse(String text) => _run(text, null);

  /// Scan: [imagePath] = photo, [ocrText] = text read by ML Kit.
  static Future<ParseResult> parseImage(String imagePath, String ocrText) =>
      _run(ocrText, imagePath);

  static Future<ParseResult> _run(String text, String? imagePath) async {
    final hasText = text.trim().isNotEmpty;
    String? note;
    final models = await _models();
    if (models == null) {
      note = 'The laptop AI (Ollama) could not be reached, so the offline '
          'reader on this phone was used.';
    } else {
      // 1. Vision: the model sees the photo itself (best for handwriting)
      if (imagePath != null) {
        if (_has(models, Store.visionModel)) {
          try {
            final bytes = await File(imagePath).readAsBytes();
            final meds = await _ollama(
              Store.visionModel,
              '$_visionHints\n\nOCR text (hint only):\n${hasText ? text : '(none)'}',
              image: base64Encode(bytes),
              timeout: const Duration(seconds: 150),
            );
            if (meds.isNotEmpty) return _done(meds, srcVision, null, text);
            note = 'The vision model found no medications in the photo.';
          } catch (_) {
            note = 'The vision model returned an error.';
          }
        }
      }
      // 2. Text: OCR text only
      if (hasText && _has(models, Store.ollamaModel)) {
        try {
          final meds = await _ollama(Store.ollamaModel, text);
          if (meds.isNotEmpty) return _done(meds, srcText, note, text);
          note = 'The laptop AI found no medications, so the offline reader '
              'on this phone was used.';
        } catch (_) {
          note = 'The laptop AI returned an error, so the offline reader on '
              'this phone was used.';
        }
      }
    }

    // 3. Offline parser on the phone (always available)
    if (!hasText) {
      return ParseResult(
          [],
          srcOffline,
          'No text could be read. Try again in brighter light, or type the '
          'prescription instead.');
    }
    return _done(FallbackParser.parse(text), srcOffline, note, text);
  }

  /// Checks each name (only small typos are corrected) and attaches warnings
  /// the user must review. [ocrText] catches medicines a model replaced or
  /// invented.
  static ParseResult _done(List<Medicine> meds, String source,
      [String? note, String? ocrText]) {
    final warnings = <String, String>{};
    final writtenMeds =
        ocrText == null ? <Medicine>[] : FallbackParser.parse(ocrText);
    for (final m in meds) {
      final c = MedNames.check(m.name);
      m.name = c.name;
      for (final written in writtenMeds) {
        if (MedNames.check(written.name).name.toLowerCase() !=
            m.name.toLowerCase()) continue;
        if (m.instructions.isEmpty) m.instructions = written.instructions;
        if (source != srcOffline &&
            written.scheduleKind == ScheduleKind.interval &&
            (m.scheduleKind != ScheduleKind.interval ||
                m.intervalHours != written.intervalHours)) {
          m.scheduleKind = ScheduleKind.unknown;
          m.reviewNotes.add(
              'The dose interval in the scanned text does not match the AI result. Choose the correct interval using the prescription.');
        }
        if (source != srcOffline &&
            written.scheduleKind == ScheduleKind.explicit &&
            (m.times.length != written.times.length ||
                !m.times.every(written.times.contains))) {
          m.scheduleKind = ScheduleKind.unknown;
          m.reviewNotes.add(
              'The clock times in the scanned text do not match the AI result. Check and correct the times.');
        }
        if (source != srcOffline &&
            written.scheduleKind == ScheduleKind.unknown &&
            written.reviewNotes.any(ReviewNote.isConflictOrUnclear)) {
          m.scheduleKind = ScheduleKind.unknown;
          m.reviewNotes.addAll(written.reviewNotes);
        }
        break;
      }
      final w = [
        'Compare the name, strength, amount, frequency, times and duration with your prescription. A recognized name does not mean the other details are correct.',
        if (c.warning != null) c.warning!,
        ...m.reviewNotes,
        ...m.validationErrors(),
        if (ocrText != null &&
            ocrText.trim().isNotEmpty &&
            !MedNames.foundInText(m.name, ocrText))
          "'${m.name}' was not found in the text read from the photo. The AI "
              'may have misread it. Compare with your prescription.',
      ];
      if (w.isNotEmpty) warnings[m.id] = w.join('\n');
    }
    if (source != srcOffline &&
        writtenMeds.any((written) => !meds.any((medicine) =>
            MedNames.check(written.name).name.toLowerCase() ==
            medicine.name.toLowerCase()))) {
      note =
          '${note == null ? '' : '$note\n'}The scanned text may include a medication the AI left out. Compare with the whole prescription and add anything missing.';
    }
    return ParseResult(meds, source, note, warnings);
  }

  static Future<List<Medicine>> _ollama(String model, String userContent,
      {String? image, Duration timeout = const Duration(seconds: 90)}) async {
    if (_cloudModel(model))
      throw const FormatException('Cloud models are not permitted.');
    final endpoint = Store.localOllamaUri(Store.ollamaUrl);
    final res = await http
        .post(
          endpoint.resolve('/api/chat'),
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
    if (res.statusCode != 200)
      throw Exception('Local AI request failed (${res.statusCode}).');
    final content =
        (jsonDecode(res.body) as Map)['message']['content'] as String;
    return medsFromContent(content);
  }

  /// Converts the model's JSON reply into medicines.
  @visibleForTesting
  static List<Medicine> medsFromContent(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['medicines'] is! List) return [];
    final list = decoded['medicines'] as List;
    final out = <Medicine>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final name = _text(raw['name']);
      if (name.isEmpty) continue;
      final perDay = _int(raw['times_per_day']);
      final interval = _int(raw['interval_hours']);
      final type = _text(raw['frequency_type']).toLowerCase();
      final notes = <String>[
        if (raw['uncertainties'] is List)
          for (final note in raw['uncertainties'] as List)
            if (note is String && note.trim().isNotEmpty) note.trim(),
      ];
      var times = <String>[];
      var invalidTimes = false;
      if (raw['times'] is List) {
        for (final time in raw['times'] as List) {
          if (time is String) {
            times.add(time.trim());
          } else {
            notes.add(
                '${ReviewNote.invalid} the AI returned a time that is not valid.');
            invalidTimes = true;
          }
        }
      } else if (raw['times'] != null) {
        notes.add(
            '${ReviewNote.invalid} the written times are in an unreadable format.');
        invalidTimes = true;
      }
      var kind = switch (type) {
        'daily' => ScheduleKind.daily,
        'interval' => ScheduleKind.interval,
        'explicit' => ScheduleKind.explicit,
        'prn' => ScheduleKind.prn,
        _ => ScheduleKind.unknown,
      };
      // Older Ollama schema is accepted only when frequency is actually present.
      if (type.isEmpty) {
        if (times.isNotEmpty) {
          kind = ScheduleKind.explicit;
        } else if (interval != null) {
          kind = ScheduleKind.interval;
        } else if (perDay == 0) {
          kind = ScheduleKind.prn;
        } else if (perDay != null && perDay > 0 && perDay <= 24) {
          kind = ScheduleKind.daily;
        }
      }
      if (kind == ScheduleKind.daily &&
          times.isEmpty &&
          perDay != null &&
          perDay > 0 &&
          perDay <= 24) {
        times = Medicine.defaultTimes(perDay, bedtime: raw['bedtime'] == true);
      }
      if (kind == ScheduleKind.explicit &&
          perDay != null &&
          perDay != times.length) {
        kind = ScheduleKind.unknown;
        notes.add(
            '${ReviewNote.mismatch} the written times do not match the frequency.');
      }
      if (invalidTimes) kind = ScheduleKind.unknown;
      final days = _int(raw['days']);
      final endDate = _date(raw['end_date']);
      // A prescribed calendar end date includes that day; the model bound is exclusive.
      final end = endDate == null
          ? null
          : DateTime(endDate.year, endDate.month, endDate.day + 1);
      final maintenance = raw['maintenance'] == true;
      final invalidDuration =
          (raw['days'] != null && (days == null || days <= 0)) ||
              (raw['end_date'] != null && end == null);
      final durationConflict =
          (maintenance && (raw['days'] != null || end != null)) ||
              (days != null && end != null);
      if (durationConflict) notes.add(ReviewNote.durationConflict);
      if (raw['days'] != null && days == null)
        notes.add(
            '${ReviewNote.unclear} the treatment duration could not be read.');
      if (raw['end_date'] != null && end == null)
        notes.add('${ReviewNote.invalid} the end date is not a valid date.');
      final medicine = Medicine(
        id: '${Medicine.newId()}${out.length}',
        name: name,
        dose: _text(raw['dose']),
        qtyPerIntake: _num(raw['qty_per_intake']) ?? 0,
        scheduleKind: kind,
        frequencyPerDay: kind == ScheduleKind.explicit ? times.length : perDay,
        intervalHours: interval,
        times: times,
        days: durationConflict ? null : days,
        end: end,
        durationConfirmed: !durationConflict &&
            !invalidDuration &&
            ((days != null && days > 0) || end != null || maintenance),
        instructions: _text(raw['instructions']),
        stock: _int(raw['stock']),
        start: _date(raw['start_date']),
        reviewNotes: notes,
      );
      _checkWrittenDirections(medicine);
      out.add(medicine);
    }
    return out;
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static int? _int(Object? value) {
    if (value is num) {
      return value.isFinite && value == value.truncateToDouble()
          ? value.toInt()
          : null;
    }
    return value is String ? int.tryParse(value.trim()) : null;
  }

  static double? _num(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : value is String
            ? double.tryParse(value.trim())
            : null;
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static DateTime? _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))
      return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
            value) return null;
    return parsed;
  }

  /// A model must not erase an interval or an obvious conflict in its own directions.
  static void _checkWrittenDirections(Medicine medicine) {
    if (medicine.instructions.isEmpty) return;
    final written =
        FallbackParser.parse('Prescription 1mg\n${medicine.instructions}')
            .first;
    medicine.reviewNotes.addAll(written.reviewNotes);
    if (written.scheduleKind == ScheduleKind.unknown &&
        written.reviewNotes.any(ReviewNote.blocksSchedule)) {
      medicine.scheduleKind = ScheduleKind.unknown;
    } else if (written.scheduleKind == ScheduleKind.interval) {
      if (medicine.intervalHours != null &&
          medicine.intervalHours != written.intervalHours) {
        medicine.scheduleKind = ScheduleKind.unknown;
        medicine.reviewNotes.add(
            '${ReviewNote.mismatch} the dose interval does not match the written directions.');
      } else {
        final alreadyInterval = medicine.scheduleKind == ScheduleKind.interval;
        medicine.scheduleKind = ScheduleKind.interval;
        medicine.intervalHours = written.intervalHours;
        if (written.times.isNotEmpty || !alreadyInterval)
          medicine.times = written.times;
      }
    } else if (written.scheduleKind == ScheduleKind.prn) {
      medicine.scheduleKind = ScheduleKind.prn;
      medicine.intervalHours = written.intervalHours;
    } else if (written.scheduleKind == ScheduleKind.explicit) {
      if (medicine.frequencyPerDay != null &&
          medicine.frequencyPerDay != written.times.length) {
        medicine.scheduleKind = ScheduleKind.unknown;
        medicine.reviewNotes.add(
            '${ReviewNote.mismatch} the written times do not match the frequency.');
      } else {
        medicine.scheduleKind = ScheduleKind.explicit;
        medicine.times = written.times;
        medicine.frequencyPerDay = written.times.length;
      }
    } else if (written.scheduleKind == ScheduleKind.daily) {
      if (medicine.scheduleKind == ScheduleKind.daily &&
          medicine.frequencyPerDay != written.frequencyPerDay) {
        medicine.scheduleKind = ScheduleKind.unknown;
        medicine.reviewNotes.add(
            '${ReviewNote.mismatch} the frequency does not match the written directions.');
      } else if (medicine.scheduleKind == ScheduleKind.unknown) {
        medicine.scheduleKind = ScheduleKind.daily;
        medicine.frequencyPerDay = written.frequencyPerDay;
        medicine.times = written.times;
      }
    }
    if (written.qtyPerIntake > 0 &&
        medicine.qtyPerIntake > 0 &&
        medicine.qtyPerIntake != written.qtyPerIntake) {
      medicine.qtyPerIntake = 0;
      medicine.reviewNotes.add(
          '${ReviewNote.mismatch} the amount per dose does not match the written directions.');
    }
    if (written.reviewNotes.any(ReviewNote.isDurationConflict)) {
      medicine.durationConfirmed = false;
    }
    if (written.durationConfirmed &&
        medicine.end == null &&
        !medicine.reviewNotes.any(ReviewNote.isDurationConflict)) {
      if (medicine.durationConfirmed && medicine.days != written.days) {
        medicine.durationConfirmed = false;
        medicine.reviewNotes.add(
            '${ReviewNote.mismatch} the treatment duration does not match the written directions.');
      } else if (!medicine.durationConfirmed) {
        medicine.days = written.days;
        medicine.durationConfirmed = true;
      }
    }
  }

  /// Models available on Ollama, or null if unreachable (4-second timeout).
  static Future<List<String>?> _models() async {
    try {
      final res = await http
          .get(Store.localOllamaUri(Store.ollamaUrl).resolve('/api/tags'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      return ((jsonDecode(res.body) as Map)['models'] as List? ?? [])
          .map((m) => (m as Map)['name'].toString())
          .toList();
    } catch (_) {
      return null;
    }
  }

  static bool _has(List<String> models, String name) =>
      name.isNotEmpty &&
      !_cloudModel(name) &&
      (models.contains(name) || models.contains('$name:latest'));

  static bool _cloudModel(String name) =>
      RegExp(r'(^|[:/\-])cloud($|[:/\-])', caseSensitive: false).hasMatch(name);

  static const pingConnected = 'Connected to Ollama on your laptop.';

  /// For Settings: is Ollama reachable and are the configured models installed?
  static Future<String> ping() async {
    final models = await _models();
    if (models == null) {
      return 'Not connected. Check the laptop IP address and that Ollama runs '
          'with OLLAMA_HOST=0.0.0.0 on the same Wi-Fi or hotspot.';
    }
    String line(String label, String m) => _has(models, m)
        ? '$label model: $m (installed)'
        : '$label model: "$m" is not installed';
    return '$pingConnected\n${line('Text', Store.ollamaModel)}\n${line('Vision', Store.visionModel)}'
        '\nAvailable: ${models.isEmpty ? '(none)' : models.join(', ')}';
  }
}
