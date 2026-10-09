/// The user's usual day. Used only to SUGGEST reminder times; prescription
/// instructions always take priority.
enum RoutineEvent { wake, breakfast, lunch, dinner, bedtime }

extension RoutineEventLabel on RoutineEvent {
  String get label => switch (this) {
        RoutineEvent.wake => 'Wake-up',
        RoutineEvent.breakfast => 'Breakfast',
        RoutineEvent.lunch => 'Lunch',
        RoutineEvent.dinner => 'Dinner',
        RoutineEvent.bedtime => 'Bedtime',
      };
}

/// Meals that a routine-linked schedule may use as anchors.
const mealEvents = [
  RoutineEvent.breakfast,
  RoutineEvent.lunch,
  RoutineEvent.dinner,
];

class DailyRoutine {
  DailyRoutine(Map<RoutineEvent, String> times)
      : times = Map.unmodifiable(times);

  /// Stored as HH:mm (24-hour), independent of the phone's display format.
  final Map<RoutineEvent, String> times;

  /// Initial picker values for a first-time setup. They are NOT a saved
  /// routine until the user reviews and saves them.
  static final pickerDefaults = DailyRoutine({
    RoutineEvent.wake: '06:00',
    RoutineEvent.breakfast: '07:00',
    RoutineEvent.lunch: '12:00',
    RoutineEvent.dinner: '18:00',
    RoutineEvent.bedtime: '21:00',
  });

  String operator [](RoutineEvent event) => times[event] ?? '';

  DailyRoutine copyWith(RoutineEvent event, String value) =>
      DailyRoutine({...times, event: value});

  static int? minutesOf(String hhmm) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static String format(int minutes) {
    final value = minutes % 1440;
    return '${(value ~/ 60).toString().padLeft(2, '0')}:'
        '${(value % 60).toString().padLeft(2, '0')}';
  }

  /// Minutes after wake-up, so a day may cross midnight (e.g. night shifts,
  /// or a bedtime after 12:00 AM).
  int offsetFromWake(RoutineEvent event) {
    final wake = minutesOf(this[RoutineEvent.wake])!;
    final value = minutesOf(this[event])!;
    return (value - wake + 1440) % 1440;
  }

  /// Minutes awake (wake-up to bedtime).
  int get awakeMinutes => offsetFromWake(RoutineEvent.bedtime);

  List<String> validationErrors() {
    final errors = <String>[];
    for (final event in RoutineEvent.values) {
      if (minutesOf(this[event]) == null) {
        errors.add('Choose a valid ${event.label.toLowerCase()} time.');
      }
    }
    if (errors.isNotEmpty) return errors;
    final values = RoutineEvent.values.map((e) => this[e]).toList();
    if (values.toSet().length != values.length) {
      errors.add('Each routine time must be different.');
    }
    // Events must follow the order of the day, starting from wake-up.
    for (var i = 1; i < RoutineEvent.values.length - 1; i++) {
      final earlier = RoutineEvent.values[i];
      final later = RoutineEvent.values[i + 1];
      if (offsetFromWake(later) <= offsetFromWake(earlier)) {
        errors.add('${later.label} should come after '
            '${earlier.label.toLowerCase()} in your day.');
      }
    }
    if (awakeMinutes < 4 * 60) {
      errors.add('Bedtime should be at least 4 hours after wake-up.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        for (final event in RoutineEvent.values) event.name: this[event],
      };

  factory DailyRoutine.fromJson(Map<String, dynamic> json) => DailyRoutine({
        for (final event in RoutineEvent.values)
          event: (json[event.name] as String?) ?? '',
      });

  @override
  bool operator ==(Object other) =>
      other is DailyRoutine &&
      RoutineEvent.values.every((event) => other[event] == this[event]);

  @override
  int get hashCode => Object.hashAll(RoutineEvent.values.map((e) => this[e]));
}

/// How a verified daily schedule is fitted to the user's routine.
enum RoutineMode { spread, beforeMeals, afterMeals, bedtime }

extension RoutineModeLabel on RoutineMode {
  String get label => switch (this) {
        RoutineMode.spread => 'Spread through my day',
        RoutineMode.beforeMeals => 'Before meals',
        RoutineMode.afterMeals => 'After meals',
        RoutineMode.bedtime => 'At bedtime',
      };
}

/// Stored on a medicine whose reminder times came from the routine, so a later
/// routine change can propose updates. Cleared when times are customized.
class RoutineLink {
  const RoutineLink({
    required this.mode,
    this.meals = const [],
    this.offsetMinutes,
  });
  final RoutineMode mode;
  final List<RoutineEvent> meals;

  /// Minutes before/after the meal as instructed. Never assumed: null means
  /// the user has not entered it yet.
  final int? offsetMinutes;

  bool get usesMeals =>
      mode == RoutineMode.beforeMeals || mode == RoutineMode.afterMeals;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'meals': meals.map((m) => m.name).toList(),
        'offsetMinutes': offsetMinutes,
      };

  factory RoutineLink.fromJson(Map<String, dynamic> json) => RoutineLink(
        mode: RoutineMode.values.byName(json['mode'] as String),
        meals: [
          for (final name in (json['meals'] as List? ?? const []))
            RoutineEvent.values.byName(name as String),
        ],
        offsetMinutes: json['offsetMinutes'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is RoutineLink &&
      other.mode == mode &&
      other.offsetMinutes == offsetMinutes &&
      other.meals.length == meals.length &&
      Iterable.generate(meals.length).every((i) => other.meals[i] == meals[i]);

  @override
  int get hashCode => Object.hash(mode, offsetMinutes, Object.hashAll(meals));
}
