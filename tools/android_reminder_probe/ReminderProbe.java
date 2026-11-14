package com.briskers.reminderprobe;

import android.app.Instrumentation;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Bundle;
import android.service.notification.StatusBarNotification;
import org.json.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

/** Test-only instrumentation, installed on an isolated CI emulator. It calls
 * the notification plugin contained in the actual candidate APK, using the
 * payload recorded from LocalTaskReminders. It never opens the shop database. */
public class ReminderProbe extends Instrumentation {
  Object plugin;
  Method invoke;
  Class<?> callType, resultType;
  final int id=19601114;

  @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
  static Object convert(Object value) throws Exception {
    if(value==JSONObject.NULL)return null;
    if(value instanceof JSONObject){Map<String,Object> out=new HashMap<>();JSONObject json=(JSONObject)value;Iterator<String> keys=json.keys();while(keys.hasNext()){String k=keys.next();out.put(k,convert(json.get(k)));}return out;}
    if(value instanceof JSONArray){List<Object> out=new ArrayList<>();JSONArray a=(JSONArray)value;for(int i=0;i<a.length();i++)out.add(convert(a.get(i)));return out;}
    return value;
  }
  Object call(String name, Object args) throws Exception {
    Object[] result={null};boolean[] completed={false};
    Object callback=Proxy.newProxyInstance(resultType.getClassLoader(),new Class<?>[]{resultType},(p,m,a)->{
      if(m.getName().equals("success")){completed[0]=true;result[0]=a[0];}
      else if(m.getName().equals("error")){throw new AssertionError("Plugin error "+Arrays.toString(a));}
      else if(m.getName().equals("notImplemented")){throw new AssertionError("Plugin method unavailable: "+name);}
      return null;
    });
    invoke.invoke(plugin,callType.getConstructor(String.class,Object.class).newInstance(name,args),callback);
    if(!completed[0])throw new AssertionError("Missing plugin result: "+name);
    return result[0];
  }
  void require(boolean ok,String message){if(!ok)throw new AssertionError(message);}
  @Override public void onStart() {
    Bundle result=new Bundle();
    try {
      Context target=getTargetContext();
      int icon=target.getResources().getIdentifier("ic_task_reminder","drawable",target.getPackageName());
      require(icon!=0,"Release drawable not packaged");
      Class<?> type=target.getClassLoader().loadClass("com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin");
      plugin=type.getConstructor().newInstance();
      Field context=type.getDeclaredField("applicationContext");context.setAccessible(true);context.set(plugin,target.getApplicationContext());
      for(Method m:type.getMethods())if(m.getName().equals("onMethodCall")){invoke=m;break;}
      require(invoke!=null,"Plugin method channel not found");callType=invoke.getParameterTypes()[0];resultType=invoke.getParameterTypes()[1];
      call("initialize",Collections.singletonMap("defaultIcon","ic_task_reminder"));
      NotificationManager manager=(NotificationManager)target.getSystemService(Context.NOTIFICATION_SERVICE);
      require(manager.areNotificationsEnabled(),"Notification permission missing");
      String json=new String(getContext().getAssets().open("request.json").readAllBytes(),StandardCharsets.UTF_8);
      @SuppressWarnings("unchecked") Map<String,Object> args=(Map<String,Object>)convert(new JSONObject(json));
      args.put("id",id);args.put("title","Briskers offline reminder verification");args.put("body","Synthetic reminder; no customer or payroll records changed");
      args.put("timeZoneName","UTC");
      args.put("scheduledDateTime",LocalDateTime.ofInstant(Instant.now().plusSeconds(5),ZoneOffset.UTC).format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")));
      call("zonedSchedule",args);call("zonedSchedule",args);
      List<?> pending=(List<?>)call("pendingNotificationRequests",null);
      require(pending.stream().filter(v->((Map<?,?>)v).get("id").equals(id)).count()==1,"Duplicate or missing pending reminder");
      StatusBarNotification delivered=null;
      long deadline=System.currentTimeMillis()+150000;
      while(System.currentTimeMillis()<deadline){for(StatusBarNotification n:manager.getActiveNotifications())if(n.getId()==id)delivered=n;if(delivered!=null)break;Thread.sleep(1000);}
      require(delivered!=null,"Scheduled reminder did not trigger");
      require(delivered.getNotification().getSmallIcon().getResId()==icon,"Wrong delivered notification icon");
      require(manager.getActiveNotifications().length==1,"Unexpected duplicate notifications");
      call("cancel",Collections.singletonMap("id",id));
      require(((List<?>)call("pendingNotificationRequests",null)).stream().noneMatch(v->((Map<?,?>)v).get("id").equals(id)),"Reminder not cancelled");
      result.putString("stream","REMINDER_PROBE_PASS: actual APK plugin initialized, stable schedule replaced, offline alarm triggered with packaged icon, cancellation verified.\n");
      finish(-1,result);
    }catch(Throwable error){result.putString("stream","REMINDER_PROBE_FAILED: "+error+"\n"+Arrays.toString(error.getStackTrace()));finish(0,result);}
  }
}
