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
  const ReminderPlan(this.reminders,
      {this.error, this.notice, this.skipped = const []});
  final List<PlannedReminder> reminders;
  final String? error;

  /// Medicines whose schedule could not be planned (invalid or unsupported).
  /// They are skipped so other medicines still get reminders; their existing
  /// reminders are left untouched by the scheduler and they are reported.
  final List<Medicine> skipped;

  /// Pulls the medicine id out of a reminder key (null if not a medicine key).
  static String? medicineIdOfKey(String key) {
    for (final prefix in ['dose:', 'followup:']) {
      if (key.startsWith(prefix)) {
        final doseId = key.substring(prefix.length);
        final bar = doseId.indexOf('|');
        return bar < 0 ? null : doseId.substring(0, bar);
      }
    }
    for (final prefix in ['daily:', 'followup-daily:']) {
      if (key.startsWith(prefix) && key.length > prefix.length + 6) {
        return key.substring(prefix.length, key.length - 6); // ":HH:mm"
      }
    }
    if (key.startsWith('refill:')) return key.substring('refill:'.length);
    return null;
  }

  /// Non-blocking information, e.g. follow-ups limited by capacity.
  final String? notice;

  /// Finite courses get one-off follow-ups this far ahead; they are refreshed
  /// whenever reminders are reconciled (app start/resume and every save).
  static const followUpWindow = Duration(days: 7);

  // A conservative application budget, not a universal Android alarm limit.
  static const maxPending = 400;

  /// [followUpMinutes]: when set, each scheduled dose also gets ONE
  /// follow-up reminder that many minutes later, for the SAME dose. It is
  /// cancelled when the dose is marked taken. Primary reminders always get
  /// capacity first; follow-ups never change the number of doses.
  static ReminderPlan build(List<Medicine> medicines, DateTime now,
      {int? followUpMinutes}) {
    final result = <PlannedReminder>[];
    final medicineIds = <String>{};
    final skipped = <Medicine>[];
    for (final medicine in medicines) {
      if (!medicineIds.add(medicine.id)) {
        return const ReminderPlan([],
            error:
                'Two medications share the same ID. Reminders were not changed.');
      }
      // One invalid record must not block every other medicine's reminders.
      if (medicine.scheduleErrors().isNotEmpty) {
        skipped.add(medicine);
        continue;
      }
      if (medicine.isPrn) continue;
      final extra =
          medicine.instructions.isEmpty ? '' : ' (${medicine.instructions})';
      final body =
          'Take ${medicine.qtyLabel} × ${medicine.name} ${medicine.dose}$extra'
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
          // Not supported as an ongoing series: skip this medicine only.
          skipped.add(medicine);
          continue;
        }
        // Daily repeating series continue while the app is closed, indefinitely.
        // Start after every already-taken occurrence, including an early marking.
        final anchor = now.isBefore(medicine.start) ? medicine.start : now;
        final horizon = anchor.add(const Duration(days: 1));
        final byTime = <String, DateTime>{};
        for (final dose in medicine.allDoses(horizon: horizon, from: now)) {
          if (!dose.isAfter(now)) continue;
          // Remaining doses of an earlier rule (before a schedule edit takes
          // effect) are one-off reminders; only the current rule repeats.
          if (medicine.revisions.isNotEmpty && dose.isBefore(medicine.start)) {
            if (!medicine.isTaken(dose)) {
              result.add(_dose(medicine, dose, body));
            }
            if (result.length > maxPending) return _capacityFailure();
            continue;
          }
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
            title: doseTitle,
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
          final start = medicine.originalStart;
          final alert =
              DateTime(start.year, start.month, start.day + covered - 3, 9);
          if (alert.isAfter(now)) {
            result.add(PlannedReminder(
              key: 'refill:${medicine.id}',
              doseId: '',
              medicineId: medicine.id,
              when: alert,
              title: 'Medication running low',
              body:
                  'About 3 days of ${medicine.name} left. Please arrange a refill.',
            ));
            if (result.length > maxPending) return _capacityFailure();
          }
        }
      }
    }
    String? notice;
    if (skipped.isNotEmpty) {
      final names = skipped
          .map((m) => m.name.trim().isEmpty ? 'a medication' : m.name.trim())
          .join(', ');
      notice = 'Reminders could not be updated for: $names. Its schedule '
          'needs review (open the medicine and use Edit Medication). '
          'Existing reminders for it were kept, and all other medications '
          'are scheduled normally.';
    }
    if (followUpMinutes != null && followUpMinutes > 0) {
      final delay = Duration(minutes: followUpMinutes);
      final skippedIds = {for (final m in skipped) m.id};
      final followUps = [
        for (final medicine in medicines)
          if (!skippedIds.contains(medicine.id))
            ..._followUps(medicine, now, delay)
      ]..sort((a, b) => a.when.compareTo(b.when));
      final room = maxPending - result.length;
      if (followUps.length > room) {
        notice = [
          if (notice != null) notice,
          'Some follow-up reminders could not be set because of the '
              'reminder limit. Your main medication reminders are not '
              'affected.',
        ].join('\n');
      }
      result.addAll(followUps.take(room < 0 ? 0 : room));
    }
    result.sort((a, b) => a.when.compareTo(b.when));
    return ReminderPlan(result, notice: notice, skipped: skipped);
  }

  static List<PlannedReminder> _followUps(
      Medicine medicine, DateTime now, Duration delay) {
    if (medicine.isPrn) return const [];
    final out = <PlannedReminder>[];
    final lower = now.subtract(delay); // Doses whose follow-up is still due.
    final end = medicine.scheduleEnd;
    bool pending(DateTime dose) =>
        !medicine.isTaken(dose) && dose.add(delay).isAfter(now);
    if (end != null) {
      final windowEnd = now.add(followUpWindow);
      final horizon = end.isBefore(windowEnd) ? end : windowEnd;
      for (final dose in medicine.allDoses(horizon: horizon, from: lower)) {
        if (pending(dose)) out.add(_followUp(medicine, dose, delay));
      }
      return out;
    }
    final anchor = now.isBefore(medicine.start) ? medicine.start : now;
    final byTime = <String, DateTime>{};
    for (final dose in medicine.allDoses(
        horizon: anchor.add(const Duration(days: 1)), from: lower)) {
      if (medicine.revisions.isNotEmpty && dose.isBefore(medicine.start)) {
        if (pending(dose)) out.add(_followUp(medicine, dose, delay));
        continue;
      }
      var next = dose;
      while (!pending(next)) {
        next = DateTime(next.year, next.month, next.day + 1, next.hour,
            next.minute, next.second, next.millisecond, next.microsecond);
      }
      byTime.putIfAbsent(_time(dose), () => next);
    }
    for (final next in byTime.values) {
      out.add(_followUp(medicine, next, delay, repeatDaily: true));
    }
    return out;
  }

  static PlannedReminder _followUp(
          Medicine medicine, DateTime dose, Duration delay,
          {bool repeatDaily = false}) =>
      PlannedReminder(
        key: repeatDaily
            ? followUpSeriesKey(medicine.id, _time(dose))
            : followUpKey(medicine.doseId(dose)),
        doseId: medicine.doseId(dose),
        medicineId: medicine.id,
        when: dose.add(delay),
        title: followUpTitle,
        body: 'Your ${_clock(dose)} dose '
            '(${'${medicine.qtyLabel} × ${medicine.name} ${medicine.dose}'.trim()}) '
            'is not marked as taken. If you already took it, mark it in '
            'IMedsU. This is the same dose, not an extra one.',
        repeatDaily: repeatDaily,
      );

  static const followUpTitle = 'Not marked as taken yet';
  static String followUpKey(String doseId) => 'followup:$doseId';
  static String followUpSeriesKey(String medicineId, String time) =>
      'followup-daily:$medicineId:$time';
  static String _clock(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$hour:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static const doseTitle = 'Time for your medication';

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
        title: doseTitle,
        body: body,
      );
  static ReminderPlan _capacityFailure() => const ReminderPlan([],
      error:
          'More than 400 reminders would be needed, which this app does not support yet. Your existing reminders were not changed. Do not change the prescription to fit this limit; use another reminder method for now.');
}
