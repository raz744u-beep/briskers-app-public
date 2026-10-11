import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appointment editor and list share offline owner policy and linked Job guard', () async {
    final form=await File('lib/screens/appointments/appointment_manage_screen.dart').readAsString();
    final list=await File('lib/screens/appointments_screen.dart').readAsString();
    final policy=await File('lib/core/appointment_action_policy.dart').readAsString();
    expect(form,contains('AppointmentActionPolicy.canEdit('));
    expect(list,contains('AppointmentActionPolicy.canEdit('));
    expect(list,contains('AppointmentActionPolicy.canDelete('));
    expect(list,contains('AppointmentActionPolicy.canCancel('));
    expect(form,contains("widget.appointment?['job_id'] != null"));
    expect(policy,contains('isOwner ||'));
    expect(policy,contains("status == 'confirmed'"));
  });

  test('appointment cards expose long press actions and guard tab-entry refresh', () async {
    final list = await File('lib/screens/appointments_screen.dart').readAsString();
    expect(list, contains('onLongPress: (_canManage || _canCheckIn)'));
    expect(list, contains('? () => _showOptions(item)'));
    expect(list, contains("case 'delete':"));
    expect(list, contains('AppointmentActionPolicy.canDelete('));
    expect(list, contains('_load(initialEntry: true)'));
    expect(list, contains('_entryRefreshInterval'));
    expect(list, contains('initialEntry && !forceOnline && localAvailable'));
    expect(list, contains('onRefresh: _load'));
  });
}

