import 'package:flutter_test/flutter_test.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/reminder_plan.dart';

void main() {
  final now = DateTime(2030, 1, 1, 7);
  Medicine daily(String id, List<String> times, {int? days = 2}) => Medicine(
      id: id,
      name: 'Example',
      dose: '500mg',
      qtyPerIntake: 1,
      times: times,
      start: now,
      days: days,
      durationConfirmed: true,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: times.length);

  test('all medicines share one chronologically ordered plan', () {
    final plan = ReminderPlan.build([
      daily('late', ['20:00']),
      daily('early', ['08:00'])
    ], now);
    expect(plan.error, isNull);
    expect(plan.reminders.map((reminder) => reminder.when), [
      DateTime(2030, 1, 1, 8),
      DateTime(2030, 1, 1, 20),
      DateTime(2030, 1, 2, 8),
      DateTime(2030, 1, 2, 20),
    ]);
  });

  test('finite q8h retains exactly eight hour spacing', () {
    final medicine = daily('interval', [])
      ..scheduleKind = ScheduleKind.interval
      ..intervalHours = 8;
    final plan = ReminderPlan.build(
        [medicine], now.subtract(const Duration(minutes: 1)));
    expect(plan.error, isNull);
    expect(plan.reminders.length, 6);
    for (var i = 1; i < plan.reminders.length; i++) {
      expect(plan.reminders[i].when.difference(plan.reminders[i - 1].when),
          const Duration(hours: 8));
    }
  });

  test('maintenance q8h uses three repeating series with original anchor', () {
    final medicine = daily('interval', [], days: null)
      ..scheduleKind = ScheduleKind.interval
      ..intervalHours = 8;
    final plan = ReminderPlan.build(
        [medicine], now.subtract(const Duration(minutes: 1)));
    expect(plan.error, isNull);
    expect(plan.reminders.length, 3);
    expect(plan.reminders.every((reminder) => reminder.repeatDaily), isTrue);
    expect(plan.reminders.map((reminder) => reminder.when.hour), [7, 15, 23]);
  });

  test('unknown schedule and duplicate times return explicit failures', () {
    expect(
        ReminderPlan.build([
          daily('unknown', ['08:00'])..scheduleKind = ScheduleKind.unknown
        ], now)
            .error,
        isNotNull);
    expect(
        ReminderPlan.build([
          daily('duplicate', ['08:00', '08:00'])
        ], now)
            .error,
        isNotNull);
  });

  test(
      'already-taken finite doses are excluded while completed schedule has no reminders',
      () {
    final medicine = daily('taken', ['08:00']);
    medicine.markTaken(DateTime(2030, 1, 1, 8));
    final plan = ReminderPlan.build([medicine], now);
    expect(plan.reminders.length, 1);
    expect(plan.reminders.single.when, DateTime(2030, 1, 2, 8));
    expect(ReminderPlan.build([medicine], DateTime(2030, 1, 3, 8)).reminders,
        isEmpty);
  });

  test('future maintenance start is preserved as the first occurrence', () {
    final medicine = daily('future', ['08:00'], days: null)
      ..start = DateTime(2030, 1, 4, 7);
    final plan = ReminderPlan.build([medicine], now);
    expect(plan.reminders.single.when, DateTime(2030, 1, 4, 8));
  });

  test(
      'capacity boundary rejects 401 future doses even when now itself is a dose',
      () {
    final medicine = daily('capacity', ['08:00'], days: 402)
      ..start = DateTime(2030, 1, 1, 8);
    final plan = ReminderPlan.build([medicine], DateTime(2030, 1, 1, 8));
    expect(plan.error, contains('400'));
    expect(plan.reminders, isEmpty);
  });
}
