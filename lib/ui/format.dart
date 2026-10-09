/// Small date/time formatters (avoids adding the intl dependency).
class Fmt {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// 8:05 AM
  static String time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Converts a stored HH:mm value for display; invalid values are shown as-is.
  static String clock(String hhmm) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
    if (match == null) return hhmm;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return hhmm;
    return time(DateTime(2000, 1, 1, hour, minute));
  }

  /// Thursday, October 9
  static String longDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

  /// Oct 9, 2026
  static String date(DateTime d) =>
      '${_months[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

  /// Oct 9, 2026 · 8:05 AM
  static String dateTime(DateTime d) => '${date(d)} · ${time(d)}';

  /// Amount per dose, e.g. 1 or 0.5, without trailing ".0".
  static String amount(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
