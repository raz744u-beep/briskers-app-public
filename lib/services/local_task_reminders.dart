import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  Future<bool> prepare({bool requestPermission = false}) async {
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
    if(kIsWeb || ![TargetPlatform.android,TargetPlatform.iOS].contains(defaultTargetPlatform))return;
    final allowed=await prepare();
    final activeIds=tasks.map((t)=>notificationId(business,t['id'] as int)).toSet();
    for(final pending in await plugin.pendingNotificationRequests()) {
      final raw=pending.payload;
      if(raw==null || !raw.startsWith('{'))continue;
      final data=jsonDecode(raw);
      if(data is Map && data['kind']=='general' && data['business']==business && !activeIds.contains(pending.id))await plugin.cancel(id:pending.id);
    }
    for (final task in tasks) {
      final id = notificationId(business, task['id'] as int);
      final enabled = task['reminder_enabled'] == 1;
      final due = task['due_at'] as int?;
      if (!enabled || due == null || task['status'] == 'done') {
        await plugin.cancel(id: id);
        continue;
      }
      final when = DateTime.fromMillisecondsSinceEpoch(
        due,
      ).subtract(Duration(minutes: task['reminder_minutes'] as int? ?? 0));
      if (!when.isAfter(DateTime.now())) {
        await plugin.cancel(id: id);
        continue;
      }
      if(!allowed)continue;
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
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({'kind':'general','business':business,'task':task['id']}),
      );
    }
  }
}
