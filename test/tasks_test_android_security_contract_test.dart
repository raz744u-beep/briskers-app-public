import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Offline Tasks TEST strips unrelated Android runtime permissions', () {
    final here = File('.github/workflows/android-tasks-test.yml');
    final workflow = (here.existsSync()
      ? here : File('../.github/workflows/android-tasks-test.yml'))
      .readAsStringSync();
    expect(workflow,contains("applicationId = \"com.briskers.tasks_lab\""));
    expect(workflow,contains('class MainActivity : FlutterActivity()'));
    expect(workflow,isNot(contains('class MainActivity : FlutterActivity() {')));
    expect(workflow,contains('tools:node="remove"'));
    expect(workflow,contains('Verify offline TEST APK requests no unrelated runtime permissions'));
    expect(workflow,contains('Isolated TEST runtime permissions audited: PASS'));
    for (final permission in [
      'android.permission.CAMERA',
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_SHORT_SERVICE',
      'android.permission.WAKE_LOCK',
    ]) {
      expect(workflow,contains(permission));
    }
    expect(workflow,contains('Verify APK is signed'));
    expect(workflow,contains('briskers-release.jks'));
    final main = File('lib/tasks_lab_main.dart').readAsStringSync();
    expect(main,isNot(contains('Supabase.initialize')));
    expect(main,isNot(contains('BriskersApi')));
  });
}
