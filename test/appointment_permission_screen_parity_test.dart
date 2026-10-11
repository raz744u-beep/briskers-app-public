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
    expect(list, contains('View dependencies / deletion options'));
    expect(list, contains('_showAppointmentDependencies(item)'));
    expect(list, contains('Linked job ID:'));
    expect(list, contains('Customer request ID:'));
  });
  test('REL-001 diagnostics flags orphaned appointment job relationships', () async {
    final diagnostics = await File('lib/services/diagnostics_service.dart')
        .readAsString();
    expect(diagnostics, contains("'Appointments missing job': await _count("));
    expect(diagnostics, contains('LEFT JOIN local_jobs j'));
    expect(diagnostics, contains('a.job_id IS NOT NULL'));
    expect(diagnostics, contains("a.sync_state <> 'pending_delete'"));
  });

  test('main list pages keep Add action beside search and invoice close', () async {
    final jobs = await File('lib/screens/jobs_screen.dart').readAsString();
    final documents = await File('lib/screens/documents_screen.dart').readAsString();
    final expenses = await File('lib/screens/expenses_screen.dart').readAsString();
    expect(jobs, contains("tooltip: 'New Job'"));
    expect(jobs, contains('onPressed: _createNewJob'));
    expect(documents, contains("tooltip: _estimate ? 'New Estimate' : 'New Invoice'"));
    expect(documents, contains('onPressed: _showCloseInvoices'));
    expect(expenses, contains("tooltip: 'Add transaction'"));
    expect(expenses, contains('onPressed: _importing ? null : _showAddMenu'));
    expect(expenses, isNot(contains('_importing || _showingLocal ? null : _showAddMenu')));
  });

  test('customer Add tap and appointment Add work while offline', () async {
    final customers = await File('lib/screens/customers/customers_screen.dart').readAsString();
    final appointments = await File('lib/screens/appointments_screen.dart').readAsString();
    expect(customers, contains('if (!_canManageCustomers) return;'));
    expect(customers, isNot(contains('if (!_onlineReady) return;')));
    expect(appointments, contains("tooltip: 'Add appointment'"));
    expect(appointments, contains('onPressed: _addAppointment'));
  });

  test('invoice customer autocomplete replaces duplicated dropdown', () async {
    final form = await File('lib/screens/jobs/blank_invoice_setup_screen.dart').readAsString();
    expect(form, contains("hintText: 'Start typing name, phone, or email'"));
    expect(form, contains('ListView.builder('));
    expect(form, isNot(contains("labelText: 'Find customer'")));
    expect(form, isNot(contains('_customerDropdownVersion')));
  });

  test('expenses search has matching elevated pill style', () async {
    final expenses = await File('lib/screens/expenses_screen.dart').readAsString();
    expect(expenses, contains('child: SearchBar('));
    expect(expenses, contains('WidgetStatePropertyAll<double>(3)'));
    expect(expenses, contains('WidgetStatePropertyAll<Color>('));
    expect(expenses, contains("tooltip: 'Add transaction'"));
  });

  test('offline New Job routes to durable create queue', () async {
    final jobs=await File('lib/screens/jobs_screen.dart').readAsString();
    final form=await File('lib/screens/jobs/job_create_screen.dart').readAsString();
    final admin=await File('lib/services/offline_job_admin_service.dart').readAsString();
    expect(jobs, isNot(contains('New job creation needs a connection in this version')));
    expect(form, contains('_offlineJobs.queueJobCreate('));
    expect(admin, contains('Future<String> queueJobCreate('));
    expect(admin, contains('Future<void> flushCreates('));
  });

  test('New Job uses a keyboard-safe full screen customer picker', () async {
    final jobs = await File('lib/screens/jobs_screen.dart').readAsString();
    final picker = await File('lib/screens/jobs/job_customer_picker_screen.dart')
        .readAsString();
    expect(jobs, contains('JobCustomerPickerScreen(businessId: widget.businessId)'));
    expect(jobs, isNot(contains("title: const Text('New job — choose customer')")));
    expect(picker, contains('Scaffold('));
    expect(picker, contains('Expanded('));
    expect(picker, contains('onTap: () => Navigator.pop(context, customer)'));
  });

  test('shared header exposes real connection preferences and sync timestamp', () async {
    final shell = await File('lib/screens/shell_screen.dart').readAsString();
    final header = await File('lib/widgets/connection_header_toggle.dart')
        .readAsString();
    expect(shell, contains('ConnectionHeaderToggle(businessId: widget.businessId)'));
    expect(header, contains('BriskersConnectionMode.offline'));
    expect(header, contains('BriskersConnectionMode.online'));
    expect(header, contains('BriskersConnectionMode.auto'));
    expect(header, contains('await _controller.setMode(next)'));
    expect(header, contains('MAX(last_pull_at)'));
    expect(header, contains('Not yet synced'));
  });

  test('New Job form exposes complaint and save controls with keyboard safe scroll', () async {
    final form = await File('lib/screens/jobs/job_create_screen.dart').readAsString();
    expect(form, contains('resizeToAvoidBottomInset: true'));
    expect(form, contains('ScrollViewKeyboardDismissBehavior.onDrag'));
    expect(form, contains('MediaQuery.viewInsetsOf(context).bottom'));
    expect(form, contains("labelText: 'Requested work / complaint'"));
    expect(form, contains("hintText: 'Describe the customer complaint or requested service'"));
    expect(form, contains('enabledBorder: OutlineInputBorder('));
    expect(form, contains("onPressed: _saving ? null : _save"));
  });

  test('offline new Jobs are sorted before historical jobs', () async {
    final repository = await File('lib/services/local_job_repository.dart').readAsString();
    expect(repository, contains("j.sync_state = 'pending' AND j.job_number = 'Pending sync'"));
    expect(repository, contains('THEN j.created_at END DESC'));
  });

}

