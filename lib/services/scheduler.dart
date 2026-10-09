import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';

/// Offline na reminders: naka-schedule sa phone mismo, walang internet na kailangan.
class Scheduler {
  static final _n = FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'inom_na_doses',
      'Paalala sa gamot',
      channelDescription: 'Paalala kapag oras na ng gamot',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    await _n.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
  }

  static Future<void> requestPermissions() async {
    final android = _n.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    final ios = _n.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> _at(int id, String title, String body, DateTime when,
      {DateTimeComponents? repeat}) async {
    final t = tz.TZDateTime.from(when, tz.local);
    Future<void> go(AndroidScheduleMode mode) => _n.zonedSchedule(
          id, title, body, t, _details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeat,
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // kapag walang exact-alarm permission
      await go(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Burahin lahat at i-schedule ulit base sa kasalukuyang listahan.
  static Future<void> rescheduleAll(List<Medicine> meds) async {
    await _n.cancelAll();
    final now = DateTime.now();
    var id = 1;
    const maxAlarms = 400; // limit ng Android sa dami ng naka-schedule

    for (final m in meds) {
      if (m.isPrn || m.isFinished) continue;
      final extra = m.instructions.isEmpty ? '' : ' (${m.instructions})';
      final body = 'Inumin: ${m.qtyLabel} ${m.name} ${m.dose}$extra'.trim();

      if (m.isMaintenance) {
        for (final t in m.times) {
          var next = Medicine.atTime(now, t);
          if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
          await _at(id++, '💊 Oras na ng gamot', body, next,
              repeat: DateTimeComponents.time);
        }
      } else {
        for (final d in m.allDoses(horizon: now)) {
          if (id >= maxAlarms) break;
          if (d.isAfter(now) && !m.isTaken(d)) {
            await _at(id++, '💊 Oras na ng gamot', body, d);
          }
        }
      }

      // Refill alert: 3 araw bago maubos ang nabili
      if (m.needsRefill) {
        final perDay = m.timesPerDay * m.qtyPerIntake;
        final daysCovered = (m.stock! / perDay).floor();
        final d0 = DateTime(m.start.year, m.start.month, m.start.day);
        final alert = DateTime(d0.year, d0.month, d0.day + daysCovered - 3, 9);
        if (alert.isAfter(now)) {
          await _at(id++, '🛒 Malapit nang maubos',
              '3 araw na lang ang ${m.name}. Bumili ka na.', alert);
        }
      }
    }
  }

  /// Pang-demo: tutunog pagkalipas ng 1 minuto.
  static Future<void> testInOneMinute(Medicine? m) async {
    final body = m == null
        ? 'Ito ang itsura ng paalala.'
        : 'Inumin: ${m.qtyLabel} ${m.name} ${m.dose}'.trim();
    await _at(9999, '💊 Oras na ng gamot', body,
        DateTime.now().add(const Duration(minutes: 1)));
  }
}
