import 'routine.dart';

/// Daily frequency and fixed-hour intervals have different prescription meanings.
enum ScheduleKind { unknown, daily, interval, explicit, prn }

/// One prescribed medication and its schedule.
class Medicine {
  Medicine({
    required this.id,
    required this.name,
    this.dose = '',
    this.qtyPerIntake = 0,
    List<String>? times,
    this.days,
    this.instructions = '',
    this.stock,
    DateTime? start,
    List<String>? taken,
    Map<String, DateTime>? takenAt,
    this.scheduleKind = ScheduleKind.unknown,
    this.frequencyPerDay,
    this.intervalHours,
    this.durationConfirmed = false,
    this.end,
    List<String>? reviewNotes,
    this.legacy = false,
    this.routineLink,
    List<ScheduleRevision>? revisions,
    this.sourceText,
  })  : times = List<String>.of(times ?? []),
        start = start ?? DateTime.now(),
        taken = (taken ?? []).toSet().toList(),
        takenAt = Map<String, DateTime>.of(takenAt ?? {}),
        reviewNotes = List<String>.of(reviewNotes ?? []),
        revisions = List<ScheduleRevision>.of(revisions ?? []);

  String id;
  String name;
  String dose;
  double qtyPerIntake;
  List<String> times; // Valid HH:mm clock times; not an interval approximation.
  int? days;
  String instructions;
  int? stock;
  DateTime start;
  List<String> taken; // Scheduled keys, never actual intake timestamps.

  /// Actual confirmation time for doses marked taken in Phase 4 or later,
  /// keyed like [taken]. Older taken keys have no entry: their actual intake
  /// time is unknown and is never invented.
  Map<String, DateTime> takenAt;

  /// When the user confirmed [scheduled] as taken, if that was recorded.
  DateTime? takenTimeOf(DateTime scheduled) => takenAt[keyOf(scheduled)];
  ScheduleKind scheduleKind;
  int? frequencyPerDay;
  int? intervalHours;
  bool durationConfirmed;
  DateTime? end; // Exclusive end of the prescribed schedule.
  List<String> reviewNotes;
  bool legacy; // Preserve already-saved legacy course bounds and dose keys.

  /// Set when the reminder times were generated from My Daily Routine; null
  /// for prescribed, interval or customized times.
  RoutineLink? routineLink;

  /// The prescription text as originally recognized or typed (evidence).
  /// Set once when first saved; edits to [instructions] never change it.
  String? sourceText;

  /// Earlier schedule rules, oldest first. Each applies to doses before its
  /// `until`; the fields above are the current rule from the last `until`.
  /// Edits never rewrite past doses or taken records.
  List<ScheduleRevision> revisions;

  /// When the medication course began (before any schedule edits).
  DateTime get originalStart =>
      revisions.isEmpty ? start : revisions.first.medicine.start;

  /// When the current schedule rule took effect.
  DateTime? get currentRuleFrom =>
      revisions.isEmpty ? null : revisions.last.until;

  Medicine copy() => Medicine.fromJson(toJson());

  int get timesPerDay => scheduleKind == ScheduleKind.interval
      ? (intervalHours != null && intervalHours! > 0
          ? (24 / intervalHours!).ceil()
          : 0)
      : times.length;

  bool get isMaintenance => durationConfirmed && days == null && end == null;
  bool get isPrn => scheduleKind == ScheduleKind.prn;

  String get qtyLabel {
    if (!qtyPerIntake.isFinite || qtyPerIntake <= 0) return '?';
    return qtyPerIntake == qtyPerIntake.roundToDouble()
        ? qtyPerIntake.toInt().toString()
        : qtyPerIntake.toString();
  }

  String get frequencyLabel {
    if (isPrn) return 'As needed (PRN)';
    if (scheduleKind == ScheduleKind.unknown) return 'Frequency: needs review';
    final count = times.length;
    final frequency = scheduleKind == ScheduleKind.interval
        ? 'Every ${intervalHours ?? "?"} hours'
        : count == 1
            ? 'Once a day'
            : count == 2
                ? 'Twice a day'
                : '$count times a day';
    if (!durationConfirmed) return '$frequency · duration needs review';
    if (isMaintenance) return '$frequency · ongoing (maintenance)';
    if (days != null) {
      return '$frequency · for $days ${days == 1 ? "day" : "days"}';
    }
    return '$frequency · until an end date';
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  static bool validTime(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    return match != null &&
        int.parse(match[1]!) < 24 &&
        int.parse(match[2]!) < 60;
  }

  /// This application's dose field expects a numeric strength or administration
  /// amount with units. Unreadable text and zero/negative values need correction.
  static bool validDose(String value) {
    if (RegExp(r'-\s*\d').hasMatch(value)) return false;
    final amounts = RegExp(
      r'(\d+(?:\.\d+)?|\.\d+)\s*(?:mcg|µg|ug|mg|ml|g|iu|units?|%|tablets?|tabs?|capsules?|caps?|drops?|puffs?|patches|patch|milligrams?|milliliters?)(?:\b|$)',
      caseSensitive: false,
    ).allMatches(value).toList();
    return amounts.isNotEmpty &&
        amounts.every((amount) {
          final quantity = double.tryParse(amount[1]!);
          return quantity != null && quantity.isFinite && quantity > 0;
        });
  }

  static DateTime atTime(DateTime day, String hhmm) {
    if (!validTime(hhmm)) throw const FormatException('Invalid HH:mm time');
    final parts = hhmm.split(':');
    return DateTime(
        day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  static String keyOf(DateTime dt) =>
      '${dt.year}-${_2(dt.month)}-${_2(dt.day)} ${_2(dt.hour)}:${_2(dt.minute)}';
  static String _2(int value) => value.toString().padLeft(2, '0');

  /// Stable across reloads and rescheduling. Includes the medicine identity.
  String doseId(DateTime scheduled) => '$id|${keyOf(scheduled)}';

  bool isTaken(DateTime scheduled) => taken.contains(keyOf(scheduled));

  /// Returns false for a repeated action, so reminders/storage need not update.
  /// [at] is the actual confirmation time. A repeated confirmation keeps the
  /// first record; undo removes only this dose's record.
  bool markTaken(DateTime scheduled, {bool value = true, DateTime? at}) {
    final key = keyOf(scheduled);
    final present = taken.contains(key);
    if (value == present) return false;
    if (value) {
      taken.add(key);
      if (at != null) takenAt[key] = at;
    } else {
      taken.removeWhere((item) => item == key);
      takenAt.remove(key);
    }
    return true;
  }

  /// Suggested clock times ONLY for a verified general daily frequency.
  /// Never use these to approximate q6h/q8h or an unknown frequency.
  static List<String> defaultTimes(int perDay, {bool bedtime = false}) {
    if (perDay <= 0 || perDay > 24) return [];
    if (bedtime && perDay == 1) return ['21:00'];
    switch (perDay) {
      case 1:
        return ['08:00'];
      case 2:
        return ['08:00', '20:00'];
      case 3:
        return ['08:00', '14:00', '20:00'];
      case 4:
        return ['06:00', '12:00', '18:00', '22:00'];
      default:
        return List.generate(perDay, (index) {
          final minute = (360 + (index * 1440 ~/ perDay)) % 1440;
          return '${_2(minute ~/ 60)}:${_2(minute % 60)}';
        });
    }
  }

  /// Structural schedule checks apply to both new and legacy records.
  List<String> scheduleErrors() {
    final errors = <String>[];
    if (scheduleKind == ScheduleKind.unknown) {
      errors.add('Choose how often or at what times to take this medication.');
    }
    if (!durationConfirmed) {
      errors.add(
          'Confirm how long to take this medication. It is not assumed to be ongoing.');
    }
    if (days != null && (days! <= 0 || days! > 3650)) {
      errors.add('The number of days must be between 1 and 3650.');
    }
    if (end != null && !end!.isAfter(start)) {
      errors.add('The end must be later than the start.');
    }
    if (end != null && end!.difference(start) > const Duration(days: 3650)) {
      errors.add('The end cannot be more than 3650 days after the start.');
    }
    if (days != null && end != null) {
      errors.add('Use either a number of days or an end date, not both.');
    }
    if (scheduleKind == ScheduleKind.interval) {
      if (intervalHours == null ||
          intervalHours! <= 0 ||
          intervalHours! > 168) {
        errors.add('The dose interval must be between 1 and 168 hours.');
      }
      if (times.any((time) => !validTime(time)) ||
          times.toSet().length != times.length) {
        errors.add('Check the first-dose time that was read.');
      }
    }
    if (scheduleKind == ScheduleKind.daily ||
        scheduleKind == ScheduleKind.explicit) {
      if (times.isEmpty ||
          times.length > 24 ||
          times.any((t) => !validTime(t))) {
        errors.add('Add at least one valid time (HH:mm).');
      }
      if (times.toSet().length != times.length) {
        errors.add('The same time cannot be added twice.');
      }
      if (scheduleKind == ScheduleKind.daily &&
          (frequencyPerDay == null ||
              frequencyPerDay! <= 0 ||
              frequencyPerDay! > 24 ||
              frequencyPerDay != times.length)) {
        errors.add('The times per day must match the number of times added.');
      }
    }
    return errors;
  }

  List<String> validationErrors() => [
        if (id.trim().isEmpty) 'This medication has no identifier.',
        if (name.trim().isEmpty) 'Enter the medication name.',
        if (!validDose(dose))
          'Enter the strength with a number and unit (for example, 500 mg).',
        if (!qtyPerIntake.isFinite || qtyPerIntake <= 0)
          'Enter a valid amount per dose (for example, 1 or 0.5).',
        if (stock != null && stock! < 0) 'Stock cannot be negative.',
        ...scheduleErrors(),
      ];

  int? get _legacyTotal =>
      legacy && days != null && !isPrn ? days! * times.length : null;

  DateTime? get _legacyLastDose {
    final total = _legacyTotal;
    if (total == null || total <= 0 || scheduleErrors().isNotEmpty) return null;
    final sorted = [...times]..sort();
    final day = DateTime(start.year, start.month, start.day);
    final cutoff = start.subtract(const Duration(minutes: 30));
    final firstDay = sorted
        .map((time) => atTime(day, time))
        .where((dose) => !dose.isBefore(cutoff))
        .toList();
    if (total <= firstDay.length) return firstDay[total - 1];
    final remainingIndex = total - firstDay.length - 1;
    final lastDay = DateTime(
        day.year, day.month, day.day + 1 + remainingIndex ~/ sorted.length);
    return atTime(lastDay, sorted[remainingIndex % sorted.length]);
  }

  DateTime? get scheduleEnd {
    if (scheduleErrors().isNotEmpty) return null;
    if (!durationConfirmed || isMaintenance) return null;
    if (legacy && _legacyTotal != null) {
      return _legacyLastDose?.add(const Duration(minutes: 1));
    }
    return end ?? (days == null ? null : start.add(Duration(days: days!)));
  }

  /// Generates doses no later than horizon and strictly before scheduleEnd.
  /// [from] queries upcoming doses without rebuilding history.
  /// [limit] is opt-in for callers detecting capacity overflow, not a reminder
  /// horizon policy: they must explicitly report when planned doses exceed it.
  /// Legacy finite records retain their original dose count and dose keys.
  List<DateTime> allDoses({
    required DateTime horizon,
    DateTime? from,
    int? limit,
  }) {
    if (limit != null && limit <= 0) return [];
    if (revisions.isEmpty) {
      return _ruleDoses(horizon: horizon, from: from, limit: limit);
    }
    // Earlier rules produce the doses before each revision boundary; the
    // current rule produces the rest. Segments never overlap.
    final out = <DateTime>[];
    DateTime? segmentStart;
    for (final revision in revisions) {
      final lower = _later(from, segmentStart);
      final segmentHorizon =
          horizon.isBefore(revision.until) ? horizon : revision.until;
      for (final dose in revision.medicine
          ._ruleDoses(horizon: segmentHorizon, from: lower)) {
        if (!dose.isBefore(revision.until)) break;
        out.add(dose);
        if (limit != null && out.length >= limit) return out;
      }
      segmentStart = revision.until;
      if (horizon.isBefore(revision.until)) return out;
    }
    out.addAll(_ruleDoses(
        horizon: horizon,
        from: _later(from, segmentStart),
        limit: limit == null ? null : limit - out.length));
    return out;
  }

  static DateTime? _later(DateTime? a, DateTime? b) =>
      a == null ? b : (b == null || a.isAfter(b) ? a : b);

  /// Doses of the current rule only.
  List<DateTime> _ruleDoses({
    required DateTime horizon,
    DateTime? from,
    int? limit,
  }) {
    if (limit != null && limit <= 0) return [];
    if (isPrn || scheduleErrors().isNotEmpty) return [];
    var cutoff = legacy ? start.subtract(const Duration(minutes: 30)) : start;
    final startDay = DateTime(start.year, start.month, start.day);
    if (legacy && cutoff.isBefore(startDay)) cutoff = startDay;
    final lower = from != null && from.isAfter(cutoff) ? from : cutoff;
    if (horizon.isBefore(lower)) return [];
    final stop = scheduleEnd;
    if (stop != null && !lower.isBefore(stop)) return [];
    final out = <DateTime>[];

    if (scheduleKind == ScheduleKind.interval) {
      final interval = Duration(hours: intervalHours!);
      final elapsed = lower.difference(start).inMicroseconds;
      final index = elapsed <= 0
          ? 0
          : (elapsed + interval.inMicroseconds - 1) ~/ interval.inMicroseconds;
      var scheduled = start.add(interval * index);
      while (!scheduled.isAfter(horizon) &&
          (stop == null || scheduled.isBefore(stop))) {
        out.add(scheduled);
        if (limit != null && out.length >= limit) return out;
        scheduled = scheduled.add(interval);
      }
      return out;
    }

    final sorted = [...times]..sort();
    var day = DateTime(lower.year, lower.month, lower.day);
    while (!day.isAfter(horizon)) {
      for (final time in sorted) {
        final scheduled = atTime(day, time);
        if (scheduled.isBefore(lower)) continue;
        if (scheduled.isAfter(horizon) ||
            (stop != null && !scheduled.isBefore(stop))) {
          return out;
        }
        out.add(scheduled);
        if (limit != null && out.length >= limit) return out;
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return out;
  }

  /// The final scheduled dose of a finite course (null if ongoing or PRN).
  /// Clearer for people than the exclusive [scheduleEnd].
  DateTime? get lastDose {
    final stop = scheduleEnd;
    if (stop == null || isPrn) return null;
    final doses = allDoses(horizon: stop);
    return doses.isEmpty ? null : doses.last;
  }

  int? get totalDoses {
    if (revisions.isNotEmpty) {
      // Past rules count their actual doses; the current rule continues to
      // the unchanged end of the course.
      if (scheduleErrors().isNotEmpty) return null;
      final stop = scheduleEnd;
      if (stop == null && !isPrn) return null;
      return allDoses(horizon: stop ?? revisions.last.until).length;
    }
    if (isPrn) return 0;
    if (scheduleErrors().isNotEmpty) return null;
    final stop = scheduleEnd;
    if (stop == null) return null;
    if (_legacyTotal != null) return _legacyTotal;
    if (scheduleKind == ScheduleKind.interval) {
      final duration = stop.difference(start).inMicroseconds;
      final interval = Duration(hours: intervalHours!).inMicroseconds;
      return (duration + interval - 1) ~/ interval;
    }
    return allDoses(horizon: stop).length;
  }

  /// End of planned treatment is independent of whether any dose was taken.
  bool get isFinished {
    final stop = scheduleEnd;
    return stop != null && !DateTime.now().isBefore(stop);
  }

  /// Applies [next]'s schedule rule from [effectiveFrom] onwards. Doses before
  /// [effectiveFrom] keep their original rule and times, and taken records,
  /// identity and history are preserved. [next] must start at or after
  /// [effectiveFrom]. This medicine is not modified.
  Medicine withScheduleFrom(Medicine next, DateTime effectiveFrom) {
    final kept = <ScheduleRevision>[];
    DateTime? segmentStart;
    var currentRuleApplies = true;
    for (final revision in revisions) {
      if (!revision.until.isAfter(effectiveFrom)) {
        kept.add(revision);
        segmentStart = revision.until;
        continue;
      }
      // An earlier rule still running at the change point is cut there.
      if (segmentStart == null || segmentStart.isBefore(effectiveFrom)) {
        kept.add(ScheduleRevision(until: effectiveFrom, rule: revision.rule));
      }
      currentRuleApplies = false;
      break;
    }
    if (currentRuleApplies &&
        _ruleDoses(horizon: effectiveFrom, from: segmentStart)
            .any((dose) => dose.isBefore(effectiveFrom))) {
      kept.add(ScheduleRevision(until: effectiveFrom, rule: ruleJson()));
    }
    return Medicine.fromJson(next.toJson())
      ..id = id
      ..taken = List<String>.of(taken)
      ..takenAt = Map<String, DateTime>.of(takenAt)
      ..revisions = kept;
  }

  /// This medicine's current schedule rule, without history.
  Map<String, dynamic> ruleJson() => toJson()
    ..remove('taken')
    ..remove('takenAt')
    ..remove('revisions')
    ..remove('routineLink')
    ..remove('sourceText');

  bool get allTaken {
    final stop = scheduleEnd;
    if (stop == null || isPrn) return false;
    final doses = allDoses(horizon: stop);
    final takenKeys = taken.toSet();
    return doses.isNotEmpty &&
        doses.every((scheduled) => takenKeys.contains(keyOf(scheduled)));
  }

  double? get daysLeft {
    if (stock == null || isPrn || qtyPerIntake <= 0 || !qtyPerIntake.isFinite) {
      return null;
    }
    final daily = scheduleKind == ScheduleKind.interval && intervalHours != null
        ? 24 / intervalHours!
        : times.length.toDouble();
    if (daily <= 0) return null;
    final remaining = stock! - taken.toSet().length * qtyPerIntake;
    return remaining / (daily * qtyPerIntake);
  }

  bool get needsRefill {
    if (stock == null || isPrn || qtyPerIntake <= 0) return false;
    final total = totalDoses;
    if (total != null && stock! >= total * qtyPerIntake) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'id': id,
        'name': name,
        'dose': dose,
        'qtyPerIntake': qtyPerIntake,
        'times': times,
        'days': days,
        'instructions': instructions,
        'stock': stock,
        'start': start.toIso8601String(),
        'taken': taken.toSet().toList(),
        if (takenAt.isNotEmpty)
          'takenAt': takenAt
              .map((key, value) => MapEntry(key, value.toIso8601String())),
        'scheduleKind': scheduleKind.name,
        'frequencyPerDay': frequencyPerDay,
        'intervalHours': intervalHours,
        'durationConfirmed': durationConfirmed,
        'end': end?.toIso8601String(),
        'reviewNotes': reviewNotes,
        'legacy': legacy,
        if (routineLink != null) 'routineLink': routineLink!.toJson(),
        if (sourceText != null) 'sourceText': sourceText,
        if (revisions.isNotEmpty)
          'revisions': revisions.map((r) => r.toJson()).toList(),
      };

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final oldSchema = !json.containsKey('schemaVersion');
    final legacy = oldSchema || json['legacy'] == true;
    final times =
        (json['times'] as List?)?.cast<String>().toList() ?? <String>[];
    final start = DateTime.tryParse(json['start'] as String? ?? '');
    if (start == null) throw const FormatException('Invalid medication start');
    final rawEnd = json['end'] as String?;
    final end = rawEnd == null ? null : DateTime.tryParse(rawEnd);
    if (rawEnd != null && end == null) {
      throw const FormatException('Invalid medication end');
    }
    final kind = oldSchema
        ? (times.isEmpty ? ScheduleKind.prn : ScheduleKind.daily)
        : ScheduleKind.values.firstWhere(
            (value) => value.name == json['scheduleKind'],
            orElse: () => ScheduleKind.unknown,
          );
    return Medicine(
      id: json['id'] as String,
      name: json['name'] as String,
      dose: (json['dose'] ?? '') as String,
      qtyPerIntake:
          (json['qtyPerIntake'] as num?)?.toDouble() ?? (legacy ? 1 : 0),
      times: times,
      days: json['days'] as int?,
      instructions: (json['instructions'] ?? '') as String,
      stock: json['stock'] as int?,
      start: start,
      taken: (json['taken'] as List?)?.cast<String>(),
      takenAt: _parseTakenAt(json['takenAt'],
          (json['taken'] as List?)?.cast<String>().toSet() ?? const {}),
      scheduleKind: kind,
      frequencyPerDay:
          oldSchema ? times.length : json['frequencyPerDay'] as int?,
      intervalHours: json['intervalHours'] as int?,
      durationConfirmed: oldSchema || json['durationConfirmed'] == true,
      end: end,
      reviewNotes: (json['reviewNotes'] as List?)?.cast<String>(),
      legacy: legacy,
      routineLink: json['routineLink'] == null
          ? null
          : RoutineLink.fromJson(
              Map<String, dynamic>.from(json['routineLink'] as Map)),
      sourceText: json['sourceText'] as String?,
      revisions: [
        for (final raw in (json['revisions'] as List? ?? const []))
          ScheduleRevision.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

/// Only timestamps for doses that are still marked taken are kept.
Map<String, DateTime> _parseTakenAt(Object? raw, Set<String> taken) {
  if (raw == null) return {};
  if (raw is! Map) throw const FormatException('Invalid intake history');
  final result = <String, DateTime>{};
  raw.forEach((key, value) {
    final at = value is String ? DateTime.tryParse(value) : null;
    if (key is! String || at == null) {
      throw const FormatException('Invalid intake history');
    }
    if (taken.contains(key)) result[key] = at;
  });
  return result;
}

/// An earlier schedule rule that applied to doses before [until].
class ScheduleRevision {
  ScheduleRevision({required this.until, required Map<String, dynamic> rule})
      : rule = Map.unmodifiable(rule);
  final DateTime until; // Exclusive.
  final Map<String, dynamic> rule;
  late final Medicine medicine =
      Medicine.fromJson(Map<String, dynamic>.from(rule));

  Map<String, dynamic> toJson() =>
      {'until': until.toIso8601String(), 'rule': rule};

  factory ScheduleRevision.fromJson(Map<String, dynamic> json) {
    final until = DateTime.tryParse(json['until'] as String? ?? '');
    final rule = json['rule'];
    if (until == null || rule is! Map) {
      throw const FormatException('Invalid schedule revision');
    }
    final revision =
        ScheduleRevision(until: until, rule: Map<String, dynamic>.from(rule));
    revision.medicine; // Validate eagerly; corrupt history must not load.
    return revision;
  }
}
