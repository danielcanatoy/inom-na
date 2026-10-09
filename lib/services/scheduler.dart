import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// Pinned v17 serializer for the native daily-repeat bridge. Retains the same
// notification configuration as the public zonedSchedule API.
// ignore: implementation_imports
import 'package:flutter_local_notifications/src/platform_specifics/android/method_channel_mappers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';
import 'reminder_plan.dart';

class SchedulerResult {
  const SchedulerResult({required this.success, this.message, this.exact});
  final bool success;
  final String? message;
  final bool? exact;
}

class SchedulerPermissionStatus {
  const SchedulerPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
  });
  final bool notificationsGranted;
  final bool exactAlarmsGranted;
}

class PendingReminder {
  const PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
}

/// Small injectable boundary so registration, failure recovery and races can be
/// tested without claiming to test Android's actual delivery behavior.
abstract class ReminderBackend {
  Future<SchedulerPermissionStatus> permissions({bool request = false});
  Future<List<PendingReminder>> pending();
  Future<bool> schedule(int id, PlannedReminder reminder, String payload,
      {required bool exact});
  Future<void> cancel(int id);
}

abstract class ReminderStateStore {
  Future<String?> read();
  Future<void> write(String value);
}

class _PreferencesReminderState implements ReminderStateStore {
  static const key = 'inom_na_reminders_v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String value) async {
    final saved =
        await (await SharedPreferences.getInstance()).setString(key, value);
    if (!saved) throw StateError('Reminder state not persisted');
  }
}

class _ReminderState {
  _ReminderState(
      {Map<String, int>? ids,
      Map<int, PlannedReminder>? registered,
      Set<int>? retiring,
      this.legacyMigrated = false})
      : ids = ids ?? {},
        registered = registered ?? {},
        retiring = retiring ?? {};
  final Map<String, int> ids;
  final Map<int, PlannedReminder> registered;
  final Set<int> retiring;
  bool legacyMigrated;

  factory _ReminderState.decode(String? raw) {
    if (raw == null) return _ReminderState();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _ReminderState(
      ids: (json['ids'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as int)),
      registered: (json['registered'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(int.parse(key),
              PlannedReminder.fromJson(value as Map<String, dynamic>))),
      legacyMigrated: json['legacyMigrated'] as bool? ?? false,
      retiring: (json['retiring'] as List?)?.cast<int>().toSet(),
    );
  }
  String encode() => jsonEncode({
        'ids': ids,
        'registered':
            registered.map((key, value) => MapEntry('$key', value.toJson())),
        'legacyMigrated': legacyMigrated,
        'retiring': retiring.toList(),
      });

  int reserve(String key, Set<int> occupied) {
    final existing = ids[key];
    if (existing != null) return existing;
    // Stable FNV-1a, then probe occupied IDs. Avoid legacy IDs and demo ID 9999.
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    var id = hash < 10000 ? hash + 10000 : hash;
    final used = {...ids.values, ...occupied};
    while (used.contains(id)) {
      id = id == 0x7fffffff ? 10000 : id + 1;
    }
    ids[key] = id;
    return id;
  }
}

class ReminderCoordinator {
  ReminderCoordinator(this.backend, this.stateStore,
      {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final ReminderBackend backend;
  final ReminderStateStore stateStore;
  final DateTime Function() clock;
  Future<void> _tail = Future<void>.value();

  Future<SchedulerResult> _serial(Future<SchedulerResult> Function() action) {
    final next = _tail.then((_) async {
      try {
        return await action();
      } catch (_) {
        // Never include exceptions, medicine names or prescription content.
        return const SchedulerResult(
            success: false,
            message:
                'Reminders could not be updated. Your medications are saved. Try again and check notification settings.');
      }
    });
    _tail = next.then<void>((_) {});
    return next;
  }

  Future<SchedulerResult> rescheduleAll(List<Medicine> medicines) {
    // Snapshot before entering the queue; callers may edit mutable medicines.
    final snapshot = medicines
        .map((medicine) => Medicine.fromJson(medicine.toJson()))
        .toList();
    return _serial(() async {
      final plan = ReminderPlan.build(snapshot, clock());
      if (plan.error != null)
        return SchedulerResult(success: false, message: plan.error);
      return _apply(plan.reminders, replaceAll: true);
    });
  }

  Future<SchedulerResult> cancelDose(Medicine medicine, DateTime dose) {
    final snapshot = Medicine.fromJson(medicine.toJson());
    return _serial(() async {
      if (snapshot.scheduleEnd == null && !snapshot.isPrn) {
        final plan = ReminderPlan.build([snapshot], clock());
        if (plan.error != null)
          return SchedulerResult(success: false, message: plan.error);
        final key =
            ReminderPlan.seriesKey(snapshot.id, ReminderPlan.timeOf(dose));
        final replacements =
            plan.reminders.where((reminder) => reminder.key == key).toList();
        return _apply(replacements, replaceAll: false, removeKeys: {key});
      }
      return _apply([],
          replaceAll: false, removeKeys: {'dose:${snapshot.doseId(dose)}'});
    });
  }

  Future<SchedulerResult> testInOneMinute(Medicine? medicine) =>
      _serial(() async {
        final now = clock();
        final reminder = PlannedReminder(
          key: 'demo:test',
          doseId: '',
          medicineId: '',
          when: now.add(const Duration(minutes: 1)),
          title: 'Test reminder',
          body: medicine == null
              ? 'This is how your medication reminders will look.'
              : 'Take ${medicine.qtyLabel} × ${medicine.name} ${medicine.dose}'
                  .trim(),
        );
        return _apply([reminder], replaceAll: false);
      });

  static String _payload(PlannedReminder reminder, {required bool exact}) =>
      jsonEncode({
        'version': 1,
        'key': reminder.key,
        'doseId': reminder.doseId,
        'when': reminder.when.toIso8601String(),
        'daily': reminder.repeatDaily,
        'content': _contentHash('${reminder.title}\n${reminder.body}'),
        'exact': exact,
      });
  static int _contentHash(String text) {
    var hash = 0;
    for (final unit in text.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash;
  }

  Future<SchedulerResult> _apply(
    List<PlannedReminder> desired, {
    required bool replaceAll,
    Set<String> removeKeys = const {},
  }) async {
    final permission = await backend.permissions();
    // Deletion/cancellation must still work when permission was revoked.
    if (desired.isNotEmpty && !permission.notificationsGranted) {
      return const SchedulerResult(
          success: false,
          message:
              'Notifications are turned off for IMedsU. Your medication is saved, but the new reminder was not set. Allow notifications in Android settings.');
    }
    final state = _ReminderState.decode(await stateStore.read());
    final pending = await backend.pending();
    final existing = {for (final reminder in pending) reminder.id: reminder};
    final desiredById = <int, PlannedReminder>{};
    for (final reminder in desired) {
      desiredById[state.reserve(reminder.key, existing.keys.toSet())] =
          reminder;
    }
    // Persist reservations before touching native schedules; retries use same IDs.
    await stateStore.write(state.encode());
    final previous = Map<int, PlannedReminder>.from(state.registered);
    final previousRetiring = Set<int>.from(state.retiring);
    final obsolete = <int>{...state.retiring};
    for (final entry in previous.entries) {
      if (entry.value.key == 'demo:test') continue;
      if ((replaceAll || removeKeys.contains(entry.value.key)) &&
          !desiredById.containsKey(entry.key)) {
        obsolete.add(entry.key);
      }
    }
    for (final key in removeKeys) {
      final id = state.ids[key];
      if (id != null && !desiredById.containsKey(id)) obsolete.add(id);
    }
    // Recover orphan pending IDs and migrate known legacy registrations only
    // during full reconciliation. Delivered managed IDs remain in tombstones.
    if (replaceAll) {
      for (final item in pending) {
        if (desiredById.containsKey(item.id)) continue;
        var managed = false;
        var demo = false;
        try {
          final payload =
              jsonDecode(item.payload ?? '') as Map<String, dynamic>;
          managed = payload['version'] == 1;
          demo = payload['key'] == 'demo:test';
        } catch (_) {/* Legacy notifications have no payload. */}
        if (managed && !demo) obsolete.add(item.id);
        if (!state.legacyMigrated &&
            (item.payload == null || item.payload!.isEmpty) &&
            item.id > 0 &&
            item.id < 9999) {
          obsolete.add(item.id);
        }
      }
    }
    // A later undo/re-add may need an ID retired by a failed prior cancellation.
    obsolete.removeAll(desiredById.keys);
    final touched = <int>[];
    var exact = permission.exactAlarmsGranted;
    try {
      for (final entry in desiredById.entries) {
        final payload =
            _payload(entry.value, exact: permission.exactAlarmsGranted);
        if (existing[entry.key]?.payload == payload &&
            !removeKeys.contains(entry.value.key)) continue;
        // Record first: a backend may register then throw.
        touched.add(entry.key);
        if (removeKeys.contains(entry.value.key)) {
          // Clear this series' displayed notification and old alarm, then
          // replace tomorrow's alarm. Failure restores its previous schedule.
          await backend.cancel(entry.key);
        }
        final wasExact = await backend.schedule(entry.key, entry.value, payload,
            exact: permission.exactAlarmsGranted);
        exact = exact && wasExact;
      }
      if (replaceAll) {
        state.registered
            .removeWhere((id, reminder) => reminder.key != 'demo:test');
      } else {
        state.registered
            .removeWhere((id, reminder) => removeKeys.contains(reminder.key));
      }
      state.registered.addAll(desiredById);
      state.retiring.clear();
      state.retiring.addAll(obsolete);
      await stateStore.write(state.encode());
    } catch (_) {
      // Old pending legacy IDs were never touched. Undo staged additions and
      // restore previously managed entries changed before this failure.
      var restored = true;
      for (final id in touched.reversed) {
        try {
          final old = previous[id];
          if (old != null && existing.containsKey(id)) {
            final restore = old.nextDailyOccurrence(clock());
            await backend.schedule(id, restore,
                _payload(restore, exact: permission.exactAlarmsGranted),
                exact: permission.exactAlarmsGranted);
          } else {
            await backend.cancel(id);
          }
        } catch (_) {
          restored = false;
        }
      }
      state.registered.clear();
      state.registered.addAll(previous);
      state.retiring.clear();
      state.retiring.addAll(previousRetiring);
      try {
        await stateStore.write(state.encode());
      } catch (_) {
        restored = false;
      }
      return SchedulerResult(
          success: false,
          message: restored
              ? 'The new reminder could not be set. Your previous reminders were kept. Please try again.'
              : 'Reminders were only partly updated. Check and try again before relying on reminders.');
    }

    // Only retire old notifications after successful registration AND storage.
    // Persisted tombstones permit retries even after a notification is delivered
    // and disappears from the plugin's pending list.
    try {
      for (final id in obsolete) {
        await backend.cancel(id);
        state.retiring.remove(id);
      }
      if (replaceAll) state.legacyMigrated = true;
      await stateStore.write(state.encode());
    } catch (_) {
      return const SchedulerResult(
          success: false,
          message:
              'An old reminder could not be cancelled. Try again before relying on the schedule.');
    }
    return SchedulerResult(
        success: true,
        exact: desired.isEmpty ? null : exact,
        message: desired.isNotEmpty && !exact
            ? 'Reminders are set, but they may arrive late because "Alarms & reminders" permission is off.'
            : null);
  }
}

class NativeReminderBackend implements ReminderBackend {
  NativeReminderBackend(this.notifications);
  final FlutterLocalNotificationsPlugin notifications;
  static const _dailyChannel = MethodChannel('com.inomna/reminders');
  static const details = NotificationDetails(
    android: AndroidNotificationDetails('inom_na_doses', 'Medication reminders',
        channelDescription: 'Reminders when it is time to take a medication',
        importance: Importance.max,
        priority: Priority.high),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<SchedulerPermissionStatus> permissions({bool request = false}) async {
    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      final ios = notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        if (request)
          await ios.requestPermissions(alert: true, badge: true, sound: true);
        final status = await ios.checkPermissions();
        return SchedulerPermissionStatus(
            notificationsGranted: status?.isEnabled ?? false,
            exactAlarmsGranted: true);
      }
      return const SchedulerPermissionStatus(
          notificationsGranted: false, exactAlarmsGranted: false);
    }
    if (request) {
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
    }
    return SchedulerPermissionStatus(
      notificationsGranted: await android.areNotificationsEnabled() ?? false,
      exactAlarmsGranted:
          await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<List<PendingReminder>> pending() async =>
      (await notifications.pendingNotificationRequests())
          .map((notification) =>
              PendingReminder(notification.id, notification.payload))
          .toList();

  @override
  Future<bool> schedule(int id, PlannedReminder reminder, String payload,
      {required bool exact}) async {
    Future<void> register(bool useExact) async {
      final modePayload = jsonEncode(
          (jsonDecode(payload) as Map<String, dynamic>)..['exact'] = useExact);
      if (reminder.repeatDaily &&
          notifications.resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>() !=
              null) {
        final date = tz.TZDateTime.from(reminder.when, tz.local);
        String two(int value) => value.toString().padLeft(2, '0');
        // Existing plugin native support is exposed through a tiny bridge to
        // honor tomorrow/future starts after an early taken-dose cancellation.
        await _dailyChannel.invokeMethod<void>('scheduleDaily', {
          'id': id,
          'title': reminder.title,
          'body': reminder.body,
          'payload': modePayload,
          'timeZoneName': date.location.name,
          'scheduledDateTime':
              '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}T${two(date.hour)}:${two(date.minute)}:${two(date.second)}',
          'platformSpecifics': {
            ...details.android!.toMap(),
            'scheduleMode': (useExact
                    ? AndroidScheduleMode.exactAllowWhileIdle
                    : AndroidScheduleMode.inexactAllowWhileIdle)
                .name,
          },
        });
        return;
      }
      await notifications.zonedSchedule(
        id,
        reminder.title,
        reminder.body,
        tz.TZDateTime.from(reminder.when, tz.local),
        details,
        androidScheduleMode: useExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            reminder.repeatDaily ? DateTimeComponents.time : null,
        payload: modePayload,
      );
    }

    try {
      await register(exact);
      return exact;
    } on PlatformException catch (error) {
      if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
      await register(false);
      return false;
    }
  }

  @override
  Future<void> cancel(int id) => notifications.cancel(id);
}

/// Native local notifications with serialized, stable registration reconciliation.
class Scheduler {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static final _backend = NativeReminderBackend(_notifications);
  static final _coordinator =
      ReminderCoordinator(_backend, _PreferencesReminderState());
  static bool _initialized = false;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    try {
      _initialized =
          await _notifications.initialize(const InitializationSettings(
                android: AndroidInitializationSettings('@mipmap/ic_launcher'),
                iOS: DarwinInitializationSettings(),
              )) ??
              false;
    } catch (_) {
      _initialized = false;
    }
  }

  static Future<SchedulerPermissionStatus> permissionStatus() async {
    try {
      return await _backend.permissions();
    } catch (_) {
      return const SchedulerPermissionStatus(
          notificationsGranted: false, exactAlarmsGranted: false);
    }
  }

  static Future<SchedulerPermissionStatus> requestPermissions() async {
    try {
      return await _backend.permissions(request: true);
    } catch (_) {
      return permissionStatus();
    }
  }

  static const _unavailable = SchedulerResult(
      success: false,
      message:
          'Notifications are not ready. Restart the app and check Android settings.');
  static Future<SchedulerResult> rescheduleAll(List<Medicine> medicines) async {
    if (!_initialized) return _unavailable;
    return _coordinator.rescheduleAll(medicines);
  }

  static Future<SchedulerResult> cancelDose(
      Medicine medicine, DateTime dose) async {
    if (!_initialized) return _unavailable;
    return _coordinator.cancelDose(medicine, dose);
  }

  static Future<SchedulerResult> testInOneMinute(Medicine? medicine) async {
    if (!_initialized) return _unavailable;
    return _coordinator.testInOneMinute(medicine);
  }
}
