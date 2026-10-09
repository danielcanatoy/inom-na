import '../models/medicine.dart';

/// Tracking status of one scheduled dose. "Missed" only means no taken
/// confirmation was recorded; it does not prove the dose was not taken.
enum DoseStatus { upcoming, taken, overdue, missed }

class DoseTracking {
  /// An unconfirmed dose becomes "missed" this long after its scheduled time.
  static const missedAfter = Duration(hours: 2);

  static DoseStatus statusOf(Medicine m, DateTime dose, DateTime now) {
    if (m.isTaken(dose)) return DoseStatus.taken; // Always takes precedence.
    if (dose.isAfter(now)) return DoseStatus.upcoming;
    return now.difference(dose) >= missedAfter
        ? DoseStatus.missed
        : DoseStatus.overdue;
  }

  /// Scheduled doses on [day] (midnight to midnight), chronological. PRN
  /// medicines have no scheduled doses. Follow-up reminders are not doses.
  static List<(Medicine, DateTime)> dosesOn(
      List<Medicine> medicines, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final result = <(Medicine, DateTime)>[];
    for (final m in medicines) {
      for (final dose in m.allDoses(horizon: end, from: start)) {
        if (dose.isBefore(end)) result.add((m, dose));
      }
    }
    result.sort((a, b) {
      final byTime = a.$2.compareTo(b.$2);
      return byTime != 0 ? byTime : a.$1.name.compareTo(b.$1.name);
    });
    return result;
  }

  static DoseCounts countDay(
          List<Medicine> medicines, DateTime day, DateTime now) =>
      DoseCounts.of([
        for (final (m, dose) in dosesOn(medicines, day)) statusOf(m, dose, now)
      ]);

  /// Doses of one medicine scheduled up to [now] (already due).
  static DoseCounts countDue(Medicine m, DateTime now) => DoseCounts.of(
      [for (final dose in m.allDoses(horizon: now)) statusOf(m, dose, now)]);
}

class DoseCounts {
  const DoseCounts(
      {this.total = 0,
      this.taken = 0,
      this.upcoming = 0,
      this.overdue = 0,
      this.missed = 0});

  factory DoseCounts.of(Iterable<DoseStatus> statuses) {
    var taken = 0, upcoming = 0, overdue = 0, missed = 0, total = 0;
    for (final status in statuses) {
      total++;
      switch (status) {
        case DoseStatus.taken:
          taken++;
        case DoseStatus.upcoming:
          upcoming++;
        case DoseStatus.overdue:
          overdue++;
        case DoseStatus.missed:
          missed++;
      }
    }
    return DoseCounts(
        total: total,
        taken: taken,
        upcoming: upcoming,
        overdue: overdue,
        missed: missed);
  }

  final int total;
  final int taken;
  final int upcoming;
  final int overdue;
  final int missed;
}
