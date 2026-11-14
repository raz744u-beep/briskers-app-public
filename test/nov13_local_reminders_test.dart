import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_task_reminders.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('dexterous.com/flutter/local_notifications');
  final pending=<int,Map<dynamic,dynamic>>{};
  setUp((){debugDefaultTargetPlatformOverride=TargetPlatform.android;AndroidFlutterLocalNotificationsPlugin.registerWith();pending.clear();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call)async{
    if(call.method=='initialize'||call.method=='areNotificationsEnabled'||call.method=='requestNotificationsPermission')return true;
    if(call.method=='pendingNotificationRequests')return pending.values.map((v)=>{'id':v['id'],'title':v['title'],'body':v['body'],'payload':v['payload']}).toList();
    final args=call.arguments as Map?;
    if(call.method=='zonedSchedule')pending[args!['id'] as int]=args;
    if(call.method=='cancel')pending.remove(args!['id']);
    return null;
  });});
  tearDown((){debugDefaultTargetPlatformOverride=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);});
  test('offline reminder edits replace one stable alarm; restart reuses identity and Done cancels it',()async{
    final due=DateTime.now().add(const Duration(days:1));
    final task=<String,dynamic>{'id':7,'description':'Order part','status':'planned','due_at':due.millisecondsSinceEpoch,'reminder_enabled':1,'reminder_minutes':15};
    await LocalTaskReminders().sync('shop',[task]);await LocalTaskReminders().sync('shop',[task]);expect(pending,hasLength(1));
    final id=LocalTaskReminders.notificationId('shop',7);expect(pending.singleValue['id'],id);
    await LocalTaskReminders().sync('shop',[{...task,'description':'Order revised part','due_at':due.add(const Duration(hours:1)).millisecondsSinceEpoch}]);expect(pending,hasLength(1));expect(pending[id]!['body'],'Order revised part');
    await LocalTaskReminders().sync('shop',[{...task,'status':'done'}]);expect(pending,isEmpty);
    await LocalTaskReminders().sync('shop',[{...task,'reminder_enabled':0}]);expect(pending,isEmpty);
    await LocalTaskReminders().sync('shop',[task]);
    await LocalTaskReminders().sync('other',[task]);
    await LocalTaskReminders().sync('shop',[]);
    expect(pending,hasLength(1));expect(pending.containsKey(LocalTaskReminders.notificationId('other',7)),isTrue);
    expect(LocalTaskReminders.notificationId('other',7),isNot(id));
  });
}
extension _OnlyValue<K,V> on Map<K,V>{V get singleValue=>values.single;}
