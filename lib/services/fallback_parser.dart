import '../models/medicine.dart';
import 'med_names.dart';
import 'review_note.dart';

/// Conservative phone-only parsing. Unknown directions remain unresolved.
class FallbackParser {
  static final _medLine = RegExp(
    r'([A-Za-z][A-Za-z\-\+ ]{2,40}?)\s*(\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu)(?:\s*/\s*\d+(?:\.\d+)?\s*(?:mg|ml))?)',
    caseSensitive: false,
  );
  static final _qHours = RegExp(
    r'\b(?:q\s*(\d{1,3})\s*h|every\s+(\d{1,3})\s*hours?)\b',
    caseSensitive: false,
  );
  static final _daily = <int, RegExp>{
    4: RegExp(r'\b(?:q\.?i\.?d\.?|4x|4\s*times|four\s*times)\b',
        caseSensitive: false),
    3: RegExp(r'\b(?:t\.?i\.?d\.?|3x|thrice|3\s*times|three\s*times)\b',
        caseSensitive: false),
    2: RegExp(r'\b(?:b\.?i\.?d\.?|2x|twice|2\s*times|two\s*times)\b',
        caseSensitive: false),
    1: RegExp(r'\b(?:o\.?d\.?|q\.?d\.?|once|1x|daily|isang\s*beses)\b',
        caseSensitive: false),
  };
  static final _bed = RegExp(r'\b(hs|bedtime|at\s*night|bago\s*matulog)\b',
      caseSensitive: false);
  static final _prn = RegExp(
      r'\b(prn|as\s*needed|kung\s*kailangan|kapag\s*kailangan)\b',
      caseSensitive: false);
  static final _days = RegExp(
      r'(?:x|for|sa\s*loob\s*ng)?\s*(\d{1,3})\s*(days?|araw|weeks?|wks?|linggo)\b',
      caseSensitive: false);
  // "Continue" alone does not establish an indefinite prescription.
  // "Continue" alone stays unresolved; an explicit "ongoing"/"long-term"
  // duration is accepted and still requires user verification.
  static final _maint = RegExp(
      r'\b(maintenance|indefinitely|tuloy.tuloy|ongoing|long[\s-]?term)\b',
      caseSensitive: false);
  static final _stock = RegExp(
      r'(?:#|qty\.?:?|quantity\s*:?|disp\.?\s*:?|no\.)\s*#?\s*(\d{1,4})\b',
      caseSensitive: false);

  /// "Medicine:", "Medication:", "Drug:", "Generic name:" label prefixes.
  static final _label = RegExp(
      r'^\s*(?:medicine|medication|drug|generic(?:\s+name)?|brand(?:\s+name)?)'
      r'\s*[:\-]\s*',
      caseSensitive: false);
  static final _qty = RegExp(
      r'(1/2|½|\d+(?:\.\d+)?)\s*(tabs?|tablets?|caps?|capsules?|tsp|ml|puffs?|drops?)\b',
      caseSensitive: false);
  static final _ac =
      RegExp(r'\b(ac|before\s*meals?|bago\s*kumain)\b', caseSensitive: false);
  static final _pc = RegExp(
      r'\b(pc|after\s*meals?|pagkatapos\s*kumain|with\s*food)\b',
      caseSensitive: false);
  static final _notName =
      RegExp(r'^(sig|take|inumin|rx|qty|no)\b', caseSensitive: false);
  static final _clock = RegExp(
      r'\b(\d{1,2}):(\d{2})\s*(am|pm)?\b|\b(\d{1,2})\s*(am|pm)\b',
      caseSensitive: false);
  static final _complex = RegExp(
      r'\b(alternate|every\s+other|weekly|monthly|taper|except|skip|then|every\s+(morning|evening)|tuwing\s+makalawa)\b',
      caseSensitive: false);
  static final _unclearInterval =
      RegExp(r'\bq\s*(?:[a-z?]+\s*h|\d+[.,]\d+\s*h)\b', caseSensitive: false);

  static final _odAbbreviation =
      RegExp(r'\bo\.?d\.?(?![a-z])', caseSensitive: false);

  /// Timing words in the written directions. Used only to pre-select a
  /// routine suggestion that the user must review before it is applied.
  static ({bool bedtime, bool beforeMeals, bool afterMeals}) timingHints(
          String directions) =>
      (
        bedtime: _bed.hasMatch(directions),
        beforeMeals: _ac.hasMatch(directions),
        afterMeals: _pc.hasMatch(directions),
      );

  static List<Medicine> parse(String text) {
    final drafts = <_Draft>[];
    _Draft? current;
    final lines = [
      for (final raw in text.split('\n'))
        if (raw.trim().isNotEmpty) raw.trim()
    ];
    for (var i = 0; i < lines.length; i++) {
      final original = lines[i];
      // Tolerate common phone-OCR misreads (e.g. "5OOmg", "500 rng") and
      // brand names in brackets, only for finding the medicine line.
      final (line, unclear) = _normalizeOcr(original);
      final match = _medLine.firstMatch(line);
      var name = match == null ? _bareName(line) : _cleanName(match.group(1)!);
      var dose = match?.group(2)?.replaceAll(' ', '') ?? '';
      var consumedNext = false;
      if (match == null &&
          (name != null || _plausibleName(line)) &&
          i + 1 < lines.length) {
        // Name and strength on separate lines (common in OCR layouts).
        final (nextLine, nextUnclear) = _normalizeOcr(lines[i + 1]);
        final strength = _strengthOnly.firstMatch(nextLine);
        if (strength != null) {
          name ??= _cleanName(line);
          dose = strength.group(1)!.replaceAll(' ', '');
          consumedNext = true;
          if (nextUnclear.isNotEmpty) unclear.add(dose);
        }
      }
      if (name != null && name.length >= 3 && !_notName.hasMatch(name)) {
        final negativeDose = match != null &&
            RegExp(r'-\s*\d').hasMatch(line.substring(0, match.end));
        current = _Draft(name, negativeDose ? '-$dose' : dose)
          ..unclearStrength = unclear.isNotEmpty;
        drafts.add(current);
        final directions =
            match == null ? '' : line.substring(match.end).trim();
        if (directions.isNotEmpty) _apply(current, directions);
        if (consumedNext) i++;
      } else if (current != null) {
        // A strength on the line after a bare known name belongs to it.
        final strength = _strengthOnly.firstMatch(line);
        if (strength != null && current.dose.isEmpty) {
          current.dose = strength.group(1)!.replaceAll(' ', '');
          if (unclear.isNotEmpty) current.unclearStrength = true;
          continue;
        }
        _apply(current, original);
      }
    }
    return [for (var i = 0; i < drafts.length; i++) _medicine(drafts[i], i)];
  }

  /// A line that is only a strength, e.g. "500mg" or "250 mg capsule".
  static final _strengthOnly = RegExp(
      r'^\W*(\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu)(?:\s*/\s*\d+(?:\.\d+)?\s*(?:mg|ml))?)'
      r'(?:\s*(?:tabs?|tablets?|caps?|capsules?))?\W*$',
      caseSensitive: false);

  /// Words that start header lines, never medicine names.
  static final _headerWord = RegExp(
      r'^(patient|name|date|age|sex|address|doctor|dr|md|clinic|hospital|'
      r'lic|license|ptr|s2|sample|demo|signature|rx|sig|qty|no|tel|phone)\b',
      caseSensitive: false);

  /// One to three words of letters that could be an (unlisted) medicine name.
  static bool _plausibleName(String line) =>
      !line.contains(':') &&
      !_headerWord.hasMatch(_cleanName(line)) &&
      RegExp(r'^[A-Za-z][A-Za-z\-]{3,}(?:\s+[A-Za-z][A-Za-z\-]+){0,2}$')
          .hasMatch(_cleanName(line));

  /// Fixes OCR look-alikes inside strengths only (O→0, l/I→1, "rng"→"mg")
  /// and drops bracketed brand names. Returns the strengths that needed
  /// fixing so they can be flagged for review; never applied silently.
  static (String, List<String>) _normalizeOcr(String line) {
    final unclear = <String>[];
    var result = line
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceFirst(_label, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    // Digits misread together with the unit, e.g. "5OO rng" -> "500mg".
    result = result.replaceAllMapped(
        RegExp(r'\b([0-9OolI|]*\d[0-9OolI|]*)\s*(rng|rnq|mq|nng)\b',
            caseSensitive: false), (m) {
      unclear.add(m[0]!);
      return '${m[1]!.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[lI|]'), '1')}mg';
    });
    result = result.replaceAllMapped(
        RegExp(r'(\d)\s*(rng|rnq|mq|nng)\b', caseSensitive: false), (m) {
      unclear.add(m[0]!);
      return '${m[1]}mg';
    });
    result = result.replaceAllMapped(
        RegExp(r'\b([0-9OolI|]*\d[0-9OolI|]*)(\s*)(mg|mcg|g|ml|iu)\b',
            caseSensitive: false), (m) {
      final digits = m[1]!
          .replaceAll(RegExp('[Oo]'), '0')
          .replaceAll(RegExp('[lI|]'), '1');
      if (digits != m[1]) unclear.add(m[0]!);
      return '$digits${m[2]}${m[3]}';
    });
    return (result.replaceAll(RegExp(r'\s{2,}'), ' ').trim(), unclear);
  }

  static Medicine _medicine(_Draft draft, int index) {
    final notes = <String>[];
    final intervals = draft.intervals;
    final frequencies = draft.frequencies;
    var kind = ScheduleKind.unknown;
    int? frequency;
    int? interval;
    var times = [...draft.times];
    final conflict = intervals.length > 1 ||
        frequencies.length > 1 ||
        (intervals.length == 1 &&
            frequencies.isNotEmpty &&
            (24 % intervals.first != 0 ||
                frequencies.first != 24 ~/ intervals.first));
    if (conflict) {
      notes.add(
          '${ReviewNote.conflict} the written frequency is contradictory. Correct it using the prescription or ask your pharmacist.');
    } else if (draft.prn) {
      kind = ScheduleKind.prn;
      interval = intervals.isEmpty ? null : intervals.single;
      if (interval != null)
        notes.add(
            'As needed (PRN): keep the written minimum interval of $interval hours. No automatic reminders.');
    } else if (intervals.isNotEmpty) {
      kind = ScheduleKind.interval;
      interval = intervals.single;
      if (times.isNotEmpty)
        notes.add(
            'Clock times are written. Set the first dose to match them before saving.');
      if (times.length > 1) {
        final sorted = [...times]..sort();
        final minutes = [
          for (final time in sorted)
            int.parse(time.split(':')[0]) * 60 + int.parse(time.split(':')[1])
        ];
        final consistent = 24 % interval == 0 &&
            minutes.length == 24 ~/ interval &&
            List.generate(
                minutes.length,
                (index) =>
                    (minutes[(index + 1) % minutes.length] -
                        minutes[index] +
                        1440) %
                    1440).every((gap) => gap == interval! * 60);
        if (!consistent) {
          kind = ScheduleKind.unknown;
          notes.add(
              '${ReviewNote.mismatch} the written clock times do not fit the dose interval.');
        }
      }
    } else if (times.isNotEmpty) {
      kind = ScheduleKind.explicit;
      frequency = times.length;
      if (frequencies.isNotEmpty && frequencies.single != times.length) {
        kind = ScheduleKind.unknown;
        notes.add(
            '${ReviewNote.mismatch} the number of written times does not match the frequency.');
      }
    } else if (frequencies.isNotEmpty) {
      kind = ScheduleKind.daily;
      frequency = frequencies.single;
      times = Medicine.defaultTimes(frequency, bedtime: draft.bedtime);
    }
    if (draft.unclearStrength) {
      notes.add('Some characters in the strength were unclear in the scan '
          'and were read as ${draft.dose}. Check it against the '
          'prescription.');
    }
    if (draft.odAbbreviation) {
      notes
          .add('"OD" usually means once a day, but on eye prescriptions it can '
              'mean the right eye. Check your prescription.');
    }
    if (draft.duplicateTime)
      notes.add(
          'The same clock time is written more than once. Check the schedule.');
    if (draft.invalidTime) {
      kind = ScheduleKind.unknown;
      notes.add(
          '${ReviewNote.invalid} a written clock time is not a valid time.');
    }
    if (draft.invalidInterval || draft.complexTiming) {
      kind = ScheduleKind.unknown;
      notes.add(
          '${ReviewNote.unclear} some timing directions are unclear or not supported. Correct the schedule and check the original directions.');
    }
    if (draft.quantities.length > 1 || draft.invalidQuantity)
      notes.add(
          '${ReviewNote.conflict} the amount per dose is contradictory or invalid.');
    if (draft.beforeMeal || draft.afterMeal) {
      notes.add(
          'Check that the chosen times are ${draft.beforeMeal ? 'before' : 'after'} meals. Times are not adjusted to meals automatically.');
    }
    if (draft.beforeMeal && draft.afterMeal) {
      kind = ScheduleKind.unknown;
      notes.add(
          '${ReviewNote.conflict} both before-meal and after-meal directions are written.');
    }
    final durationConflict =
        (draft.maintenance && draft.durations.isNotEmpty) ||
            draft.durations.length > 1;
    if (durationConflict) notes.add(ReviewNote.durationConflict);
    final days = !durationConflict && draft.durations.length == 1
        ? draft.durations.single
        : null;
    return Medicine(
      id: '${Medicine.newId()}$index',
      name: draft.name,
      dose: draft.dose,
      qtyPerIntake: !draft.invalidQuantity && draft.quantities.length == 1
          ? draft.quantities.single
          : 0,
      scheduleKind: kind,
      frequencyPerDay: frequency,
      intervalHours: interval,
      times: times,
      days: days,
      durationConfirmed:
          !durationConflict && (days != null || draft.maintenance),
      instructions: draft.directions.join('\n'),
      stock: draft.stock,
      reviewNotes: notes,
    );
  }

  static void _apply(_Draft draft, String line) {
    draft.directions.add(line);
    for (final match in _qHours.allMatches(line)) {
      final hours = int.parse(match.group(1) ?? match.group(2)!);
      if (hours > 0 && hours <= 168) {
        draft.intervals.add(hours);
      } else {
        draft.invalidInterval = true;
      }
    }
    final found = <int>{
      for (final entry in _daily.entries)
        if (entry.value.hasMatch(line)) entry.key
    };
    // "twice daily"/"three times daily": the word "daily" belongs to the
    // stated count and is not a separate once-daily instruction.
    if (found.length > 1 &&
        found.contains(1) &&
        !RegExp(r'\b(?:o\.?d\.?|q\.?d\.?|once|1x|isang\s*beses)\b',
                caseSensitive: false)
            .hasMatch(line)) {
      found.remove(1);
    }
    draft.frequencies.addAll(found);
    if (_bed.hasMatch(line)) {
      draft.bedtime = true;
      draft.frequencies.add(1);
    }
    if (_prn.hasMatch(line)) draft.prn = true;
    if (_odAbbreviation.hasMatch(line)) draft.odAbbreviation = true;
    if (_maint.hasMatch(line)) draft.maintenance = true;
    for (final match in _days.allMatches(line)) {
      final count = int.parse(match.group(1)!);
      final unit = match.group(2)!.toLowerCase();
      draft.durations
          .add((unit.startsWith('w') || unit == 'linggo') ? count * 7 : count);
    }
    final stock = _stock.firstMatch(line);
    if (stock != null) draft.stock ??= int.parse(stock.group(1)!);
    for (final quantity in _qty.allMatches(line)) {
      final value = quantity.group(1)!;
      final parsed =
          value == '1/2' || value == '½' ? 0.5 : double.tryParse(value);
      if (parsed != null) draft.quantities.add(parsed);
      if (RegExp(r'-\s*$').hasMatch(line.substring(0, quantity.start))) {
        draft.invalidQuantity = true;
      }
    }
    for (final match in _clock.allMatches(line)) {
      var hour = int.parse(match.group(1) ?? match.group(4)!);
      final minute = int.parse(match.group(2) ?? '0');
      final meridiem = (match.group(3) ?? match.group(5))?.toLowerCase();
      if (minute > 59 ||
          (meridiem == null ? hour > 23 : hour < 1 || hour > 12)) {
        draft.invalidTime = true;
        continue;
      }
      if (meridiem != null) hour = hour % 12 + (meridiem == 'pm' ? 12 : 0);
      final time =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      if (draft.times.contains(time)) draft.duplicateTime = true;
      draft.times.add(time);
    }
    draft.beforeMeal |= _ac.hasMatch(line);
    draft.afterMeal |= _pc.hasMatch(line);
    draft.complexTiming |= _complex.hasMatch(line);
    draft.invalidInterval |= _unclearInterval.hasMatch(line);
  }

  static String? _bareName(String line) {
    final cleaned = _cleanName(line);
    // A known bare medicine still has unresolved strength, quantity and timing.
    for (final name in MedNames.common) {
      if (cleaned.toLowerCase() == name.toLowerCase()) return cleaned;
    }
    return null;
  }

  static String _cleanName(String value) {
    final name = value
        .replaceFirst(_label, '')
        .replaceAll(
            RegExp(r'^\s*(\d+[\.\)]|rx:?|r/)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // OCR may join a header onto the medicine line ("... USE Amoxicillin").
    // Start the name at a listed medicine if one is present, otherwise keep
    // at most the last two words of a long run. Never substitutes a name.
    final words = name.split(' ');
    if (words.length <= 2) return name;
    for (var i = 0; i < words.length; i++) {
      final rest = words.sublist(i).join(' ').toLowerCase();
      if (MedNames.common
          .any((known) => rest.startsWith(known.toLowerCase()))) {
        return words.sublist(i).join(' ');
      }
    }
    return words.length > 3 ? words.sublist(words.length - 2).join(' ') : name;
  }
}

class _Draft {
  _Draft(this.name, this.dose);
  final String name;
  String dose;
  bool unclearStrength = false;
  final Set<int> frequencies = {};
  final Set<int> intervals = {};
  final Set<int> durations = {};
  final List<String> times = [];
  final List<String> directions = [];
  final Set<double> quantities = {};
  int? stock;
  bool bedtime = false;
  bool odAbbreviation = false;
  bool prn = false;
  bool maintenance = false;
  bool beforeMeal = false;
  bool afterMeal = false;
  bool invalidTime = false;
  bool duplicateTime = false;
  bool invalidInterval = false;
  bool complexTiming = false;
  bool invalidQuantity = false;
}
