import '../models/medicine.dart';

/// A dose, or a daily series whose first occurrence is a specific dose.
class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.doseId,
    required this.medicineId,
    required this.when,
    required this.title,
    required this.body,
    this.repeatDaily = false,
  });

  final String key;
  final String doseId;
  final String medicineId;
  final DateTime when;
  final String title;
  final String body;
  final bool repeatDaily;

  Map<String, dynamic> toJson() => {
        'key': key,
        'doseId': doseId,
        'medicineId': medicineId,
        'when': when.toIso8601String(),
        'title': title,
        'body': body,
        'repeatDaily': repeatDaily,
      };

  factory PlannedReminder.fromJson(Map<String, dynamic> json) =>
      PlannedReminder(
        key: json['key'] as String,
        doseId: json['doseId'] as String,
        medicineId: json['medicineId'] as String,
        when: DateTime.parse(json['when'] as String),
        title: json['title'] as String,
        body: json['body'] as String,
        repeatDaily: json['repeatDaily'] as bool? ?? false,
      );

  PlannedReminder nextDailyOccurrence(DateTime now) {
    var next = when;
    if (repeatDaily) {
      while (!next.isAfter(now)) {
        next = DateTime(
            next.year, next.month, next.day + 1, next.hour, next.minute);
      }
    }
    return PlannedReminder(
      key: key,
      doseId: doseId,
      medicineId: medicineId,
      when: next,
      title: title,
      body: body,
      repeatDaily: repeatDaily,
    );
  }
}

class ReminderPlan {
  const ReminderPlan(this.reminders, {this.error});
  final List<PlannedReminder> reminders;
  final String? error;

  // A conservative application budget, not a universal Android alarm limit.
  static const maxPending = 400;

  static ReminderPlan build(List<Medicine> medicines, DateTime now) {
    final result = <PlannedReminder>[];
    final medicineIds = <String>{};
    for (final medicine in medicines) {
      if (!medicineIds.add(medicine.id)) {
        return const ReminderPlan([],
            error:
                'May magkaparehong medicine ID. Hindi binago ang mga paalala.');
      }
      if (medicine.scheduleErrors().isNotEmpty) {
        return const ReminderPlan([],
            error:
                'May hindi pa wastong iskedyul. Suriin ang oras, frequency at petsa bago magpaalala.');
      }
      if (medicine.isPrn) continue;
      final extra =
          medicine.instructions.isEmpty ? '' : ' (${medicine.instructions})';
      final body =
          'Inumin: ${medicine.qtyLabel} ${medicine.name} ${medicine.dose}$extra'
              .trim();
      final end = medicine.scheduleEnd;
      if (end != null && !end.isAfter(now)) continue;

      if (end != null) {
        // Register the whole remaining finite course, never silently truncate it.
        // Taken keys may remove candidates from this budget, so allow one
        // candidate per unique taken key in addition to remaining capacity.
        final doses = medicine.allDoses(
            horizon: end,
            from: now,
            limit: maxPending - result.length + medicine.taken.length + 2);
        for (final dose in doses) {
          if (!dose.isAfter(now) || medicine.isTaken(dose)) continue;
          result.add(_dose(medicine, dose, body));
          if (result.length > maxPending) return _capacityFailure();
        }
      } else {
        final interval = medicine.intervalHours;
        if (medicine.scheduleKind == ScheduleKind.interval &&
            (interval == null || 24 % interval != 0)) {
          return const ReminderPlan([],
              error:
                  'Ang tuloy-tuloy na interval na ito ay hindi pa suportado sa offline reminders. Magtakda ng end date; hindi binago ang mga paalala.');
        }
        // Daily repeating series continue while the app is closed, indefinitely.
        // Start after every already-taken occurrence, including an early marking.
        final anchor = now.isBefore(medicine.start) ? medicine.start : now;
        final horizon = anchor.add(const Duration(days: 1));
        final byTime = <String, DateTime>{};
        for (final dose in medicine.allDoses(horizon: horizon, from: now)) {
          if (!dose.isAfter(now)) continue;
          final time = _time(dose);
          var next = dose;
          while (medicine.isTaken(next)) {
            next = DateTime(next.year, next.month, next.day + 1, next.hour,
                next.minute, next.second, next.millisecond, next.microsecond);
          }
          byTime.putIfAbsent(time, () => next);
        }
        for (final entry in byTime.entries) {
          result.add(PlannedReminder(
            key: seriesKey(medicine.id, entry.key),
            doseId: medicine.doseId(entry.value),
            medicineId: medicine.id,
            when: entry.value,
            title: 'Oras na ng gamot',
            body: body,
            repeatDaily: true,
          ));
          if (result.length > maxPending) return _capacityFailure();
        }
      }
      // Preserve the existing refill alert, with a stable separate identity.
      if (medicine.needsRefill) {
        final perDay = medicine.timesPerDay * medicine.qtyPerIntake;
        if (perDay.isFinite && perDay > 0 && (medicine.stock ?? 0) > 0) {
          final covered = (medicine.stock! / perDay).floor();
          final start = medicine.start;
          final alert =
              DateTime(start.year, start.month, start.day + covered - 3, 9);
          if (alert.isAfter(now)) {
            result.add(PlannedReminder(
              key: 'refill:${medicine.id}',
              doseId: '',
              medicineId: medicine.id,
              when: alert,
              title: 'Malapit nang maubos',
              body: '3 araw na lang ang ${medicine.name}. Bumili ka na.',
            ));
            if (result.length > maxPending) return _capacityFailure();
          }
        }
      }
    }
    result.sort((a, b) => a.when.compareTo(b.when));
    return ReminderPlan(result);
  }

  static String seriesKey(String medicineId, String time) =>
      'daily:$medicineId:$time';
  static String timeOf(DateTime dose) => _time(dose);
  static String _time(DateTime dose) =>
      '${dose.hour.toString().padLeft(2, '0')}:${dose.minute.toString().padLeft(2, '0')}';
  static PlannedReminder _dose(Medicine medicine, DateTime dose, String body) =>
      PlannedReminder(
        key: 'dose:${medicine.doseId(dose)}',
        doseId: medicine.doseId(dose),
        medicineId: medicine.id,
        when: dose,
        title: 'Oras na ng gamot',
        body: body,
      );
  static ReminderPlan _capacityFailure() => const ReminderPlan([],
      error:
          'Mahigit 400 paalala ang kailangan. Hindi binago ang mga dating paalala. Hindi suportado ang dami ng paalala sa kasalukuyang app. Huwag baguhin ang reseta para magkasya; gumamit muna ng ibang paraan ng paalala.');
}
