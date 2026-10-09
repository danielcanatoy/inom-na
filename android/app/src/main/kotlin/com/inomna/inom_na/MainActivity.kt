package com.inomna.inom_na

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import com.dexterous.flutterlocalnotifications.models.ScheduledNotificationRepeatFrequency

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.inomna/reminders")
            .setMethodCallHandler { call, result ->
                if (call.method != "scheduleDaily") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val arguments = call.arguments as? Map<*, *>
                val plugin = flutterEngine.plugins.get(FlutterLocalNotificationsPlugin::class.java)
                    as? FlutterLocalNotificationsPlugin
                if (arguments == null || plugin == null) {
                    result.error("reminders_unavailable", "Reminder registration unavailable", null)
                    return@setMethodCallHandler
                }
                // v17's matchDateTimeComponents.time ignores the first date.
                // Its existing native daily repeat preserves that date and uses
                // the same persisted cache, receiver and reboot recovery.
                val nativeArguments = HashMap<String, Any?>()
                for ((key, value) in arguments) {
                    if (key is String) nativeArguments[key] = value
                }
                nativeArguments.remove("matchDateTimeComponents")
                nativeArguments["scheduledNotificationRepeatFrequency"] =
                    ScheduledNotificationRepeatFrequency.Daily.ordinal
                try {
                    plugin.onMethodCall(MethodCall("zonedSchedule", nativeArguments), result)
                } catch (_: Exception) {
                    result.error("reminder_registration_failed", "Reminder registration failed", null)
                }
            }
    }
}
