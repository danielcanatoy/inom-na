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
    4: RegExp(r'\b(?:q\.?i\.?d\.?|4x|4\s*times)\b', caseSensitive: false),
    3: RegExp(r'\b(?:t\.?i\.?d\.?|3x|thrice|3\s*times)\b',
        caseSensitive: false),
    2: RegExp(r'\b(?:b\.?i\.?d\.?|2x|twice|2\s*times)\b', caseSensitive: false),
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
  static final _maint = RegExp(r'\b(maintenance|indefinitely|tuloy.tuloy)\b',
      caseSensitive: false);
  static final _stock =
      RegExp(r'(?:#|qty\.?:?|no\.)\s*(\d{1,4})\b', caseSensitive: false);
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
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = _medLine.firstMatch(line);
      final name =
          match == null ? _bareName(line) : _cleanName(match.group(1)!);
      if (name != null && name.length >= 3 && !_notName.hasMatch(name)) {
        final dose = match?.group(2)?.replaceAll(' ', '') ?? '';
        final negativeDose = match != null &&
            RegExp(r'-\s*\d').hasMatch(line.substring(0, match.end));
        current = _Draft(name, negativeDose ? '-$dose' : dose);
        drafts.add(current);
        final directions =
            match == null ? '' : line.substring(match.end).trim();
        if (directions.isNotEmpty) _apply(current, directions);
      } else if (current != null) {
        _apply(current, line);
      }
    }
    return [for (var i = 0; i < drafts.length; i++) _medicine(drafts[i], i)];
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
    for (final entry in _daily.entries) {
      if (entry.value.hasMatch(line)) draft.frequencies.add(entry.key);
    }
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

  static String _cleanName(String value) => value
      .replaceAll(
          RegExp(r'^\s*(\d+[\.\)]|rx:?|r/)\s*', caseSensitive: false), '')
      .trim();
}

class _Draft {
  _Draft(this.name, this.dose);
  final String name;
  final String dose;
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
