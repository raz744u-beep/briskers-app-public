// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'diagnostics_service.dart';
import 'document_pdf_service.dart';
import 'local_document_detail_cache.dart';
import 'local_financial_cache.dart';
import 'offline_customer_vehicle_admin_service.dart';
import 'offline_document_draft_service.dart';
import 'offline_estimate_invoice_service.dart';
import 'offline_financial_write_service.dart';
import 'offline_job_admin_service.dart';
import 'weather_service.dart';
import 'historical_photo_matcher.dart';
import '../screens/customers/customer_quick_actions.dart';
import '../screens/jobs/invoice_note_draft_rules.dart';

class FunctionalDiagnosticsReport {
  const FunctionalDiagnosticsReport({
    required this.startedAt,
    required this.finishedAt,
    required this.checks,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final List<DiagnosticCheck> checks;

  int get passed => checks
      .where((check) => check.level == BriskersDiagnosticLevel.pass)
      .length;
  int get warnings => checks
      .where((check) => check.level == BriskersDiagnosticLevel.warning)
      .length;
  int get failed => checks
      .where((check) => check.level == BriskersDiagnosticLevel.fail)
      .length;

  String toText() {
    final buffer = StringBuffer()
      ..writeln('Briskers Functional Diagnostics')
      ..writeln('Mode: Isolated sandbox')
      ..writeln('Started: ' + startedAt.toLocal().toIso8601String())
      ..writeln('Finished: ' + finishedAt.toLocal().toIso8601String())
      ..writeln('Result: $passed passed, $warnings warnings, $failed failed')
      ..writeln();

    for (final check in checks) {
      final marker = switch (check.level) {
        BriskersDiagnosticLevel.pass => 'PASS',
        BriskersDiagnosticLevel.warning => 'WARN',
        BriskersDiagnosticLevel.fail => 'FAIL',
      };
      buffer.writeln('[' + marker + '] ' + check.id + ' ' + check.title);
      buffer.writeln('  ' + check.summary);
      for (final detail in check.details) {
        buffer.writeln('  - ' + detail);
      }
    }
    return buffer.toString();
  }
}

class BriskersFunctionalDiagnosticsService {
  const BriskersFunctionalDiagnosticsService();

  Future<FunctionalDiagnosticsReport> run() async {
    final startedAt = DateTime.now().toUtc();
    final checks = <DiagnosticCheck>[];

    await _scenario(
      checks,
      id: 'FUNC-001',
      title: 'Offline estimate create/edit',
      success: 'Estimate draft, line math, memo, local document and outbox passed.',
      action: _checkEstimateDraft,
    );
    await _scenario(
      checks,
      id: 'FUNC-002',
      title: 'Estimate → existing invoice',
      success: 'Same-job invoice matching and one-time local merge passed.',
      action: _checkEstimateMerge,
    );
    await _scenario(
      checks,
      id: 'FUNC-003',
      title: 'Customer / vehicle offline writes',
      success: 'Customer profile, problem flag and vehicle queueing passed.',
      action: _checkCustomerVehicle,
    );
    await _scenario(
      checks,
      id: 'FUNC-004',
      title: 'Job admin offline writes',
      success: 'Job edit, status and assignment merged into one pending change.',
      action: _checkJobAdmin,
    );
    await _scenario(
      checks,
      id: 'FUNC-005',
      title: 'Expense create/edit offline',
      success: 'First local expense creation and edit stayed queued correctly.',
      action: _checkExpense,
    );
    await _scenario(
      checks,
      id: 'FUNC-006',
      title: 'Home weather parsing/cache',
      success: 'Shop geocoding, condition parsing and offline weather cache passed.',
      action: _checkWeather,
    );
    await _scenario(
      checks,
      id: 'FUNC-007',
      title: 'Historical photo job matching',
      success: 'Exact MobileBiz job-number matching rejects ambiguous/unrelated files.',
      action: _checkHistoricalPhotoMatching,
    );

    await _scenario(
      checks,
      id: 'FUNC-008',
      title: 'Customer quick-action wiring and role permissions',
      success: 'All six customer shortcuts have unique destinations; owner and secretary routes are enabled and mechanic actions are hidden.',
      action: _checkCustomerQuickActions,
    );

    await _scenario(
      checks,
      id: 'FUNC-009',
      title: 'Offline blank invoice draft and unique sync identity',
      success: 'Invoice, linked pending Job, first visit, items and notes saved locally with one retry-safe sync identity.',
      action: _checkOfflineInvoiceDraft,
    );

    await _scenario(
      checks,
      id: 'FUNC-010',
      title: 'Invoice note actions and standard note insertion',
      success: 'Empty text cannot be saved as a template; clearing saved notes is explicit; adding a template keeps unsaved text and avoids duplicate paragraphs.',
      action: _checkInvoiceNoteActions,
    );

    await _scenario(
      checks,
      id: 'FUNC-011',
      title: 'Invoice PDF payment methods and remaining balance',
      success: 'Individual finalized/pending methods, fallback and invoice balances reconcile; no payment is counted twice.',
      action: _checkInvoicePdfPayments,
    );

    return FunctionalDiagnosticsReport(
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      checks: checks,
    );
  }

  Future<void> _scenario(
    List<DiagnosticCheck> checks, {
    required String id,
    required String title,
    required String success,
    required Future<void> Function(
      BriskersLocalDatabase database,
      String businessId,
    ) action,
  }) async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final businessId =
        '__briskers_diag_${id}_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await action(database, businessId);
      checks.add(
        DiagnosticCheck(
          id: id,
          category: 'Functional sandbox',
          title: title,
          level: BriskersDiagnosticLevel.pass,
          summary: success,
          details: const [
            'Disposable in-memory database used.',
            'No production shop records or network calls used.',
          ],
        ),
      );
    } catch (error) {
      checks.add(
        DiagnosticCheck(
          id: id,
          category: 'Functional sandbox',
          title: title,
          level: BriskersDiagnosticLevel.fail,
          summary: 'Sandbox workflow failed.',
          details: [error.toString()],
        ),
      );
    } finally {
      await _cleanupPreferences(businessId);
      await database.close();
    }
  }

  Future<void> _checkInvoicePdfPayments(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    final detail = <String, dynamic>{
      'total_amount': 500,
      'paid_amount': 200,
      'pending_payment': 100,
      'payments': [
        {
          'amount': 120,
          'state': 'posted',
          'payment_method_name': 'Cash',
        },
        {
          'amount': 80,
          'state': 'posted',
          'payment_method_name': 'Check',
        },
        {
          'amount': 100,
          'state': 'pending',
          'payment_method_name': 'Credit card',
        },
      ],
    };
    final lines = DocumentPdfService.invoicePaymentLines(detail);
    final summary = DocumentPdfService.invoicePaymentAmounts(detail);
    _require(
      lines.length == 3 &&
          lines[0]['label'] == 'Payment - Cash' &&
          lines[1]['label'] == 'Payment - Check' &&
          lines[2]['label'] == 'Payment - Credit card',
      'The PDF did not retain the individual methods and pending state.',
    );
    _require(
      _near(summary['remaining']!, 200) &&
          _near(
            lines.fold<num>(
              0,
              (sum, row) => sum + (row['amount'] as num),
            ),
            summary['paid']! + summary['pending']!,
          ),
      'The invoice PDF payment breakdown double counted or lost money.',
    );

    // An incomplete local/historical payload must not invent method names
    // or duplicate just the available payment records.
    final partialCache = Map<String, dynamic>.from(detail)
      ..['payments'] = [
        {
          'amount': 120,
          'state': 'posted',
          'payment_method_name': 'Cash',
        },
      ];
    final safe = DocumentPdfService.invoicePaymentLines(partialCache);
    _require(
      safe.length == 2 &&
          safe.first['amount'] == 200 &&
          safe.last['amount'] == 100 &&
          safe.first['label'] == 'Payment - Method not recorded' &&
          safe.last['pending'] == true,
      'An incomplete offline payment list produced an incorrect PDF total.',
    );
  }

  Future<void> _checkInvoiceNoteActions(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    _require(
      invoiceNoteDraftAction('', null) == InvoiceNoteDraftAction.none &&
          invoiceNoteDraftAction('  ', '') == InvoiceNoteDraftAction.none,
      'A blank invoice must not offer Save or Clear.',
    );
    _require(
      invoiceNoteDraftAction('Updated note', 'Prior note') ==
          InvoiceNoteDraftAction.save,
      'An edited invoice note must offer Save.',
    );
    _require(
      invoiceNoteDraftAction('', 'Saved note') ==
          InvoiceNoteDraftAction.clear,
      'Clearing a saved note must request confirmation.',
    );
    const manual = 'Typed but not yet saved';
    const template = 'Warranty: 12 months / 12000 miles';
    final merged = mergeStandardNoteIntoDraft(manual, template);
    _require(
      merged == '$manual\n\n$template',
      'Adding a standard note discarded the unsaved manual text.',
    );
    _require(
      mergeStandardNoteIntoDraft(merged, template) == merged,
      'Adding a standard note duplicated an existing paragraph.',
    );
    _require(
      mergeStandardNoteIntoDraft('', template) == template,
      'Creating and adding a first standard note was ignored.',
    );
    _require(
      !canSaveStandardNoteText('', 'body') &&
          !canSaveStandardNoteText('name', '   ') &&
          canSaveStandardNoteText('Standard Warranty', template),
      'Empty template names/text must be blocked.',
    );
  }

  Future<void> _checkCustomerQuickActions(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    final expected = <CustomerQuickAction, String>{
      CustomerQuickAction.appointment: 'appointment_create',
      CustomerQuickAction.job: 'job_create',
      CustomerQuickAction.estimate: 'estimate_create',
      CustomerQuickAction.invoice: 'blank_invoice_create',
      CustomerQuickAction.vehicle: 'vehicle_create',
      CustomerQuickAction.note: 'customer_note_composer',
    };
    if (customerQuickActions.length != expected.length ||
        customerQuickActions.toSet().length != expected.length) {
      throw StateError('Customer action inventory is incomplete or duplicated.');
    }
    final destinations = <String>{};
    for (final action in customerQuickActions) {
      final destination = customerQuickActionDestination(action);
      if (destination != expected[action] ||
          !destinations.add(destination) ||
          customerQuickActionLabel(action).trim().isEmpty) {
        throw StateError('Customer action ${action.name} has no verified destination.');
      }
    }
    if (!canManageCustomerActions('owner') ||
        !canManageCustomerActions('office') ||
        !canManageCustomerActions('manager') ||
        canManageCustomerActions('mechanic') ||
        canManageCustomerActions('porter')) {
      throw StateError('Customer quick-action role visibility is incorrect.');
    }
    // No production actions are executed: widget regression tests verify
    // every sheet tap returns its matching action, and the typed exhaustive
    // screen dispatcher must handle each value.
  }

  Future<void> _checkOfflineInvoiceDraft(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    final cache = const LocalDocumentDetailCache();
    final drafts = OfflineDocumentDraftService(
      database: database,
      cache: cache,
    );
    final id = await drafts.createQuickInvoice(
      businessId,
      customerId: 'diagnostic-customer',
      customerName: 'Sandbox Customer',
    );
    _require(
      id.startsWith('local-invoice-') && drafts.isLocalDraftId(id),
      'Offline invoice temporary ID missing.',
    );
    await drafts.addLine(
      businessId,
      id,
      name: 'Diagnostic water pump',
      quantity: 1,
      unitPrice: 100,
      taxRate: 0.0975,
      lineKind: 'item',
    );
    await drafts.saveMemo(businessId, id, 'Sandbox invoice note');
    final snapshot = await cache.load(businessId, id);
    _require(snapshot != null, 'Offline invoice detail not cached.');
    final localJobId = snapshot!['job_id']?.toString() ?? '';
    _require(
      localJobId.startsWith('local-job-') &&
          localJobId == id.replaceFirst('local-invoice-', 'local-job-'),
      'The offline Quick Invoice has no deterministic linked Job.',
    );
    final linked = await database.customSelect(
      '''
      SELECT j.id, j.sync_state, d.job_id,
             (SELECT COUNT(*) FROM local_job_visits v
              WHERE v.business_id = j.business_id AND v.job_id = j.id) AS visits
      FROM local_documents d
      JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
      WHERE d.business_id = ? AND d.id = ?
      ''',
      variables: [Variable<String>(businessId), Variable<String>(id)],
    ).get();
    _require(
      linked.length == 1 &&
          linked.single.read<String>('id') == localJobId &&
          linked.single.read<String>('sync_state') == 'pending' &&
          linked.single.read<int>('visits') == 1,
      'Offline invoice, pending Job and initial visit were not created atomically.',
    );
    _require(snapshot!['kind'] == 'invoice', 'Invoice kind was lost.');
    _require(
      (snapshot['total_amount'] as num).toDouble() > 109,
      'Offline invoice math was not saved.',
    );
    _require(
      snapshot['memo'] == 'Sandbox invoice note',
      'Offline invoice memo was lost.',
    );
    _require(
      snapshot['document_number'] == null,
      'Temporary invoice was assigned a false final number.',
    );
    final outbox = await database.customSelect(
      'SELECT operation, payload_json FROM sync_outbox '
      'WHERE business_id = ? AND entity_id = ?',
      variables: [Variable<String>(businessId), Variable<String>(id)],
    ).get();
    _require(
      outbox.length == 1 &&
          outbox.single.read<String>('operation') == 'create_quick_invoice',
      'Offline invoice did not queue one durable create operation.',
    );
    final payload = jsonDecode(
      outbox.single.read<String>('payload_json'),
    ) as Map<String, dynamic>;
    final operationId = payload['operation_id']?.toString() ?? '';
    _require(
      operationId.length == 36 && operationId.split('-').length == 5 &&
          payload['provisional_job_id'] == localJobId,
      'Offline operation ID or provisional Job mapping is missing for safe retry.',
    );
  }

  Future<void> _cleanupPreferences(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'briskers_document_detail_${businessId}_';
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  bool _near(num value, num expected) =>
      (value.toDouble() - expected.toDouble()).abs() < 0.001;

  Future<void> _seedCustomerVehicleJob(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    await database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, sync_state
      ) VALUES ('customer-1', ?, 'Richard Goff', 'synced')
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_vehicles (
        id, business_id, year, make, model, sync_state
      ) VALUES ('vehicle-1', ?, 2012, 'Hyundai', 'Equus', 'synced')
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_customer_vehicles (
        business_id, customer_id, vehicle_id, is_primary
      ) VALUES (?, 'customer-1', 'vehicle-1', 1)
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_jobs (
        id, business_id, access_scope, job_number, title, requested_work,
        status, status_name, customer_id, customer_name,
        vehicle_id, vehicle_label, planned_hours, is_unassigned, sync_state
      ) VALUES (
        'job-1', ?, 'all', 'J-5', 'Oil leak', 'Oil leak',
        'in_progress', 'In progress', 'customer-1', 'Richard Goff',
        'vehicle-1', '2012 Hyundai Equus', 1.0, 1, 'synced'
      )
      ''',
      [businessId],
    );
  }

  Future<void> _checkEstimateDraft(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    await _seedCustomerVehicleJob(database, businessId);
    const cache = LocalDocumentDetailCache();
    final service = OfflineDocumentDraftService(
      database: database,
      cache: cache,
    );

    final estimateId = await service.createEstimate(businessId, 'job-1');
    _require(
      estimateId.startsWith('local-estimate-'),
      'Local estimate ID was not generated.',
    );
    await service.addLine(
      businessId,
      estimateId,
      name: 'Transmission Fluid',
      quantity: 2,
      unitPrice: 50,
      taxRate: 0.10,
      lineKind: 'item',
    );
    await service.saveMemo(
      businessId,
      estimateId,
      'Offline diagnostic estimate',
    );

    final detail = await cache.load(businessId, estimateId);
    _require(detail != null, 'Estimate detail was not cached.');
    _require(
      _near(detail!['net_amount'] as num, 100) &&
          _near(detail['tax_amount'] as num, 10) &&
          _near(detail['total_amount'] as num, 110),
      'Estimate math did not equal 100 + 10 tax = 110.',
    );
    _require(
      detail['memo'] == 'Offline diagnostic estimate',
      'Estimate memo was not retained.',
    );

    final queued = await database.customSelect(
      '''
      SELECT entity_type, operation, state
      FROM sync_outbox
      WHERE business_id = ? AND entity_id = ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(estimateId),
      ],
    ).getSingle();
    _require(
      queued.read<String>('entity_type') == 'document_draft_create' &&
          queued.read<String>('operation') == 'create_estimate' &&
          queued.read<String>('state') == 'pending',
      'Estimate outbox entry is incorrect.',
    );

    final document = await database.customSelect(
      '''
      SELECT total, sync_state
      FROM local_documents
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(estimateId),
      ],
    ).getSingle();
    _require(
      _near(document.read<double>('total'), 110) &&
          document.read<String>('sync_state') == 'pending',
      'Local estimate document did not retain its total/pending state.',
    );
  }

  Future<void> _checkEstimateMerge(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    await _seedCustomerVehicleJob(database, businessId);
    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, job_id, customer_id, kind, status,
        display_status_code, converted, total, sync_state
      ) VALUES (
        'estimate-1', ?, 'job-1', 'customer-1',
        'estimate', 'draft', 'draft', 0, 110, 'synced'
      )
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, job_id, customer_id, kind, document_number,
        status, display_status_code, converted, total, sync_state
      ) VALUES (
        'invoice-1', ?, 'job-1', 'customer-1',
        'invoice', '4', 'issued', 'open', 0, 220, 'synced'
      )
      ''',
      [businessId],
    );

    const cache = LocalDocumentDetailCache();
    await cache.save(businessId, 'estimate-1', {
      'id': 'estimate-1',
      'kind': 'estimate',
      'status': 'draft',
      'customer_id': 'customer-1',
      'customer_name': 'Richard Goff',
      'job_id': 'job-1',
      'job_number': 'J-5',
      'job_title': 'Oil leak',
      'vehicle_id': null,
      'vehicle': '2012 Hyundai Equus',
      'net_amount': 100,
      'tax_amount': 10,
      'total_amount': 110,
      'converted': false,
      'lines': [
        {
          'id': 'estimate-line-1',
          'name': 'Transmission Fluid',
          'quantity': 2,
          'unit_price': 50,
          'net_amount': 100,
          'tax_amount': 10,
          'position': 1,
        },
      ],
    });
    await cache.save(businessId, 'invoice-1', {
      'id': 'invoice-1',
      'kind': 'invoice',
      'document_number': '4',
      'status': 'issued',
      'customer_id': 'customer-1',
      'customer_name': 'Richard Goff',
      'job_id': 'job-1',
      'job_number': 'J-5',
      'job_title': 'Oil leak',
      'vehicle_id': 'vehicle-1',
      'vehicle': '2012 Hyundai Equus',
      'net_amount': 200,
      'tax_amount': 20,
      'total_amount': 220,
      'lines': [
        {
          'id': 'invoice-line-1',
          'name': 'Existing work',
          'net_amount': 200,
          'tax_amount': 20,
          'position': 1,
        },
      ],
    });

    final service = OfflineEstimateInvoiceService(
      database: database,
      cache: cache,
    );
    final estimate = await cache.load(businessId, 'estimate-1');
    _require(estimate != null, 'Sandbox estimate cache is missing.');
    final eligible = await service.eligibleLocalInvoices(
      businessId,
      estimate!,
    );
    _require(eligible.length == 1, 'Expected one eligible local invoice.');
    _require(
      eligible.single['same_job'] == true &&
          eligible.single['same_vehicle'] == true &&
          eligible.single['customer_name'] == 'Richard Goff',
      'Invoice eligibility context is incorrect.',
    );

    await service.mergeLocal(
      businessId,
      estimateId: 'estimate-1',
      invoiceId: 'invoice-1',
    );

    final mergedEstimate = await cache.load(businessId, 'estimate-1');
    final mergedInvoice = await cache.load(businessId, 'invoice-1');
    _require(
      mergedEstimate?['converted'] == true,
      'Estimate was not marked converted.',
    );
    _require(
      mergedInvoice != null &&
          _near(mergedInvoice['total_amount'] as num, 330) &&
          List<dynamic>.from(mergedInvoice['lines'] as List).length == 2,
      'Invoice merge did not produce total 330 with two lines.',
    );

    final outbox = await database.customSelect(
      '''
      SELECT entity_type, state
      FROM sync_outbox
      WHERE business_id = ?
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    _require(
      outbox.length == 1 &&
          outbox.single.read<String>('entity_type') ==
              'estimate_add_to_invoice' &&
          outbox.single.read<String>('state') == 'pending',
      'Estimate merge created an incorrect number/type of pending changes.',
    );
  }

  Future<void> _checkCustomerVehicle(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    await _seedCustomerVehicleJob(database, businessId);
    final service = OfflineCustomerVehicleAdminService(database: database);

    await service.queueCustomerProfile(
      businessId,
      'customer-1',
      name: 'Richard Goff Updated',
      phone: '5045551212',
      email: 'richard@example.com',
      billingAddress: const {'city': 'Gretna'},
    );
    await service.queueProblemFlag(
      businessId,
      'customer-1',
      flagged: true,
      note: 'Diagnostic flag',
    );
    final vehicleId = await service.queueVehicle(
      businessId,
      'customer-1',
      make: 'BMW',
      model: 'X5',
      year: 2020,
    );

    _require(
      vehicleId.startsWith('local-vehicle-'),
      'Local vehicle ID was not generated.',
    );

    final customer = await database.customSelect(
      '''
      SELECT display_name, problem_flag, sync_state
      FROM local_customers
      WHERE business_id = ? AND id = 'customer-1'
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    _require(
      customer.read<String>('display_name') == 'Richard Goff Updated' &&
          customer.read<int>('problem_flag') == 1 &&
          customer.read<String>('sync_state') == 'pending',
      'Customer offline update was not retained.',
    );

    final vehicle = await database.customSelect(
      '''
      SELECT make, model, sync_state
      FROM local_vehicles
      WHERE business_id = ? AND id LIKE 'local-vehicle-%'
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    _require(
      vehicle.read<String>('make') == 'BMW' &&
          vehicle.read<String>('model') == 'X5' &&
          vehicle.read<String>('sync_state') == 'pending',
      'Vehicle offline create was not retained.',
    );

    final outbox = await database.customSelect(
      '''
      SELECT entity_type
      FROM sync_outbox
      WHERE business_id = ?
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    final types =
        outbox.map((row) => row.read<String>('entity_type')).toSet();
    _require(
      types.containsAll({
        'customer_profile',
        'customer_flag',
        'vehicle_create',
      }),
      'Customer/vehicle outbox operations are incomplete.',
    );
  }

  Future<void> _checkJobAdmin(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    await _seedCustomerVehicleJob(database, businessId);
    final service = OfflineJobAdminService(database: database);

    await service.queueCore(
      businessId,
      'job-1',
      title: 'Transmission service',
      plannedHours: 2.5,
    );
    await service.queueStatus(
      businessId,
      'job-1',
      code: 'waiting_parts',
      name: 'Waiting parts',
      colorHex: '#E58A00',
    );
    await service.queueAssignment(
      businessId,
      'job-1',
      employeeId: 'employee-1',
      employeeName: 'Mechanic One',
      position: 'Mechanic',
    );

    final job = await database.customSelect(
      '''
      SELECT title, planned_hours, status, assigned_employee_id,
             is_unassigned, sync_state
      FROM local_jobs
      WHERE business_id = ? AND id = 'job-1'
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    _require(
      job.read<String>('title') == 'Transmission service' &&
          _near(job.read<double>('planned_hours'), 2.5) &&
          job.read<String>('status') == 'waiting_parts' &&
          job.read<String>('assigned_employee_id') == 'employee-1' &&
          job.read<int>('is_unassigned') == 0 &&
          job.read<String>('sync_state') == 'pending',
      'Job offline changes were not retained.',
    );

    final assignment = await database.customSelect(
      '''
      SELECT employee_id, employee_name
      FROM local_job_assignments
      WHERE business_id = ? AND job_id = 'job-1'
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    _require(
      assignment.read<String>('employee_id') == 'employee-1' &&
          assignment.read<String>('employee_name') == 'Mechanic One',
      'Offline assignment row is incorrect.',
    );

    final outbox = await database.customSelect(
      '''
      SELECT payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'job_admin'
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    _require(outbox.length == 1, 'Job admin should produce one merged outbox row.');
    final payload = Map<String, dynamic>.from(
      jsonDecode(outbox.single.read<String>('payload_json')) as Map,
    );
    _require(
      payload['core_changed'] == true &&
          payload['status_changed'] == true &&
          payload['assignment_changed'] == true,
      'Job admin pending payload is missing a change group.',
    );
  }

  Future<void> _checkHistoricalPhotoMatching(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    const matcher = HistoricalPhotoMatcher();
    final jobs = <Map<String, dynamic>>[
      {
        'id': 'job-6230',
        'job_number': 'MB-6230',
        'status': 'completed',
      },
      {
        'id': 'job-6087',
        'job_number': 'MB-6087',
        'status': 'completed',
      },
      {
        'id': 'job-open',
        'job_number': 'MB-7000',
        'status': 'in_progress',
      },
    ];
    final files = <Map<String, dynamic>>[
      {
        'name': 'IMG_001.jpg',
        'relative_path': 'MobileBiz/6230/IMG_001.jpg',
      },
      {
        'name': 'invoice_6087_photo.jpeg',
        'relative_path': 'photos/invoice_6087_photo.jpeg',
      },
      {
        'name': 'IMG_7000.jpg',
        'relative_path': 'MobileBiz/7000/IMG_7000.jpg',
      },
      {
        'name': 'wrong.jpg',
        'relative_path': 'MobileBiz/16230/wrong.jpg',
      },
    ];

    final matches = matcher.exactMatches(jobs, files);
    _require(matches.length == 2, 'Expected exactly two historical photo matches.');
    final ids = matches
        .map((match) => match.job['id']?.toString() ?? '')
        .toSet();
    _require(
      ids.contains('job-6230') &&
          ids.contains('job-6087') &&
          !ids.contains('job-open'),
      'Historical photo matcher assigned an incorrect job.',
    );
  }

  Future<void> _checkWeather(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    final service = BriskersWeatherService(
      forceOffline: () => false,
      businessSettingsLoader: (_) async => {
        'address': {
          'formatted': '1400 Stumpf Blvd, Gretna, LA, 70053',
        },
        'latitude': null,
        'longitude': null,
      },
      jsonLoader: (uri) async {
        if (uri.host == 'geocoding-api.open-meteo.com') {
          return {
            'results': [
              {
                'name': 'Gretna',
                'admin1': 'Louisiana',
                'latitude': 29.9146,
                'longitude': -90.0539,
              },
            ],
          };
        }
        return {
          'current': {
            'temperature_2m': 82.6,
            'apparent_temperature': 87.1,
            'precipitation': 0.02,
            'rain': 0.02,
            'weather_code': 61,
            'wind_speed_10m': 8.0,
          },
        };
      },
    );

    final snapshot = await service.load(
      businessId,
      forceRefresh: true,
    );
    _require(snapshot != null, 'Weather snapshot was not created.');
    _require(
      snapshot!.condition == 'Rain' &&
          snapshot.iconKey == 'rain' &&
          snapshot.message == 'Rain now' &&
          _near(snapshot.temperatureF, 82.6),
      'Weather condition parsing is incorrect.',
    );

    final cached = await service.loadCached(businessId);
    _require(
      cached != null &&
          cached.condition == 'Rain' &&
          _near(cached.temperatureF, 82.6),
      'Weather cache did not retain the sandbox snapshot.',
    );
  }

  Future<void> _checkExpense(
    BriskersLocalDatabase database,
    String businessId,
  ) async {
    final cache = LocalFinancialCache(database: database);
    final service = OfflineFinancialWriteService(
      database: database,
      cache: cache,
    );

    final created = await service.createLocalTransaction(
      businessId,
      direction: 'expense',
      accountId: 'account-1',
      accountName: 'Checking',
      categoryId: 'category-1',
      categoryName: 'Supplies',
      amount: 100,
      date: DateTime(2026, 10, 6),
      counterpartyName: 'Parts Vendor',
      remarks: 'Offline diagnostic expense',
      receipts: const [],
    );
    final id = created['id']?.toString() ?? '';
    _require(
      id.startsWith('local-transaction-'),
      'Local expense ID was not generated.',
    );

    final updated = await service.updateLocalTransaction(
      businessId,
      id,
      direction: 'expense',
      accountId: 'account-1',
      accountName: 'Checking',
      categoryId: 'category-1',
      categoryName: 'Supplies',
      amount: 125,
      date: DateTime(2026, 10, 6),
      counterpartyName: 'Parts Vendor',
      remarks: 'Updated offline',
    );
    _require(
      _near(updated['amount'] as num, 125),
      'Updated local expense amount is not 125.',
    );

    final rows = await cache.loadTransactions(businessId);
    _require(
      rows.length == 1 && _near(rows.single['amount'] as num, 125),
      'Local expense summary did not retain the edit.',
    );

    final outbox = await database.customSelect(
      '''
      SELECT entity_type, payload_json
      FROM sync_outbox
      WHERE business_id = ?
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    _require(
      outbox.length == 1 &&
          outbox.single.read<String>('entity_type') == 'financial_create' &&
          outbox.single.read<String>('payload_json').contains('"amount":125'),
      'Expense edit did not update the original pending create.',
    );
  }
}
