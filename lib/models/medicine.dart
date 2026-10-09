/// Daily frequency and fixed-hour intervals have different prescription meanings.
enum ScheduleKind { unknown, daily, interval, explicit, prn }

/// Isang gamot sa reseta at ang schedule nito.
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
    this.scheduleKind = ScheduleKind.unknown,
    this.frequencyPerDay,
    this.intervalHours,
    this.durationConfirmed = false,
    this.end,
    List<String>? reviewNotes,
    this.legacy = false,
  })  : times = List<String>.of(times ?? []),
        start = start ?? DateTime.now(),
        taken = (taken ?? []).toSet().toList(),
        reviewNotes = List<String>.of(reviewNotes ?? []);

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
  ScheduleKind scheduleKind;
  int? frequencyPerDay;
  int? intervalHours;
  bool durationConfirmed;
  DateTime? end; // Exclusive end of the prescribed schedule.
  List<String> reviewNotes;
  bool legacy; // Preserve already-saved legacy course bounds and dose keys.

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
    if (isPrn) return 'Kapag kailangan (PRN)';
    if (scheduleKind == ScheduleKind.unknown) return 'Dalas: kailangang suriin';
    final frequency = scheduleKind == ScheduleKind.interval
        ? 'Tuwing ${intervalHours ?? "?"} oras'
        : '${times.length}x kada araw';
    if (!durationConfirmed) return '$frequency · tagal: kailangang suriin';
    if (isMaintenance) return '$frequency · maintenance';
    if (days != null) return '$frequency · $days araw';
    return '$frequency · may petsa ng pagtatapos';
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
    return DateTime(day.year, day.month, day.day, int.parse(parts[0]),
        int.parse(parts[1]));
  }

  static String keyOf(DateTime dt) =>
      '${dt.year}-${_2(dt.month)}-${_2(dt.day)} ${_2(dt.hour)}:${_2(dt.minute)}';
  static String _2(int value) => value.toString().padLeft(2, '0');

  /// Stable across reloads and rescheduling. Includes the medicine identity.
  String doseId(DateTime scheduled) => '$id|${keyOf(scheduled)}';

  bool isTaken(DateTime scheduled) => taken.contains(keyOf(scheduled));

  /// Returns false for a repeated action, so reminders/storage need not update.
  bool markTaken(DateTime scheduled, {bool value = true}) {
    final key = keyOf(scheduled);
    final present = taken.contains(key);
    if (value == present) return false;
    if (value) {
      taken.add(key);
    } else {
      taken.removeWhere((item) => item == key);
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
      errors.add('Linawin ang dalas o oras ng pag-inom.');
    }
    if (!durationConfirmed) {
      errors.add('Kumpirmahin ang tagal; hindi awtomatikong maintenance.');
    }
    if (days != null && (days! <= 0 || days! > 3650)) {
      errors.add('Ang bilang ng araw ay dapat 1–3650.');
    }
    if (end != null && !end!.isAfter(start)) {
      errors.add('Dapat mas huli sa simula ang pagtatapos.');
    }
    if (end != null && end!.difference(start) > const Duration(days: 3650)) {
      errors.add('Hindi maaaring lumampas sa 3650 araw ang pagtatapos.');
    }
    if (days != null && end != null) {
      errors.add('Gamitin ang bilang ng araw o petsa ng pagtatapos, hindi pareho.');
    }
    if (scheduleKind == ScheduleKind.interval) {
      if (intervalHours == null || intervalHours! <= 0 || intervalHours! > 168) {
        errors.add('Ang pagitan ng oras ay dapat 1–168 oras.');
      }
      if (times.any((time) => !validTime(time)) ||
          times.toSet().length != times.length) {
        errors.add('Linawin ang nabasang oras ng unang dose.');
      }
    }
    if (scheduleKind == ScheduleKind.daily ||
        scheduleKind == ScheduleKind.explicit) {
      if (times.isEmpty || times.length > 24 || times.any((t) => !validTime(t))) {
        errors.add('Maglagay ng wastong oras sa format na HH:mm.');
      }
      if (times.toSet().length != times.length) {
        errors.add('Hindi maaaring maulit ang oras ng isang gamot.');
      }
      if (scheduleKind == ScheduleKind.daily &&
          (frequencyPerDay == null ||
              frequencyPerDay! <= 0 ||
              frequencyPerDay! > 24 ||
              frequencyPerDay != times.length)) {
        errors.add('Dapat tumugma ang dalas sa bilang ng napiling oras.');
      }
    }
    return errors;
  }

  List<String> validationErrors() => [
        if (id.trim().isEmpty) 'Walang pagkakakilanlan ang gamot.',
        if (name.trim().isEmpty) 'Ilagay ang pangalan ng gamot.',
        if (!validDose(dose))
          'Ilagay at suriin ang numeric dosage o strength kasama ang unit.',
        if (!qtyPerIntake.isFinite || qtyPerIntake <= 0)
          'Ilagay ang wastong dami kada pag-inom.',
        if (stock != null && stock! < 0) 'Hindi maaaring negatibo ang stock.',
        ...scheduleErrors(),
      ];

  int? get _legacyTotal => legacy && days != null && !isPrn
      ? days! * times.length
      : null;

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
    final lastDay = DateTime(day.year, day.month,
        day.day + 1 + remainingIndex ~/ sorted.length);
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
    if (isPrn || scheduleErrors().isNotEmpty) return [];
    var cutoff = legacy
        ? start.subtract(const Duration(minutes: 30))
        : start;
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

  int? get totalDoses {
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
        'scheduleKind': scheduleKind.name,
        'frequencyPerDay': frequencyPerDay,
        'intervalHours': intervalHours,
        'durationConfirmed': durationConfirmed,
        'end': end?.toIso8601String(),
        'reviewNotes': reviewNotes,
        'legacy': legacy,
      };

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final oldSchema = !json.containsKey('schemaVersion');
    final legacy = oldSchema || json['legacy'] == true;
    final times = (json['times'] as List?)?.cast<String>().toList() ?? <String>[];
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
      qtyPerIntake: (json['qtyPerIntake'] as num?)?.toDouble() ?? (legacy ? 1 : 0),
      times: times,
      days: json['days'] as int?,
      instructions: (json['instructions'] ?? '') as String,
      stock: json['stock'] as int?,
      start: start,
      taken: (json['taken'] as List?)?.cast<String>(),
      scheduleKind: kind,
      frequencyPerDay: oldSchema ? times.length : json['frequencyPerDay'] as int?,
      intervalHours: json['intervalHours'] as int?,
      durationConfirmed: oldSchema || json['durationConfirmed'] == true,
      end: end,
      reviewNotes: (json['reviewNotes'] as List?)?.cast<String>(),
      legacy: legacy,
    );
  }
}
