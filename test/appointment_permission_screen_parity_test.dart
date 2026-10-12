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

  test('Jobs cards prefer job title over customer requested work', () async {
    final card = await File('lib/widgets/job_compact_card.dart').readAsString();
    expect(card, contains('final description = title.isNotEmpty ? title : requested;'));
  });

  test('Paid Still Open filter excludes completed and unpaid jobs', () async {
    final jobs = await File('lib/screens/jobs_screen.dart').readAsString();
    final repo = await File('lib/services/local_job_repository.dart').readAsString();
    expect(jobs, contains("value: 'paid_still_open'"));
    expect(jobs, contains("Text('Paid, Still Open')"));
    expect(repo, contains("lower(COALESCE(payment_state, '')) = 'paid'"));
    expect(repo, contains("NOT IN ('completed','cancelled','closed')"));
  });

  test('full payment offers job completion without auto closing work', () async {
    final invoice = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(invoice, contains('_offerCompletePaidJob()'));
    expect(invoice, contains("paid >= total - 0.005"));
    expect(invoice, contains("await _api.jobDocuments(widget.businessId, jobId)"));
    expect(invoice, contains("child: const Text('Keep Job Open')"));
    expect(invoice, contains("child: const Text('Complete Job')"));
  });

  test('Standalone estimates use shared connection header without repeated title', () async {
    final source = await File('lib/screens/documents_screen.dart').readAsString();
    expect(source, contains('ConnectionHeaderToggle(businessId: widget.businessId)'));
    expect(source, contains('if (!_estimate) ...['));
    expect(source, contains('const BriskersLogo(height: 44, maxWidth: 148)'));
  });

  test('offline estimate conversion retains existing job and queues one invoice', () async {
    final draft = await File('lib/services/offline_document_draft_service.dart').readAsString();
    final screen = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(draft, contains('Future<String> convertEstimateOffline('));
    expect(draft, contains("'kind': 'convert_invoice'"));
    expect(draft, contains("serverId = await _api.convertEstimate(businessId, estimateServerId)"));
    expect(draft, contains("estimate['job_id']"));
    expect(screen, contains('_offlineDocumentDraft.convertEstimateOffline('));
    expect(screen, isNot(contains('Creating a new invoice from an estimate still requires a connection.')));
  });

  test('Customer Overview reads active offline records and excludes history', () async {
    final source = await File('lib/screens/customers/customer_detail_screen.dart').readAsString();
    expect(source, contains("Widget _customerOverviewCard()"));
    expect(source, contains('local_appointments'));
    expect(source, contains('local_jobs'));
    expect(source, contains('local_documents'));
    expect(source, contains("item['id']?.toString()"));
  });

  test('Document cards show a title under the customer name', () async {
    final source = await File('lib/screens/documents_screen.dart').readAsString();
    final repo = await File('lib/services/local_document_repository.dart').readAsString();
    expect(source, contains("if (documentTitle.isNotEmpty)"));
    expect(repo, contains('j.title AS job_title'));
  });

  test('Standalone Estimates restores main navigation and owner pill', () async {
    final docs = await File('lib/screens/documents_screen.dart').readAsString();
    expect(docs, contains('bottomNavigationBar: widget.showAppBar && _estimate'));
    expect(docs, contains('ShellScreen('));
    expect(docs, contains("child: Text('OWNER'"));
  });

  test('Custom item editor protects bottom buttons and selects numeric values', () async {
    final screen = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(screen, contains('child: AnimatedPadding('));
    expect(screen, contains('_taxPercent.selection = TextSelection('));
    expect(screen, contains('_quantity.selection = TextSelection('));
    expect(screen, contains('_price.selection = TextSelection('));
  });

  test('Estimates navigation reuses shell badges, not an isolated More tab', () async {
    final shell = await File('lib/screens/shell_screen.dart').readAsString();
    final home = await File('lib/screens/home_screen.dart').readAsString();
    final docs = await File('lib/screens/documents_screen.dart').readAsString();
    expect(shell, contains('estimatesNavigationBar: _shellNavigationBar()'));
    expect(home, contains('sharedBottomNavigationBar: widget.estimatesNavigationBar'));
    expect(docs, contains('widget.sharedBottomNavigationBar ?? NavigationBar('));
  });

  test('Standalone offline conversion keeps new Job open and linked on invoice', () async {
    final draft = await File('lib/services/offline_document_draft_service.dart').readAsString();
    final invoice = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(draft, contains("'job_number': provisionalJobId != null ? temporaryJobNumber"));
    expect(draft, contains("final temporaryJobNumber = 'TEMP-"));
    expect(draft, contains("'open','Open'"));
    expect(invoice, contains("final job = rawJob.isNotEmpty ? rawJob"));
    expect(invoice, contains("onTap: jobId.isEmpty ? null : _openLinkedJob"));
  });

  test('Shell preloads real payment method IDs and note templates when online', () async {
    final shell = await File('lib/screens/shell_screen.dart').readAsString();
    final screen = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(shell, contains('Future<void> _prepareOfflineChoices()'));
    expect(shell, contains('LocalPaymentMethodsCache().save(widget.businessId, methods)'));
    expect(shell, contains('LocalStandardNotesService().available('));
    expect(screen, contains('No payment methods saved offline.'));
  });

  test('Offline warranty on synced invoice queues changes for replay', () async {
    final screen = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    final edits = await File('lib/services/offline_document_edit_service.dart').readAsString();
    expect(screen, contains('.saveWarranty(widget.businessId,'));
    expect(edits, contains("'warranty',"));
    expect(edits, contains("operation == 'warranty'"));
    expect(edits, contains('await _api.updateDocumentWarranty('));
    expect(edits, contains("'offline_warranty_detail': updatedWarranty"));
  });

  test('Unsynced invoices use local standard notes even in Auto mode', () async {
    final screen = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(screen, contains('final offline = BriskersConnectionModeController.instance.forceOffline ||'));
    expect(screen, contains('_offlineDocumentDraft.isLocalDraftId(widget.documentId);'));
    expect(screen, contains('await _standardNotes.saveOffline('));
  });

  test('Warranty options and detail cache are prepared for offline reopening', () async {
    final shell = await File('lib/screens/shell_screen.dart').readAsString();
    final invoice = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(shell, contains('briskers_warranty_companies_'));
    expect(invoice, contains("'offline_warranty_detail': warrantyDetail"));
  });

  test('Offline warranty editor fits above system navigation and keyboard', () async {
    final source = await File('lib/screens/jobs/invoice_warranty_panel.dart').readAsString();
    expect(source, contains('isScrollControlled: true'));
    expect(source, contains('MediaQuery.viewInsetsOf(sheetContext).bottom + 18'));
    expect(source, contains("allowCreate: false"));
    expect(source, contains("tr('saveWarrantyInformation')"));
  });

}

