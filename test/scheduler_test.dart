import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:inom_na/models/medicine.dart';
import 'package:inom_na/services/reminder_plan.dart';
import 'package:inom_na/services/schedule_edit.dart';
import 'package:inom_na/services/scheduler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _now = DateTime(2030, 1, 1, 7);

Medicine _medicine(String id,
        {bool maintenance = false, List<String>? times}) =>
    Medicine(
      id: id,
      name: 'Example',
      dose: '500mg',
      qtyPerIntake: 1,
      start: _now,
      times: times ?? ['08:00'],
      days: maintenance ? null : 2,
      durationConfirmed: true,
      scheduleKind: ScheduleKind.daily,
      frequencyPerDay: times?.length ?? 1,
    );

class _MemoryState implements ReminderStateStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

class _FakeBackend implements ReminderBackend {
  bool allowed = true;
  bool exact = true;
  int calls = 0;
  int? failCall;
  int? failCancelId;
  int active = 0;
  int maxActive = 0;
  Completer<void>? block;
  final entries = <int, PendingReminder>{};
  final reminders = <int, PlannedReminder>{};
  final canceled = <int>[];
  @override
  Future<SchedulerPermissionStatus> permissions({bool request = false}) async =>
      SchedulerPermissionStatus(
          notificationsGranted: allowed, exactAlarmsGranted: exact);
  @override
  Future<List<PendingReminder>> pending() async => entries.values.toList();
  @override
  Future<bool> schedule(int id, PlannedReminder reminder, String payload,
      {required bool exact}) async {
    active++;
    if (active > maxActive) maxActive = active;
    try {
      calls++;
      if (calls == failCall) throw StateError('Injected registration failure');
      final gate = block;
      block = null;
      if (gate != null) await gate.future;
      entries[id] = PendingReminder(id, payload);
      reminders[id] = reminder;
      return exact;
    } finally {
      active--;
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (id == failCancelId) {
      failCancelId = null;
      throw StateError('Injected cancellation failure');
    }
    canceled.add(id);
    entries.remove(id);
    reminders.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeBackend backend;
  late _MemoryState state;
  late ReminderCoordinator scheduler;
  setUp(() {
    backend = _FakeBackend();
    state = _MemoryState();
    scheduler = ReminderCoordinator(backend, state, clock: () => _now);
  });

  test(
      'stable dose IDs survive reconciliation, ordering and coordinator restart',
      () async {
    final medicines = [_medicine('a'), _medicine('b')];
    expect((await scheduler.rescheduleAll(medicines)).success, isTrue);
    final initial = Map<int, String?>.from(
        backend.entries.map((id, entry) => MapEntry(id, entry.payload)));
    final calls = backend.calls;
    final restarted = ReminderCoordinator(backend, state, clock: () => _now);
    expect((await restarted.rescheduleAll(medicines.reversed.toList())).success,
        isTrue);
    expect(backend.calls, calls);
    expect(backend.entries.map((id, entry) => MapEntry(id, entry.payload)),
        initial);
    expect(initial.length, 4);
    expect(initial.keys.every((id) => id >= 10000), isTrue);
  });

  test('taking a finite dose cancels only its notification', () async {
    final first = _medicine('a');
    final second = _medicine('b');
    await scheduler.rescheduleAll([first, second]);
    final dose = DateTime(2030, 1, 1, 8);
    final target = backend.entries.values
        .singleWhere((entry) =>
            (jsonDecode(entry.payload!) as Map<String, dynamic>)['doseId'] ==
            first.doseId(dose))
        .id;
    expect(first.markTaken(dose), isTrue);
    expect(first.markTaken(dose), isFalse);
    expect((await scheduler.cancelDose(first, dose)).success, isTrue);
    expect(backend.canceled, [target]);
    expect(backend.entries.length, 3);
  });

  test('early maintenance taken advances only its recurring series', () async {
    final medicine =
        _medicine('a', maintenance: true, times: ['08:00', '20:00']);
    await scheduler.rescheduleAll([medicine]);
    final first = backend.reminders.entries
        .singleWhere((entry) => entry.value.when.hour == 8);
    final eveningId = backend.reminders.entries
        .singleWhere((entry) => entry.value.when.hour == 20)
        .key;
    medicine.markTaken(DateTime(2030, 1, 1, 8));
    expect(
        (await scheduler.cancelDose(medicine, DateTime(2030, 1, 1, 8))).success,
        isTrue);
    expect(backend.reminders[first.key]!.when, DateTime(2030, 1, 2, 8));
    expect(backend.reminders[first.key]!.repeatDaily, isTrue);
    expect(backend.reminders[eveningId]!.when, DateTime(2030, 1, 1, 20));
    expect(backend.canceled, [first.key]);
  });

  test(
      'taking a delivered finite dose still cancels its visible notification ID',
      () async {
    final medicine = _medicine('a');
    await scheduler.rescheduleAll([medicine]);
    final dose = DateTime(2030, 1, 1, 8);
    final id = backend.entries.values
        .singleWhere((entry) =>
            (jsonDecode(entry.payload!) as Map<String, dynamic>)['doseId'] ==
            medicine.doseId(dose))
        .id;
    backend.entries
        .remove(id); // Delivered notifications leave the pending list.
    medicine.markTaken(dose);
    expect((await scheduler.cancelDose(medicine, dose)).success, isTrue);
    expect(backend.canceled, [id]);
  });

  test(
      'maintenance taken clears displayed reminder after resume already advanced its series',
      () async {
    final medicine = _medicine('a', maintenance: true);
    await scheduler.rescheduleAll([medicine]);
    final id = backend.entries.keys.single;
    final resumed = ReminderCoordinator(backend, state,
        clock: () => DateTime(2030, 1, 1, 9));
    await resumed.rescheduleAll([medicine]);
    expect(backend.reminders[id]!.when, DateTime(2030, 1, 2, 8));
    medicine.markTaken(DateTime(2030, 1, 1, 8));
    expect(
        (await resumed.cancelDose(medicine, DateTime(2030, 1, 1, 8))).success,
        isTrue);
    expect(backend.canceled, [id]);
    expect(backend.reminders[id]!.repeatDaily, isTrue);
  });

  test(
      'failed cancellation is retried after restart even when old dose is no longer pending',
      () async {
    final medicine = _medicine('a');
    await scheduler.rescheduleAll([medicine]);
    final dose = DateTime(2030, 1, 1, 8);
    final id = backend.entries.values
        .singleWhere((entry) =>
            (jsonDecode(entry.payload!) as Map<String, dynamic>)['doseId'] ==
            medicine.doseId(dose))
        .id;
    backend.entries.remove(id);
    backend.failCancelId = id;
    medicine.markTaken(dose);
    expect((await scheduler.cancelDose(medicine, dose)).success, isFalse);
    expect((jsonDecode(state.value!) as Map)['retiring'], contains(id));
    final restarted = ReminderCoordinator(backend, state, clock: () => _now);
    expect((await restarted.rescheduleAll([medicine])).success, isTrue);
    expect(backend.canceled, [id]);
    expect((jsonDecode(state.value!) as Map)['retiring'], isEmpty);
  });

  test('undo keeps a desired dose whose earlier cancellation failed', () async {
    final medicine = _medicine('a');
    await scheduler.rescheduleAll([medicine]);
    final dose = DateTime(2030, 1, 1, 8);
    final id = backend.entries.values
        .singleWhere((entry) =>
            (jsonDecode(entry.payload!) as Map<String, dynamic>)['doseId'] ==
            medicine.doseId(dose))
        .id;
    backend.failCancelId = id;
    medicine.markTaken(dose);
    expect((await scheduler.cancelDose(medicine, dose)).success, isFalse);
    medicine.markTaken(dose, value: false);
    expect((await scheduler.rescheduleAll([medicine])).success, isTrue);
    expect(backend.entries.containsKey(id), isTrue);
    expect(backend.canceled, isNot(contains(id)));
    expect((jsonDecode(state.value!) as Map)['retiring'], isEmpty);
  });

  test(
      'legacy reminders survive failed registration; staged new IDs are removed',
      () async {
    backend.entries[1] = const PendingReminder(1, '');
    backend.failCall = 2;
    final result = await scheduler.rescheduleAll([_medicine('a')]);
    expect(result.success, isFalse);
    expect(backend.entries.keys, [1]);
    expect(backend.canceled, isNot(contains(1)));
  });

  test(
      'legacy IDs retired only after successful replacements; test reminder remains',
      () async {
    backend.entries[1] = const PendingReminder(1, '');
    backend.entries[9999] = const PendingReminder(9999, '');
    expect((await scheduler.rescheduleAll([_medicine('a')])).success, isTrue);
    expect(backend.canceled, [1]);
    expect(backend.entries.containsKey(9999), isTrue);
  });

  test('failed managed replacement restores its previous reminder content',
      () async {
    final medicine = _medicine('a');
    await scheduler.rescheduleAll([medicine]);
    final previous =
        backend.reminders.map((id, reminder) => MapEntry(id, reminder.body));
    medicine.instructions = 'Changed';
    backend.failCall = backend.calls + 2;
    expect((await scheduler.rescheduleAll([medicine])).success, isFalse);
    expect(backend.reminders.map((id, reminder) => MapEntry(id, reminder.body)),
        previous);
  });

  test(
      'concurrent reconciliations serialize and leave the latest complete plan',
      () async {
    final gate = Completer<void>();
    backend.block = gate;
    final first = scheduler.rescheduleAll([_medicine('a')]);
    final second = scheduler.rescheduleAll([_medicine('b')]);
    await Future<void>.delayed(Duration.zero);
    expect(backend.calls, 1);
    gate.complete();
    expect((await first).success, isTrue);
    expect((await second).success, isTrue);
    expect(backend.maxActive, 1);
    expect(
        backend.reminders.values
            .every((reminder) => reminder.medicineId == 'b'),
        isTrue);
  });

  test(
      'denied permission returns failure and preserves existing pending notifications',
      () async {
    backend.entries[1] = const PendingReminder(1, '');
    backend.allowed = false;
    expect((await scheduler.rescheduleAll([_medicine('a')])).success, isFalse);
    expect(backend.calls, 0);
    expect(backend.canceled, isEmpty);
    expect(backend.entries.keys, [1]);
  });

  test('inexact fallback is explicit and does not claim exact delivery',
      () async {
    backend.exact = false;
    final result = await scheduler.rescheduleAll([_medicine('a')]);
    expect(result.success, isTrue);
    expect(result.exact, isFalse);
    expect(result.message, isNotNull);
  });

  test('changed exact-alarm permission reconciles previously pending mode',
      () async {
    final medicines = [_medicine('a')];
    await scheduler.rescheduleAll(medicines);
    final before = backend.calls;
    backend.exact = false;
    final result = await scheduler.rescheduleAll(medicines);
    expect(result.success, isTrue);
    expect(result.exact, isFalse);
    expect(backend.calls, before + 2);
    expect(
        backend.entries.values.every((entry) =>
            (jsonDecode(entry.payload!) as Map<String, dynamic>)['exact'] ==
            false),
        isTrue);
  });

  test('deletion can cancel managed notifications after permission revocation',
      () async {
    await scheduler.rescheduleAll([_medicine('a')]);
    backend.allowed = false;
    expect((await scheduler.rescheduleAll([])).success, isTrue);
    expect(backend.entries, isEmpty);
  });

  test('demo reminder is not canceled by medication reconciliation', () async {
    await scheduler.testInOneMinute(null);
    final id = backend.entries.keys.single;
    await scheduler.rescheduleAll([_medicine('a')]);
    expect(backend.entries.containsKey(id), isTrue);
    expect(backend.canceled, isNot(contains(id)));
  });

  test('capacity failure happens before touching any existing reminders',
      () async {
    final medicine = _medicine('a')..days = 401;
    backend.entries[1] = const PendingReminder(1, '');
    final result = await scheduler.rescheduleAll([medicine]);
    expect(result.success, isFalse);
    expect(result.message, contains('400'));
    expect(backend.calls, 0);
    expect(backend.canceled, isEmpty);
  });

  test(
      'an unplannable medicine is reported and keeps its reminders; others still work',
      () async {
    final medicine = _medicine('a', maintenance: true);
    final other = _medicine('b', maintenance: true, times: ['09:00']);
    await scheduler.rescheduleAll([medicine, other]);
    final keptIds = backend.reminders.entries
        .where((entry) => entry.value.medicineId == 'a')
        .map((entry) => entry.key)
        .toSet();
    expect(keptIds, isNotEmpty);
    // The record becomes unplannable (ongoing interval not dividing 24 h).
    medicine
      ..scheduleKind = ScheduleKind.interval
      ..intervalHours = 7;
    final result = await scheduler.rescheduleAll([medicine, other]);
    expect(result.success, isTrue);
    expect(result.message, contains('Reminders could not be updated'));
    // Not silently ended: its existing reminders stay registered.
    expect(backend.canceled.toSet().intersection(keptIds), isEmpty);
    expect(backend.entries.keys, containsAll(keptIds));
    expect(backend.reminders.values.any((r) => r.medicineId == 'b'), isTrue);
  });

  test('one invalid record no longer blocks a new valid medicine', () async {
    final invalid = _medicine('bad')..scheduleKind = ScheduleKind.unknown;
    final added = _medicine('new', maintenance: true, times: ['10:00']);
    final result = await scheduler.rescheduleAll([invalid, added]);
    expect(result.success, isTrue);
    expect(result.message, contains('Reminders could not be updated'));
    expect(backend.reminders.values.where((r) => r.medicineId == 'new'),
        isNotEmpty);
    expect(
        backend.reminders.values.where((r) => r.medicineId == 'bad'), isEmpty);
    // A restarted coordinator keeps the same IDs for the valid medicine.
    final ids = Map.of(backend.entries.map((id, e) => MapEntry(id, e.payload)));
    final calls = backend.calls;
    await ReminderCoordinator(backend, state, clock: () => _now)
        .rescheduleAll([invalid, added]);
    expect(backend.calls, calls);
    expect(backend.entries.map((id, e) => MapEntry(id, e.payload)), ids);
  });

  test(
      'native daily bridge preserves future first date without match-components',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    const channel = MethodChannel('com.inomna/reminders');
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });
    try {
      final native = NativeReminderBackend(FlutterLocalNotificationsPlugin());
      final reminder = PlannedReminder(
        key: 'daily:a:08:00',
        doseId: 'a|2030-01-02 08:00',
        medicineId: 'a',
        when: DateTime.utc(2030, 1, 2, 8),
        title: 'Reminder',
        body: 'Review',
        repeatDaily: true,
      );
      expect(await native.schedule(12000, reminder, '{}', exact: true), isTrue);
      expect(captured!.method, 'scheduleDaily');
      final args = captured!.arguments as Map;
      expect(args['scheduledDateTime'], '2030-01-02T08:00:00');
      expect(args.containsKey('matchDateTimeComponents'), isFalse);
      expect((args['platformSpecifics'] as Map)['scheduleMode'],
          'exactAllowWhileIdle');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('Phase 3 schedule edits', () {
    final day2 = DateTime(2030, 1, 2);
    Medicine edit(Medicine saved, List<String> times) => saved.withScheduleFrom(
        ScheduleEdit.draftOf(saved)
          ..times = times
          ..frequencyPerDay = times.length
          ..start = day2,
        day2);
    int idOf(String key) => backend.reminders.entries
        .singleWhere((entry) => entry.value.key == key)
        .key;

    test('an edit replaces only affected reminders; others stay untouched',
        () async {
      final edited =
          _medicine('a', maintenance: true, times: ['08:00', '20:00']);
      final other = _medicine('b', maintenance: true, times: ['09:00']);
      expect((await scheduler.rescheduleAll([edited, other])).success, isTrue);
      final old8 = idOf('daily:a:08:00');
      final old20 = idOf('daily:a:20:00');
      final otherId = idOf('daily:b:09:00');
      final otherPayload = backend.entries[otherId]!.payload;
      final callsBefore = backend.calls;

      final revised = edit(edited, ['09:30', '21:00']);
      expect((await scheduler.rescheduleAll([revised, other])).success, isTrue);
      expect(backend.canceled, containsAll([old8, old20]));
      final keys = backend.reminders.values.map((r) => r.key).toSet();
      // Today's remaining doses keep their old times as one-off reminders.
      expect(
          keys,
          containsAll([
            'dose:a|2030-01-01 08:00',
            'dose:a|2030-01-01 20:00',
            'daily:a:09:30',
            'daily:a:21:00',
            'daily:b:09:00',
          ]));
      expect(keys, isNot(contains('daily:a:08:00')));
      expect(keys, isNot(contains('daily:a:20:00')));
      expect(backend.reminders[idOf('daily:a:09:30')]!.when,
          DateTime(2030, 1, 2, 9, 30));
      // The unaffected medicine was neither cancelled nor re-registered.
      expect(backend.canceled, isNot(contains(otherId)));
      expect(backend.entries[otherId]!.payload, otherPayload);
      expect(backend.calls - callsBefore, 4);
    });

    test('a failed edit registration keeps the previous reminders', () async {
      final med = _medicine('a', maintenance: true, times: ['08:00']);
      await scheduler.rescheduleAll([med]);
      final before =
          backend.entries.map((id, entry) => MapEntry(id, entry.payload));
      backend.failCall = backend.calls + 2;
      final result = await scheduler.rescheduleAll([
        edit(med, ['10:00'])
      ]);
      expect(result.success, isFalse);
      expect(result.message, isNotNull);
      expect(backend.entries.map((id, entry) => MapEntry(id, entry.payload)),
          before);
    });

    test('concurrent edit saves serialize; the last confirmed edit wins',
        () async {
      final med = _medicine('a', maintenance: true, times: ['08:00']);
      final gate = Completer<void>();
      backend.block = gate;
      final first = scheduler.rescheduleAll([
        edit(med, ['09:00'])
      ]);
      final second = scheduler.rescheduleAll([
        edit(med, ['11:00'])
      ]);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect((await first).success, isTrue);
      expect((await second).success, isTrue);
      expect(backend.maxActive, 1);
      final series = backend.reminders.values
          .where((r) => r.key.startsWith('daily:a:'))
          .map((r) => r.key)
          .toList();
      expect(series, ['daily:a:11:00']);
    });

    test('taking an old-time dose during a change cancels only that reminder',
        () async {
      final med = _medicine('a', maintenance: true, times: ['08:00', '20:00']);
      final revised = edit(med, ['09:00', '21:00']);
      await scheduler.rescheduleAll([revised]);
      final oneOff = idOf('dose:a|2030-01-01 20:00');
      final seriesIds = backend.reminders.entries
          .where((entry) => entry.value.repeatDaily)
          .map((entry) => entry.key)
          .toSet();
      expect(seriesIds, hasLength(2));
      final dose = DateTime(2030, 1, 1, 20);
      revised.markTaken(dose);
      expect((await scheduler.cancelDose(revised, dose)).success, isTrue);
      expect(backend.canceled, contains(oneOff));
      expect(backend.canceled.toSet().intersection(seriesIds), isEmpty);
      expect(backend.entries.keys, containsAll(seriesIds));
    });
  });

  group('Phase 4 follow-up reminders', () {
    List<PlannedReminder> followUps() => backend.reminders.values
        .where((r) => r.key.startsWith('followup'))
        .toList();
    int idOf(String key) => backend.reminders.entries
        .singleWhere((entry) => entry.value.key == key)
        .key;

    test('each dose gets one follow-up 30 minutes later for the same dose',
        () async {
      final med = _medicine('a'); // 2-day course at 08:00.
      expect(
          (await scheduler.rescheduleAll([med], followUpMinutes: 30)).success,
          isTrue);
      final primaries = backend.reminders.values
          .where((r) => r.key.startsWith('dose:'))
          .toList();
      expect(primaries, hasLength(2));
      expect(followUps(), hasLength(2));
      for (final primary in primaries) {
        final followUp =
            followUps().singleWhere((f) => f.doseId == primary.doseId);
        expect(followUp.when.difference(primary.when),
            const Duration(minutes: 30));
        expect(followUp.key, ReminderPlan.followUpKey(primary.doseId));
        expect(followUp.body, contains('same dose, not an extra one'));
      }
    });

    test('follow-ups are not created when turned off or already taken',
        () async {
      final med = _medicine('a')..markTaken(DateTime(2030, 1, 1, 8));
      await scheduler.rescheduleAll([med]);
      expect(followUps(), isEmpty);
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      expect(followUps().map((f) => f.doseId), ['a|2030-01-02 08:00']);
    });

    test('a passed dose keeps its pending follow-up only', () async {
      final late = ReminderCoordinator(backend, state,
          clock: () => DateTime(2030, 1, 1, 8, 10));
      await late.rescheduleAll([_medicine('a')], followUpMinutes: 30);
      final today = backend.reminders.values
          .where((r) => r.doseId == 'a|2030-01-01 08:00')
          .toList();
      expect(today.map((r) => r.key), ['followup:a|2030-01-01 08:00']);
      expect(today.single.when, DateTime(2030, 1, 1, 8, 30));
    });

    test('marking a dose taken cancels its follow-up and nothing else',
        () async {
      final med = _medicine('a');
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      final dose = DateTime(2030, 1, 1, 8);
      final followUpId = idOf('followup:a|2030-01-01 08:00');
      final otherFollowUp = idOf('followup:a|2030-01-02 08:00');
      med.markTaken(dose, at: DateTime(2030, 1, 1, 8, 5));
      expect(
          (await scheduler.cancelDose(med, dose, followUpMinutes: 30)).success,
          isTrue);
      expect(backend.canceled, contains(followUpId));
      expect(backend.canceled, isNot(contains(otherFollowUp)));
      expect(backend.entries.containsKey(otherFollowUp), isTrue);
    });

    test('maintenance follow-ups repeat daily and move after taking', () async {
      final med = _medicine('a', maintenance: true);
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      final series = followUps().single;
      expect(series.key, 'followup-daily:a:08:00');
      expect(series.repeatDaily, isTrue);
      expect(series.when, DateTime(2030, 1, 1, 8, 30));
      final dose = DateTime(2030, 1, 1, 8);
      med.markTaken(dose);
      await scheduler.cancelDose(med, dose, followUpMinutes: 30);
      final moved = followUps().single;
      expect(moved.key, 'followup-daily:a:08:00');
      expect(moved.when, DateTime(2030, 1, 2, 8, 30));
      expect(followUps(), hasLength(1)); // No duplicate series.
    });

    test('reconciling twice registers nothing new (no duplicates)', () async {
      final med = _medicine('a', maintenance: true, times: ['08:00', '20:00']);
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      final calls = backend.calls;
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      expect(backend.calls, calls);
      expect(followUps().map((f) => f.key).toSet().length, followUps().length);
    });

    test('turning follow-ups off removes them; deletion removes the rest',
        () async {
      final med = _medicine('a', maintenance: true);
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      final followUpId = idOf('followup-daily:a:08:00');
      await scheduler.rescheduleAll([med]);
      expect(backend.canceled, contains(followUpId));
      expect(followUps(), isEmpty);
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      await scheduler.rescheduleAll([], followUpMinutes: 30);
      expect(backend.reminders, isEmpty);
    });

    test('a schedule edit replaces obsolete follow-ups', () async {
      final med = _medicine('a', maintenance: true);
      await scheduler.rescheduleAll([med], followUpMinutes: 30);
      final old = idOf('followup-daily:a:08:00');
      final day2 = DateTime(2030, 1, 2);
      final revised = med.withScheduleFrom(
          ScheduleEdit.draftOf(med)
            ..times = ['09:00']
            ..start = day2,
          day2);
      await scheduler.rescheduleAll([revised], followUpMinutes: 30);
      expect(backend.canceled, contains(old));
      final keys = followUps().map((f) => f.key).toSet();
      // Today's old-time dose keeps a one-off follow-up; the new time repeats.
      expect(keys, {'followup:a|2030-01-01 08:00', 'followup-daily:a:09:00'});
    });

    test('a failed follow-up registration keeps previous reminders', () async {
      final med = _medicine('a');
      await scheduler.rescheduleAll([med]);
      final before =
          backend.entries.map((id, entry) => MapEntry(id, entry.payload));
      backend.failCall = backend.calls + 1;
      final result = await scheduler.rescheduleAll([med], followUpMinutes: 30);
      expect(result.success, isFalse);
      expect(backend.entries.map((id, entry) => MapEntry(id, entry.payload)),
          before);
    });

    test('capacity: primary reminders always win over follow-ups', () {
      final hourly = [
        for (var h = 0; h < 24; h++) '${h.toString().padLeft(2, '0')}:00'
      ];
      final med = Medicine(
        id: 'h',
        name: 'Hourly sample',
        dose: '5mg',
        qtyPerIntake: 1,
        scheduleKind: ScheduleKind.explicit,
        frequencyPerDay: 24,
        times: hourly,
        days: 16,
        durationConfirmed: true,
        start: DateTime(2030, 1, 1),
      );
      final plan =
          ReminderPlan.build([med], DateTime(2030, 1, 1), followUpMinutes: 30);
      expect(plan.error, isNull);
      final primaries =
          plan.reminders.where((r) => r.key.startsWith('dose:')).length;
      expect(primaries, 16 * 24 - 1); // Every future dose (00:00 is now).
      expect(plan.reminders, hasLength(ReminderPlan.maxPending));
      expect(
          plan.notice,
          contains('main medication reminders are not '
              'affected'));
    });
  });
}
