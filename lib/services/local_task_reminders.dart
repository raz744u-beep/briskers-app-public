import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Device-local notifications; scheduling never requires Supabase or internet.
class LocalTaskReminders {
  final FlutterLocalNotificationsPlugin plugin;
  LocalTaskReminders({FlutterLocalNotificationsPlugin? notifications})
    : plugin = notifications ?? FlutterLocalNotificationsPlugin();
  static int notificationId(String business, int task) {
    var value = 2166136261;
    for (final c in '$business/general/$task'.codeUnits) {
      value = ((value ^ c) * 16777619) & 0x7fffffff;
    }
    return value;
  }

  // General task IDs are positive. A negative ID keeps the weekly reminder
  // independent of task reminders for the same business.
  static int _closeoutId(String business) => -1 - notificationId(business, 0);

  Future<bool> fridayCloseoutEnabled(String business) async {
    if (!await prepare()) return false;
    return (await plugin.pendingNotificationRequests()).any(
      (request) => request.id == _closeoutId(business),
    );
  }

  Future<void> setFridayCloseoutReminder(String business, bool enabled) async {
    final allowed = await prepare(requestPermission: enabled);
    if (!enabled) {
      await plugin.cancel(id: _closeoutId(business));
      return;
    }
    if (!allowed) throw const TaskReminderUnavailable();
    final shop = tz.getLocation('America/Chicago');
    final now = tz.TZDateTime.now(shop);
    final days = (DateTime.friday - now.weekday + 7) % 7;
    var next = tz.TZDateTime(shop, now.year, now.month, now.day + days, 15);
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(shop, now.year, now.month, now.day + days + 7, 15);
    }
    await plugin.zonedSchedule(
      id: _closeoutId(business),
      title: 'Briskers Friday Closeout',
      body: 'Open Owner Reports → Friday Closeout to review the latest saved shop records.',
      scheduledDate: next,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'briskers_closeout',
          'Friday Closeout',
          icon: 'ic_task_reminder',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<bool> prepare({bool requestPermission = false}) async {
    try {
      return await _prepare(requestPermission: requestPermission);
    } on PlatformException {
      throw const TaskReminderUnavailable();
    }
  }

  Future<bool> _prepare({bool requestPermission = false}) async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return false;
    }
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_task_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      return (requestPermission
              ? await android.requestNotificationsPermission()
              : await android.areNotificationsEnabled()) ??
          false;
    }
    if (requestPermission) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  Future<void> sync(String business, List<Map<String, dynamic>> tasks) async {
    try {
      await _sync(business, tasks);
    } on PlatformException {
      throw const TaskReminderUnavailable();
    }
  }

  Future<void> _sync(String business, List<Map<String, dynamic>> tasks) async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    final allowed = await prepare();
    final activeIds = tasks
        .map((t) => notificationId(business, t['id'] as int))
        .toSet();
    for (final pending in await plugin.pendingNotificationRequests()) {
      final raw = pending.payload;
      if (raw == null || !raw.startsWith('{')) continue;
      final data = jsonDecode(raw);
      if (data is Map &&
          data['kind'] == 'general' &&
          data['business'] == business &&
          !activeIds.contains(pending.id)) {
        await plugin.cancel(id: pending.id);
      }
    }
    for (final task in tasks) {
      final id = notificationId(business, task['id'] as int);
      final enabled = task['reminder_enabled'] == 1;
      final due = task['due_at'] as int?;
      if (!enabled || due == null || task['status'] == 'done') {
        await plugin.cancel(id: id);
        continue;
      }
      final when = DateTime.fromMillisecondsSinceEpoch(due)
          .subtract(Duration(minutes: task['reminder_minutes'] as int? ?? 0));
      if (!when.isAfter(DateTime.now())) {
        await plugin.cancel(id: id);
        continue;
      }
      if (!allowed) continue;
      await plugin.zonedSchedule(
        id: id,
        title: 'Briskers task reminder',
        body: task['description'] as String?,
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'briskers_tasks',
            'Task reminders',
            channelDescription: 'Assigned General Task due reminders',
            icon: 'ic_task_reminder',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({
          'kind': 'general',
          'business': business,
          'task': task['id'],
        }),
      );
    }
  }
}

class TaskReminderUnavailable implements Exception {
  const TaskReminderUnavailable();
  @override
  String toString() =>
      'This device could not update task reminders. Check notification settings and try again.';
}
