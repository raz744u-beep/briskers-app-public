import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/appointment_action_policy.dart';

void main() {
  test('owner can edit statuses offline including linked jobs', () {
    expect(AppointmentActionPolicy.canEdit(
      canManage:true,isOwner:true,linkedJob:true,
      status:'cancelled',conflict:false),isTrue);
  });
  test('secretary may edit confirmed unlinked, not cancelled or linked', () {
    expect(AppointmentActionPolicy.canEdit(
      canManage:true,isOwner:false,linkedJob:false,
      status:'confirmed',conflict:false),isTrue);
    expect(AppointmentActionPolicy.canEdit(
      canManage:true,isOwner:false,linkedJob:false,
      status:'cancelled',conflict:false),isFalse);
    expect(AppointmentActionPolicy.canEdit(
      canManage:true,isOwner:false,linkedJob:true,
      status:'confirmed',conflict:false),isFalse);
  });
  test('secretary may cancel but cannot delete', () {
    expect(AppointmentActionPolicy.canCancel(
      canManage:true,linkedJob:false,status:'confirmed',
      pending:false,conflict:false),isTrue);
    expect(AppointmentActionPolicy.canDelete(
      isOwner:false,linkedJob:false,linkedRequest:false,
      pending:false,conflict:false),isFalse);
    expect(AppointmentActionPolicy.canDelete(
      isOwner:true,linkedJob:true,linkedRequest:false,
      pending:false,conflict:false),isFalse);
  });
}
