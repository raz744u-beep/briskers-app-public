import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/job_list_options.dart';
import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/customer_document_summary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('main list pages keep permission-safe bottom New actions and invoice close', () async {
    final jobs = await File('lib/screens/jobs_screen.dart').readAsString();
    final documents = await File('lib/screens/documents_screen.dart').readAsString();
    final expenses = await File('lib/screens/expenses_screen.dart').readAsString();
    expect(jobs, contains("tooltip: 'New Job'"));
    expect(jobs, contains('onPressed: _createNewJob'));
    expect(documents, contains("tooltip: _estimate ? 'New Estimate' : 'New Invoice'"));
    expect(documents, contains('onPressed: _showCloseInvoices'));
    expect(expenses, contains("tooltip: 'Add transaction'"));
    expect(expenses, contains('onPressed: _importing || _loading ? null : _showAddMenu'));
    expect(expenses, contains('FloatingActionButton.extended('));
    expect(jobs, contains('shape: RoundedRectangleBorder('));
    expect(documents, contains('shape: RoundedRectangleBorder('));
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
    expect(header, contains('LocalSyncStatusRepository'));
    expect(header, contains('didChangeAppLifecycleState'));
    expect(header, contains('Sync needs attention'));
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
    expect(repository, contains("j.job_number = 'Pending sync'"));
    expect(repository, contains("OR upper(j.job_number) LIKE 'TEMP-%'"));
    expect(repository, isNot(contains("j.sync_state = 'pending' AND j.job_number")));
    expect(repository, contains('THEN j.created_at END DESC'));
  });

  test(
    'New Job is saved before detail opens and refreshes the list on return',
    () async {
      final jobs = await File('lib/screens/jobs_screen.dart').readAsString();
      final form = await File('lib/screens/jobs/job_create_screen.dart')
          .readAsString();
      final shell = await File('lib/screens/shell_screen.dart').readAsString();
      final createStart = jobs.indexOf('Future<void> _createNewJob()');
      final createEnd = jobs.indexOf('Future<void> _load(', createStart);
      expect(createStart, greaterThanOrEqualTo(0));
      expect(createEnd, greaterThan(createStart));
      final createFlow = jobs.substring(createStart, createEnd);
      expect(createFlow, contains('JobCreateScreen('));
      final returned = createFlow.substring(
        createFlow.indexOf('if (created == true && mounted)'),
      );
      final refresh = returned.indexOf('await _load();');
      final notify = returned.indexOf('widget.onJobsChanged?.call();');
      expect(refresh, greaterThanOrEqualTo(0));
      expect(notify, greaterThan(refresh));

      // Detail is opened by the durable creation form, before it returns true.
      final saveStart = form.indexOf('Future<void> _save()');
      final saveEnd = form.indexOf('Widget build(', saveStart);
      expect(saveStart, greaterThanOrEqualTo(0));
      expect(saveEnd, greaterThan(saveStart));
      final saveFlow = form.substring(saveStart, saveEnd);
      final queued = saveFlow.indexOf('await _offlineJobs.queueJobCreate(');
      final stableId = saveFlow.indexOf('_createdJobId = jobId;');
      final detail = saveFlow.indexOf('JobDetailScreen(');
      final finish = saveFlow.indexOf('Navigator.pop(context, true)');
      expect(queued, greaterThanOrEqualTo(0));
      expect(stableId, greaterThan(queued));
      expect(detail, greaterThan(stableId));
      expect(finish, greaterThan(detail));
      expect(saveFlow, contains('jobId: jobId'));
      expect(saveFlow, contains('roleCode: widget.roleCode'));

      final jobsTab = shell.indexOf('return JobsScreen(');
      final lazyPages = shell.indexOf('_lazyPages.putIfAbsent(index');
      expect(jobsTab, greaterThanOrEqualTo(0));
      expect(lazyPages, greaterThan(jobsTab));
      expect(shell, contains('refreshToken: _jobsRefreshToken'));
      expect(jobs, contains('oldWidget.refreshToken != widget.refreshToken'));
    },
  );

  test('Jobs cards prefer job title over customer requested work', () async {
    final card = await File('lib/widgets/job_compact_card.dart').readAsString();
    expect(card, contains('final description = title.isNotEmpty ? title : requested;'));
  });

  test('Paid Still Open uses translated copy and returns only paid unfinished Jobs', () async {
    final source = await File('lib/screens/jobs_screen.dart').readAsString();
    expect(source, contains("value: 'paid_still_open'"));
    expect(
      source,
      matches(RegExp(r"_text\(\s*'Paid, Still Open',\s*'Pagado, aún abierto'")),
    );
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LocalJobRepository(database: db);
    for (final item in [
      ('paid-open', 'open', 'paid'),
      ('paid-working', 'in_progress', 'paid'),
      ('paid-completed', 'completed', 'paid'),
      ('paid-cancelled', 'cancelled', 'paid'),
      ('paid-closed', 'closed', 'paid'),
      ('part-paid', 'open', 'partial'),
      ('unpaid', 'open', 'unpaid'),
    ]) {
      await db.customStatement(
        'INSERT INTO local_jobs(id,business_id,access_scope,title,status,payment_state) '
        "VALUES (?,'shop','all','Repair',?,?)",
        [item.$1, item.$2, item.$3],
      );
    }
    for (final view in JobListView.values) {
      final rows = await repository.listJobs(
        'shop',
        view: view,
        status: 'paid_still_open',
      );
      expect(rows.map((row) => row['id']).toSet(), {
        'paid-open',
        'paid-working',
      });
      expect(
        await repository.jobCount(
          'shop',
          view: view,
          status: 'paid_still_open',
        ),
        2,
      );
    }
  });

  test('full payment offers job completion without auto closing work', () async {
    final invoice = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(invoice, contains('_offerCompletePaidJob()'));
    expect(invoice, contains("paid >= total - 0.005"));
    expect(invoice, contains("await _api.jobDocuments(widget.businessId, jobId)"));
    expect(invoice, contains("child: const Text('Keep In Progress')"));
    expect(invoice, contains("title: const Text('Mark Job Completed?')"));
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
    expect(draft, contains("() => _api.convertEstimate(businessId, estimateServerId)"));
    expect(draft, contains('LocalJobQuarantine.guardReplay('));
    expect(draft, contains("estimate['job_id']"));
    expect(screen, contains('_offlineDocumentDraft.convertEstimateOffline('));
    expect(screen, isNot(contains('Creating a new invoice from an estimate still requires a connection.')));
  });

  test('Customer Overview delegates saved documents and keeps closed history separate', () async {
    final source = await File(
      'lib/screens/customers/customer_detail_screen.dart',
    ).readAsString();
    final activeStart = source.indexOf(
      'Future<List<Map<String, dynamic>>> _activeCustomerItems()',
    );
    final activeEnd = source.indexOf(
      'Widget _customerOverviewCard()',
      activeStart,
    );
    expect(activeStart, greaterThanOrEqualTo(0));
    expect(activeEnd, greaterThan(activeStart));
    final activeFlow = source.substring(activeStart, activeEnd);
    expect(activeFlow, contains('local_appointments'));
    expect(activeFlow, contains('local_jobs'));
    expect(
      activeFlow,
      contains(
        "NOT IN ('cancelled','canceled','no_show','checked_in','completed')",
      ),
    );
    expect(activeFlow, contains('includeClosed: true'));
    expect(activeFlow, contains("'type': 'Visit'"));
    expect(
      activeFlow,
      contains('CustomerDocumentSummaryService().forCustomer('),
    );
    expect(activeFlow, contains('widget.businessId, widget.customerId'));
    expect(activeFlow, contains('visibility.filter(rows, jobIdKey:'));
    expect(source, contains("item['id']?.toString()"));

    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final item in [
      ('open', 'shop', 'customer', 'draft', null),
      ('paid-pending', 'shop', 'customer', 'paid', null),
      ('closed', 'shop', 'customer', 'paid', 123),
      ('void', 'shop', 'customer', 'void', null),
      ('other-customer', 'shop', 'other', 'draft', null),
      ('other-shop', 'other', 'customer', 'draft', null),
    ]) {
      await db.customStatement(
        'INSERT INTO local_documents(id,business_id,customer_id,kind,status,closed_at,total) '
        "VALUES (?,?,?,'invoice',?,?,100)",
        [item.$1, item.$2, item.$3, item.$4, item.$5],
      );
    }
    final summaries = CustomerDocumentSummaryService(database: db);
    final active = await summaries.forCustomer('shop', 'customer');
    expect(active.map((row) => row['id']).toSet(), {'open', 'paid-pending'});
    final history = await summaries.forCustomer(
      'shop',
      'customer',
      includeClosed: true,
    );
    expect(history.map((row) => row['id']).toSet(), {
      'open',
      'paid-pending',
      'closed',
    });
    expect(
      DocumentPresentation(history.singleWhere((row) => row['id'] == 'closed'))
          .isClosed,
      isTrue,
    );
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });

  test('Document cards show a title under the customer name', () async {
    final source = await File('lib/screens/documents_screen.dart').readAsString();
    final repo = await File('lib/services/local_document_repository.dart').readAsString();
    expect(source, contains("if (documentTitle.isNotEmpty)"));
    expect(repo, contains('j.title AS job_title'));
  });

  test('Standalone Estimates restores main navigation and owner pill', () async {
    final docs = await File('lib/screens/documents_screen.dart').readAsString();
    expect(docs, contains('bottomNavigationBar: widget.customerId != null &&'));
    expect(docs, contains('widget.sharedBottomNavigationBar!'));
    expect(docs, contains(': widget.showAppBar && _estimate'));
    expect(docs, contains('ShellScreen('));
    expect(docs, matches(RegExp(r"child:\s*Text\(\s*'OWNER'")));
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
    expect(shell, contains('estimatesNavigationBar: _shellNavigationBar(nested: true)'));
    expect(shell, contains("label: 'Estimates'"));
    expect(home, contains('sharedBottomNavigationBar: widget.estimatesNavigationBar'));
    expect(docs, matches(RegExp(r'widget\.sharedBottomNavigationBar\s*\?\?\s*NavigationBar\(')));
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
    expect(edits, contains('() => _api.updateDocumentWarranty('));
    expect(edits, contains('LocalJobQuarantine.guardReplay('));
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

  test('Temporary Job detail stays local in Auto mode until sync', () async {
    final job = await File('lib/screens/jobs/job_detail_screen.dart').readAsString();
    final draft = await File('lib/services/offline_document_draft_service.dart').readAsString();
    expect(job, contains("widget.jobId.startsWith('local-') && !forceOnline"));
    expect(draft, contains("'job_number': temporaryJobNumber"));
    expect(draft, contains("'provisional_job_id':provisionalJobId"));
  });

  test('Payment method cache survives empty online refresh', () async {
    final screen = await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    final shell = await File('lib/screens/shell_screen.dart').readAsString();
    expect(screen, contains('if (methods.isEmpty && cached.isNotEmpty) return cached;'));
    expect(screen, contains('if (methods.isNotEmpty) {'));
    expect(shell, contains('if (methods.isNotEmpty) {'));
    expect(screen, contains('_offlinePayments.recordReceivedPayment('));
    expect(screen, contains('remainingBeforePaymentCents: (remaining * 100).round()'));
  });

  test('Offline payment ledger keeps an idempotent operation per payment', () async {
    final ledger = await File('lib/services/offline_invoice_payment_ledger.dart').readAsString();
    expect(ledger, contains("'operation_id': operationId"));
    expect(ledger, contains('addPendingInvoicePaymentOnce('));
    expect(ledger, contains('serverAcknowledgesPayment(detail, paymentId)'));
    expect(ledger, contains('if (invoiceId.startsWith(\'local-\')) continue;'));
    expect(ledger, contains("DELETE FROM sync_outbox WHERE id=?"));
  });

  test('Offline warranty editor fits above system navigation and keyboard', () async {
    final source = await File('lib/screens/jobs/invoice_warranty_panel.dart').readAsString();
    expect(source, contains('isScrollControlled: true'));
    expect(source, contains('MediaQuery.viewInsetsOf(sheetContext).bottom + 18'));
    expect(source, contains("allowCreate: false"));
    expect(source, contains("tr('saveWarrantyInformation')"));
  });

}

