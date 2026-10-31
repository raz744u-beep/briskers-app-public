import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_i18n.dart';
import '../../core/connection_mode.dart';
import '../../local/local_database_provider.dart';
import '../../services/appointment_sync_service.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/document_index_sync_service.dart';
import '../../services/linked_expense_sync_service.dart';
import '../../services/job_sync_service.dart';
import '../../services/local_sync_status_repository.dart';
import '../../services/import_cache_repair_service.dart';
import '../../services/kiosk_registration_service.dart';
import '../../services/offline_preinspection_service.dart';
import '../../services/offline_job_admin_service.dart';
import '../../services/offline_customer_vehicle_admin_service.dart';
import '../../services/offline_customer_detail_write_service.dart';
import '../../services/offline_financial_write_service.dart';
import '../../services/offline_document_draft_service.dart';
import '../../services/local_document_detail_cache.dart';
import '../../services/offline_document_edit_service.dart';
import '../../services/local_tax_settings_cache.dart';
import '../../services/local_invoice_status_styles_cache.dart';
import '../../services/offline_estimate_invoice_service.dart';
import '../../services/offline_invoice_mileage_service.dart';
import '../../services/offline_invoice_payment_ledger.dart';
import '../../services/offline_work_findings_service.dart';
import '../../services/offline_attachment_mirror_service.dart';

class LocalSyncStatusScreen extends StatefulWidget {
  const LocalSyncStatusScreen({
    super.key,
    required this.businessId,
    this.isOwner = false,
  });

  final String businessId;
  final bool isOwner;

  @override
  State<LocalSyncStatusScreen> createState() =>
      _LocalSyncStatusScreenState();
}

class _LocalSyncStatusScreenState extends State<LocalSyncStatusScreen> {
  final JobSyncService _jobs = JobSyncService();
  final ImportCacheRepairService _importRepair = ImportCacheRepairService();
  final AppointmentSyncService _appointments = AppointmentSyncService();
  final CustomerVehicleSyncService _customers = CustomerVehicleSyncService();
  final CatalogSyncService _catalog = CatalogSyncService();
  final DocumentIndexSyncService _documents = DocumentIndexSyncService();
  final LinkedExpenseSyncService _linkedExpenses = LinkedExpenseSyncService();
  final OfflinePreInspectionService _preInspections =
      OfflinePreInspectionService();
  final OfflineWorkFindingsService _workFindings =
      OfflineWorkFindingsService();
  final KioskRegistrationService _kiosk = KioskRegistrationService();
  final OfflineJobAdminService _jobAdmin = OfflineJobAdminService();
  final OfflineCustomerVehicleAdminService _customerVehicleAdmin =
      OfflineCustomerVehicleAdminService();
  final OfflineCustomerDetailWriteService _customerDetail =
      OfflineCustomerDetailWriteService();
  final OfflineFinancialWriteService _financial = OfflineFinancialWriteService();
  final OfflineDocumentDraftService _documentDrafts =
      OfflineDocumentDraftService();
  final OfflineDocumentEditService _documentEdits =
      OfflineDocumentEditService();
  final LocalTaxSettingsCache _taxSettings =
      LocalTaxSettingsCache();
  final LocalInvoiceStatusStylesCache _invoiceStatusStyles =
      LocalInvoiceStatusStylesCache();
  final OfflineEstimateInvoiceService _estimateInvoice =
      OfflineEstimateInvoiceService();
  final OfflineInvoiceMileageService _mileage = OfflineInvoiceMileageService();
  final OfflineInvoicePaymentLedger _payments = OfflineInvoicePaymentLedger();

  bool _loading = true;
  bool _syncing = false;
  bool _targetedRecovery = false;
  static const int _syncStepCount = 22;
  int _syncStep = 0;
  String? _syncStage;
  String? _error;
  String? _syncMessage;

  Map<String, int> _counts = const {};
  List<Map<String, dynamic>> _syncStates = const [];
  List<Map<String, dynamic>> _outbox = const [];
  List<Map<String, dynamic>> _pendingDetails = const [];
  final OfflineAttachmentMirrorService _mediaMirror =
      OfflineAttachmentMirrorService();
  late Future<OfflineAttachmentInventory> _mediaInventory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int> _count(String table, {String? where}) async {
    final rows = await localDatabase.customSelect(
      'SELECT COUNT(*) AS count FROM $table '
      'WHERE business_id = ?${where == null ? '' : ' AND $where'}',
      variables: [Variable<String>(widget.businessId)],
    ).get();
    return rows.isEmpty ? 0 : rows.first.read<int>('count');
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        // This read-only disk check is independent from database sync.
        _mediaInventory = _mediaMirror.inventory(widget.businessId);
      });
    }

    try {
      // Independent read-only counts do not need fourteen sequential round
      // trips through SQLite before the diagnostics screen can paint.
      final names = <String>[
        'customers', 'vehicles', 'appointments', 'jobs', 'catalog',
        'documents', 'findings', 'inspections', 'photoPending',
        'photoUploaded', 'photoFailed', 'pending', 'conflicts',
      ];
      final values = await Future.wait<int>([
        _count('local_customers'),
        _count('local_vehicles'),
        _count('local_appointments'),
        _count('local_jobs'),
        _count('local_catalog_items'),
        _count('local_documents'),
        _count('local_findings'),
        _count('local_pre_inspections'),
        _count('local_expense_iq_photos',
            where: "state IN ('pending','uploading')"),
        _count('local_expense_iq_photos', where: "state = 'uploaded'"),
        _count('local_expense_iq_photos',
            where: "state IN ('failed','missing')"),
        _count('sync_outbox', where: "state = 'pending'"),
        _count('sync_outbox', where: "state = 'conflict'"),
      ]);
      final counts = <String, int>{
        for (var i = 0; i < names.length; i++) names[i]: values[i],
      };

      final stateRows = await localDatabase.customSelect(
        '''
        SELECT scope, last_server_cursor, last_pull_at, last_push_at,
               last_error, bootstrapped
        FROM local_sync_states
        WHERE business_id = ?
        ORDER BY scope
        ''',
        variables: [Variable<String>(widget.businessId)],
      ).get();

      final outboxRows = await localDatabase.customSelect(
        '''
        SELECT entity_type, state, COUNT(*) AS count,
               MAX(last_error) AS last_error
        FROM sync_outbox
        WHERE business_id = ?
        GROUP BY entity_type, state
        ORDER BY state, entity_type
        ''',
        variables: [Variable<String>(widget.businessId)],
      ).get();

      // Paint the local counts and sync history before performing expensive
      // per-outbox-record relationship checks (which can involve 120+ rows).
      // Those checks are diagnostic only and must not hold the entire screen
      // on a spinner.
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _syncStates = stateRows.map((row) => <String, dynamic>{
          'scope': row.read<String>('scope'),
          'cursor': row.readNullable<int>('last_server_cursor'),
          'last_pull_at': row.data['last_pull_at'],
          'last_push_at': row.data['last_push_at'],
          'last_error': row.readNullable<String>('last_error'),
          'bootstrapped': row.read<int>('bootstrapped') == 1,
        }).toList();
        _outbox = outboxRows.map((row) => <String, dynamic>{
          'entity_type': row.read<String>('entity_type'),
          'state': row.read<String>('state'),
          'count': row.read<int>('count'),
          'last_error': row.readNullable<String>('last_error'),
        }).toList();
        _loading = false;
      });

      // Read-only owner-facing inspection: never mutate or retry a queued
      // operation from the diagnostic panel. Keep raw IDs for safe cleanup.
      final detailsRows = await localDatabase.customSelect(
        """SELECT id, entity_type, entity_id, state, attempt_count,
                  payload_json, last_error
           FROM sync_outbox
           WHERE business_id=? AND state IN ('pending','inflight','conflict')
           ORDER BY id""",
        variables: [Variable<String>(widget.businessId)],
      ).get();
      final pendingDetails = <Map<String, dynamic>>[];
      for (final row in detailsRows) {
        final payloadText = row.readNullable<String>('payload_json') ?? '{}';
        Map<String, dynamic> payload = {};
        try {
          payload = Map<String, dynamic>.from(jsonDecode(payloadText) as Map);
        } catch (_) {}
        // Diagnostic preflight: count locally linked records before any
        // proposed cleanup. These checks do not alter SQLite or the outbox.
        final entityId = row.read<String>('entity_id');
        final jobId = payload['job_id']?.toString() ??
            payload['provisional_job_id']?.toString() ?? entityId;
        final localDocumentLinks = await localDatabase.customSelect(
          'SELECT COUNT(*) AS n FROM local_documents '
          'WHERE business_id=? AND (id=? OR job_id=?)',
          variables: [
            Variable<String>(widget.businessId),
            Variable<String>(entityId),
            Variable<String>(jobId),
          ],
        ).getSingle();
        final localJobLinks = await localDatabase.customSelect(
          'SELECT COUNT(*) AS n FROM local_jobs '
          'WHERE business_id=? AND id=?',
          variables: [
            Variable<String>(widget.businessId),
            Variable<String>(jobId),
          ],
        ).getSingle();
        pendingDetails.add({
          'id': row.read<int>('id'),
          'type': row.read<String>('entity_type'),
          'entity': row.read<String>('entity_id'),
          'state': row.read<String>('state'),
          'attempts': row.read<int>('attempt_count'),
          'linked_documents': localDocumentLinks.read<int>('n'),
          'linked_jobs': localJobLinks.read<int>('n'),
          'customer_id': payload['customer_id']?.toString() ?? '',
          'vehicle_id': payload['vehicle_id']?.toString() ?? '',
          'job_id': payload['job_id']?.toString() ??
              payload['provisional_job_id']?.toString() ?? '',
          'kind': payload['kind']?.toString() ?? '',
          // Read-only evidence for a stalled finding_action. Neither value
          // authorizes retry or acknowledgement of the saved mutation.
          'finding_action': payload['action']?.toString() ?? '',
          'finding_mutation_attempted': payload['_mutation_attempted'] == true,
          'error': row.readNullable<String>('last_error') ?? '',
        });
      }
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _syncStates = stateRows
            .map(
              (row) => <String, dynamic>{
                'scope': row.read<String>('scope'),
                'cursor': row.readNullable<int>('last_server_cursor'),
                'last_pull_at': row.data['last_pull_at'],
                'last_push_at': row.data['last_push_at'],
                'last_error': row.readNullable<String>('last_error'),
                'bootstrapped': row.read<int>('bootstrapped') == 1,
              },
            )
            .toList();
        _pendingDetails = pendingDetails;
        _outbox = outboxRows
            .map(
              (row) => <String, dynamic>{
                'entity_type': row.read<String>('entity_type'),
                'state': row.read<String>('state'),
                'count': row.read<int>('count'),
                'last_error': row.readNullable<String>('last_error'),
              },
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  DateTime? _date(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        raw * 1000,
        isUtc: true,
      ).toLocal();
    }
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _dateLabel(Object? raw) {
    final value = _date(raw);
    if (value == null) return tr('never');
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMd(locale).add_jm().format(value);
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'jobs':
        return tr('jobs');
      case 'appointments':
        return tr('appointments');
      case 'customers_vehicles':
        return tr('customersVehicles');
      case 'catalog':
        return 'Items / Catalog';
      case 'documents':
        return 'Estimates / Invoices';
      default:
        return scope;
    }
  }

  String _operationLabel(String type) {
    switch (type) {
      case 'work_summary':
        return tr('workPerformed');
      case 'finding_create':
      case 'finding_update':
        return tr('vehicleFindings');
      case 'finding_photo':
        return tr('findingPhotos');
      case 'preinspection':
        return tr('preInspection');
      case 'preinspection_photo':
        return tr('inspectionPhotos');
      case 'appointment_checkin':
        return tr('appointmentCheckIn');
      case 'kiosk_walkin_registration':
        return tr('kioskWalkIn');
      default:
        return type.replaceAll('_', ' ');
    }
  }

  Future<void> _repairImportedData() async {
    if (_syncing) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('repairImportedData')),
        content: Text(tr('repairImportedDataHelp')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('repairImportedData')),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() {
      _syncing = true;
      _syncMessage = null;
      _error = null;
    });
    try {
      final result = await _importRepair.repair(widget.businessId);
      await _load();
      if (!mounted) return;
      setState(() {
        _syncMessage = tr('repairImportedDataDone')
            .replaceAll('{customers}', '${result.customersRemoved}')
            .replaceAll('{vehicles}', '${result.vehiclesRemoved}')
            .replaceAll('{jobs}', '${result.jobsRemoved}');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _syncMessage = tr('repairImportedDataBlocked');
      });
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  /// Cancel only the proven orphaned test Job update. This operation
  /// targets a local-only ID that cannot be used by UUID server RPCs.
  Future<void> _cancelOrphanedTestJobUpdate() async {
    if (!widget.isOwner || _syncing) return;
    const orphanId = 'local-conversion-job-5b982dcb-6cd7-4aae-8e29-0945d1000c04';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel orphaned test update?'),
        content: const Text(
          'This removes only the pending local Job update #81. '
          'It does not delete an invoice, estimate, Job, customer, '
          'or any server record. The action is blocked if anything '
          'still references the temporary Job.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm cancel'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      await localDatabase.transaction(() async {
        final rows = await localDatabase.customSelect(
          """SELECT entity_id,state FROM sync_outbox
             WHERE business_id=? AND id=81 AND entity_type='job_admin'
             LIMIT 1""",
          variables: [Variable<String>(widget.businessId)],
        ).get();
        if (rows.length != 1) {
          throw StateError('Operation #81 is not present in this shop queue. Nothing removed.');
        }
        final actualId = rows.single.read<String>('entity_id');
        final actualState = rows.single.read<String>('state');
        if (actualId != orphanId) {
          throw StateError(
            'Operation #81 record ID differs from the expected orphan '
            '(actual length ${actualId.length}, expected ${orphanId.length}). '
            'Nothing removed.',
          );
        }
        if (actualState != 'pending') {
          throw StateError(
            'Operation #81 is in state $actualState, not pending. Nothing removed.',
          );
        }
        final jobs = await localDatabase.customSelect(
          'SELECT COUNT(*) AS n FROM local_jobs WHERE business_id=? AND id=?',
          variables: [Variable<String>(widget.businessId),
            const Variable<String>(orphanId)],
        ).getSingle();
        final docs = await localDatabase.customSelect(
          'SELECT COUNT(*) AS n FROM local_documents WHERE business_id=? AND job_id=?',
          variables: [Variable<String>(widget.businessId),
            const Variable<String>(orphanId)],
        ).getSingle();
        if (jobs.read<int>('n') != 0 || docs.read<int>('n') != 0) {
          throw StateError('Local Job or documents still reference #81. Nothing removed.');
        }
        await localDatabase.customStatement(
          """DELETE FROM sync_outbox WHERE business_id=? AND id=81
             AND entity_type='job_admin' AND entity_id=? AND state='pending'""",
          [widget.businessId, orphanId],
        );
      });
      await _load();
      if (mounted) {
        setState(() => _syncMessage =
            'Orphaned test operation #81 cancelled. Other data untouched.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _removeTestEstimate78() async {
    if (!widget.isOwner || _syncing) return;
    const localId = 'local-estimate-ff67c47c-b116-437a-a8a4-2e3511695ef2';
    const customerId = '74e2a6ce-75f7-4c9e-a888-fde4bfeab2b2';
    const vehicleId = 'local-vehicle-1791733959244810';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove disposable test estimate?'),
        content: const Text(
          'Remove only offline test estimate #78 and its pending upload? '
          'All other estimates, invoices, customers, and jobs are preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove test estimate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      await localDatabase.transaction(() async {
        final queued = await localDatabase.customSelect(
          """SELECT entity_id, state, payload_json FROM sync_outbox
             WHERE business_id=? AND id=78 AND entity_type='document_draft_create'
             LIMIT 1""",
          variables: [Variable<String>(widget.businessId)],
        ).get();
        if (queued.length != 1 ||
            queued.single.read<String>('entity_id') != localId ||
            queued.single.read<String>('state') != 'pending') {
          throw StateError('The test estimate queue changed. Nothing removed.');
        }
        final payload = Map<String, dynamic>.from(
          jsonDecode(queued.single.read<String>('payload_json')) as Map);
        if (payload['kind'] != 'estimate' ||
            payload['customer_id'] != customerId ||
            payload['vehicle_id'] != vehicleId ||
            payload['job_id'] != null) {
          throw StateError('Unexpected test estimate dependencies. Nothing removed.');
        }
        final docs = await localDatabase.customSelect(
          """SELECT id,customer_id,job_id,sync_state FROM local_documents
             WHERE business_id=? AND id=? LIMIT 1""",
          variables: [Variable<String>(widget.businessId),
            const Variable<String>(localId)],
        ).get();
        if (docs.length != 1 ||
            docs.single.read<String>('customer_id') != customerId ||
            docs.single.readNullable<String>('job_id') != null ||
            docs.single.read<String>('sync_state') != 'pending') {
          throw StateError('Local estimate has changed. Nothing removed.');
        }
        final other = await localDatabase.customSelect(
          """SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id=?
             AND entity_id=? AND id<>78""",
          variables: [Variable<String>(widget.businessId),
            const Variable<String>(localId)],
        ).getSingle();
        if (other.read<int>('n') != 0) {
          throw StateError('Another pending edit references the estimate.');
        }
        await localDatabase.customStatement(
          """DELETE FROM sync_outbox WHERE business_id=? AND id=78
             AND entity_id=? AND state='pending'""",
          [widget.businessId, localId],
        );
        await localDatabase.customStatement(
          """DELETE FROM local_documents WHERE business_id=? AND id=?
             AND customer_id=? AND sync_state='pending'""",
          [widget.businessId, localId, customerId],
        );
      });
      await const LocalDocumentDetailCache().remove(widget.businessId, localId);
      await _load();
      if (mounted) {
        setState(() => _syncMessage = 'Disposable estimate #78 removed locally.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // One purpose only: recover already queued customer, vehicle, invoice and
  // recorded payment operations.  Do not refresh unrelated catalog/tax,
  // appointments or jobs when a single invoice is awaiting its number.
  // These services retain their original durable operation IDs.
  // Owner-only and read-only. No network calls, mutations, or queue ACKs.
  // Captures the exact four known Gloria outbox rows plus linked local tables.
  Future<void> _copyGloriaRecoverySnapshot() async {
    if (!widget.isOwner) return;
    try {
      const expected = <int, String>{
        252: 'customer_create',
        253: 'vehicle_create',
        254: 'document_draft_create',
        255: 'invoice_payment_received',
      };
      final operations = <Map<String, dynamic>>[];
      for (final entry in expected.entries) {
        final rows = await localDatabase.customSelect(
          'SELECT * FROM sync_outbox WHERE business_id=? AND id=? AND entity_type=?',
          variables: [
            Variable<String>(widget.businessId),
            Variable<int>(entry.key),
            Variable<String>(entry.value),
          ],
        ).get();
        if (rows.length != 1) {
          throw StateError('Expected Gloria outbox #${entry.key} (${entry.value}) was not found. No export copied.');
        }
        operations.add(Map<String, dynamic>.from(rows.single.data));
      }
      final customerId = operations[0]['entity_id'].toString();
      final vehicleId = operations[1]['entity_id'].toString();
      final invoiceId = operations[2]['entity_id'].toString();
      const knownCustomer = 'local-customer-1793301637612107';
      const knownVehicle = 'local-vehicle-1793301794872090';
      const knownInvoice = 'local-invoice-f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385';
      if (customerId != knownCustomer ||
          vehicleId != knownVehicle ||
          invoiceId != knownInvoice) {
        throw StateError('Gloria record identifiers have changed. Stop and inspect before exporting.');
      }
      Future<List<Map<String, dynamic>>> read(
        String sql, List<Variable> params,
      ) async => (await localDatabase.customSelect(sql, variables: params).get())
          .map((row) => Map<String, dynamic>.from(row.data)).toList();
      final customer = await read(
        'SELECT * FROM local_customers WHERE business_id=? AND id=?',
        [Variable<String>(widget.businessId), Variable<String>(customerId)],
      );
      final vehicle = await read(
        'SELECT * FROM local_vehicles WHERE business_id=? AND id=?',
        [Variable<String>(widget.businessId), Variable<String>(vehicleId)],
      );
      final documents = await read(
        'SELECT * FROM local_documents WHERE business_id=? AND id=?',
        [Variable<String>(widget.businessId), Variable<String>(invoiceId)],
      );
      final jobs = await read(
        'SELECT * FROM local_jobs WHERE business_id=? AND id=?',
        [Variable<String>(widget.businessId),
          const Variable<String>('local-job-f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385')],
      );
      if (customer.length != 1 || vehicle.length != 1 || documents.length != 1) {
        throw StateError('One of Gloria local source records is missing. Nothing exported.');
      }
      final evidence = <String, dynamic>{
        'format': 'briskers-gloria-recovery-readonly-v1',
        'purpose': 'Restricted private financial recovery; do not publicly share',
        'business_id': widget.businessId,
        'operations': operations,
        'local_customer': customer.single,
        'local_vehicle': vehicle.single,
        'local_document': documents.single,
        'local_invoice_detail': await const LocalDocumentDetailCache().load(widget.businessId, invoiceId),
        'local_jobs': jobs,
      };
      final snapshot = const JsonEncoder.withIndent('  ').convert(evidence);
      await Clipboard.setData(ClipboardData(text: snapshot));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gloria recovery snapshot copied (${snapshot.length} characters). Paste into a private recovery message. No records changed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gloria export stopped safely: $error')),
      );
    }
  }

  Future<int> _pendingRecoveryOperations(String type) async {
    final row = await localDatabase.customSelect(
      "SELECT COUNT(*) AS n FROM sync_outbox "
      "WHERE business_id=? AND entity_type=? "
      "AND state IN ('pending','inflight','conflict')",
      variables: [
        Variable<String>(widget.businessId),
        Variable<String>(type),
      ],
    ).getSingle();
    return row.read<int>('n');
  }

  Future<void> _recoverPendingInvoices() async {
    if (_syncing) { return; }
    if (BriskersConnectionModeController.instance.forceOffline) {
      setState(() {
        _error = 'Switch out of Force Offline before attempting recovery.';
      });
      return;
    }
    setState(() {
      _syncing = true;
      _targetedRecovery = true;
      _syncStep = 0;
      _syncStage = 'Inspecting local invoice queue';
      _syncMessage = null;
      _error = null;
    });

    String? failure;
    String? message;
    try {
      final customer = await _pendingRecoveryOperations('customer_create');
      final vehicle = await _pendingRecoveryOperations('vehicle_create');
      final invoice = await _pendingRecoveryOperations('document_draft_create');
      final payment = await _pendingRecoveryOperations('invoice_payment_received');
      if (customer + vehicle + invoice + payment == 0) {
        message = 'No pending customer, vehicle, invoice or received-payment '
            'uploads found. Confirm invoice number and payment separately.';
      } else {
        if (mounted) {
          setState(() => _syncStage = '1/3 Customer and vehicle uploads');
        }
        if (customer + vehicle > 0) {
          await _customerVehicleAdmin.flush(widget.businessId);
        }
        if (await _pendingRecoveryOperations('customer_create') > 0 ||
            await _pendingRecoveryOperations('vehicle_create') > 0) {
          throw StateError(
            'Customer or vehicle is still waiting for server confirmation. '
            'Invoice and payment uploads were not retried. '
            'Review the pending operation error.',
          );
        }
        if (mounted) { setState(() => _syncStep = 1); }

        if (mounted) { setState(() => _syncStage = '2/3 Invoice upload'); }
        if (invoice > 0) { await _documentDrafts.flush(widget.businessId); }
        if (await _pendingRecoveryOperations('document_draft_create') > 0) {
          throw StateError(
            'Invoice is still awaiting server confirmation. '
            'Payment upload was not retried. '
            'Review the invoice operation error.',
          );
        }
        if (mounted) { setState(() => _syncStep = 2); }

        if (mounted) { setState(() => _syncStage = '3/3 Recorded payment upload'); }
        if (payment > 0) { await _payments.flush(widget.businessId); }
        if (await _pendingRecoveryOperations('invoice_payment_received') > 0) {
          throw StateError(
            'The payment is still waiting for an authoritative server receipt. '
            'Do not enter it a second time.',
          );
        }
        if (mounted) { setState(() => _syncStep = 3); }
        message = 'The queued customer, vehicle, invoice and received-payment '
            'uploads have cleared. Check the invoice number and confirm the '
            'payment separately before finalizing anything.';
      }
    } catch (error) {
      failure = error.toString();
    } finally {
      // Inspection alone is read-only; refresh the queue after uploads.
      try {
        await _load();
      } catch (_) {
        // Preserve the upload error even if refreshing the UI fails.
      }
      if (mounted) {
        setState(() {
          _syncing = false;
          _targetedRecovery = false;
          _syncStage = null;
          _error = failure;
          _syncMessage = message;
        });
      }
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _targetedRecovery = false;
      _syncStep = 0;
      _syncStage = 'Preparing sync';
      _syncMessage = null;
      _error = null;
    });

    final failures = <String>[];
    final failedStages = <String>[];

    Future<void> attempt(
      String label,
      Future<void> Function() action,
    ) async {
      if (mounted) setState(() => _syncStage = label);
      try {
        await action();
      } catch (error) {
        failures.add('$label: $error');
        failedStages.add(label);
      } finally {
        if (mounted) setState(() => _syncStep += 1);
      }
    }

    // Parents must receive their server UUIDs before dependent Job and
    // document uploads. This screen is also used for manual recovery.
    await attempt(
      'Customer / vehicle changes',
      () => _customerVehicleAdmin.flush(widget.businessId),
    );
    await attempt(
      'Job changes',
      () => _jobAdmin.flush(widget.businessId),
    );
    await attempt(
      'Customer notes / findings',
      () => _customerDetail.flush(widget.businessId),
    );
    await attempt(
      'Expenses / receipts',
      () => _financial.flush(widget.businessId),
    );
    await attempt(
      'Offline estimate drafts',
      () => _documentDrafts.flush(widget.businessId),
    );
    await attempt(
      'Tax settings',
      () async {
        final settings = await _taxSettings.refresh(widget.businessId);
        final rate = num.tryParse(
              settings['sales_tax_rate']?.toString() ?? '',
            ) ??
            0;
        await _documentEdits.repairPendingCatalogTaxes(
          widget.businessId,
          rate,
        );
      },
    );
    await attempt(
      'Cached estimate / invoice edits',
      () => _documentEdits.flush(widget.businessId),
    );
    await attempt(
      'Estimate / invoice changes',
      () => _estimateInvoice.flush(widget.businessId),
    );
    // Invoice creation has to reconcile its local ID before any payment
    // or mileage write can safely target the permanent server invoice.
    await attempt(
      'Invoice mileage changes',
      () => _mileage.flush(widget.businessId),
    );
    await attempt(
      'Received invoice payments',
      () => _payments.flush(widget.businessId),
    );
    await attempt(
      'Pending payment corrections',
      () => _payments.flushPendingServerEdits(widget.businessId),
    );
    await attempt(
      tr('preInspection'),
      () => _preInspections.flush(widget.businessId),
    );
    await attempt(
      tr('workPerformed'),
      () => _workFindings.flush(widget.businessId),
    );
    await attempt(tr('kioskWalkIn'), () async {
      await _kiosk.flush(widget.businessId);
    });
    await attempt(tr('appointments'), () async {
      await _appointments.flush(widget.businessId);
      await _appointments.pull(widget.businessId);
    });
    await attempt(
      tr('jobs'),
      () => _jobs.pull(widget.businessId),
    );
    await attempt(
      tr('customersVehicles'),
      () => _customers.pull(widget.businessId),
    );
    await attempt(
      'Items / Catalog',
      () => _catalog.pull(widget.businessId),
    );
    await attempt(
      'Tax settings',
      () => _taxSettings.refresh(widget.businessId),
    );
    await attempt(
      'Estimates / Invoices',
      () => _documents.pull(widget.businessId),
    );
    await attempt(
      'Linked job / invoice expenses',
      () async { await _linkedExpenses.pull(widget.businessId); },
    );
    await attempt(
      'Invoice status styles',
      () => _invoiceStatusStyles.refresh(widget.businessId),
    );

    try {
      await LocalSyncStatusRepository.recordManualRefreshResult(
        widget.businessId, failedStages,
      );
    } catch (error) {
      // The in-memory warning remains available even if preferences fail.
      failures.add('Saving sync status: $error');
    }

    await _load();
    if (!mounted) return;

    setState(() {
      _syncing = false;
      _syncStage = null;
      _syncMessage =
          failures.isEmpty ? tr('syncCompleted') : tr('syncPartial');
      if (failures.isNotEmpty) {
        _error = failures.join('\n');
      }
    });
  }

  Widget _countTile(
    IconData icon,
    String label,
    int count, {
    Color? color,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        trailing: Text(
          '$count',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offlineReady = (_counts['customers'] ?? 0) > 0 &&
        (_counts['jobs'] ?? 0) > 0 &&
        (_counts['catalog'] ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('localDatabaseSync')),
        actions: [
          IconButton(
            tooltip: tr('refresh'),
            onPressed: _loading || _syncing ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  if (_syncing)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Synchronization in progress'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(_syncStage ?? 'Working…'),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _syncStep / (_targetedRecovery ? 3 : _syncStepCount),
                            ),
                            const SizedBox(height: 6),
                            Text('Step $_syncStep of ${_targetedRecovery ? 3 : _syncStepCount} completed'),
                          ],
                        ),
                      ),
                    ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.storage_outlined),
                      title: Text(
                        tr('localDatabaseActive'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'SQLite / Drift • ${tr('schemaVersion')} '
                        '${localDatabase.schemaVersion}',
                      ),
                      trailing: Icon(
                        offlineReady
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: offlineReady ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('cachedOnDevice'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  _countTile(
                    Icons.people_outline,
                    tr('customers'),
                    _counts['customers'] ?? 0,
                  ),
                  _countTile(
                    Icons.directions_car_outlined,
                    tr('vehicles'),
                    _counts['vehicles'] ?? 0,
                  ),
                  _countTile(
                    Icons.calendar_month_outlined,
                    tr('appointments'),
                    _counts['appointments'] ?? 0,
                  ),
                  _countTile(
                    Icons.build_outlined,
                    tr('jobs'),
                    _counts['jobs'] ?? 0,
                  ),
                  _countTile(
                    Icons.inventory_2_outlined,
                    'Items / Catalog',
                    _counts['catalog'] ?? 0,
                  ),
                  _countTile(
                    Icons.description_outlined,
                    'Estimates / Invoices',
                    _counts['documents'] ?? 0,
                  ),
                  _countTile(
                    Icons.car_repair_outlined,
                    tr('vehicleFindings'),
                    _counts['findings'] ?? 0,
                  ),
                  _countTile(
                    Icons.search,
                    tr('preInspections'),
                    _counts['inspections'] ?? 0,
                  ),
                  FutureBuilder<OfflineAttachmentInventory>(
                    future: _mediaInventory,
                    builder: (context, snapshot) {
                      final available = snapshot.data?.available;
                      final known = snapshot.data?.known;
                      final missing = snapshot.data?.missing;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Offline photo copies'),
                          subtitle: Text(
                            snapshot.hasError
                                ? 'Photo inventory unavailable — refresh to retry'
                                : known == null
                                    ? 'Checking files already saved on this device…'
                                    : '$available of $known known photos stored locally '
                                        '• $missing missing. '
                                        'Only synced photo references are counted; '
                                        'the full historical total may be higher.',
                          ),
                          trailing: snapshot.connectionState ==
                                  ConnectionState.done
                              ? Icon(snapshot.hasError
                                  ? Icons.warning_amber_outlined
                                  : missing == 0
                                      ? Icons.check_circle_outline
                                      : Icons.cloud_download_outlined)
                              : const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr('offlineQueue'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  _countTile(
                    Icons.cloud_upload_outlined,
                    tr('pendingUpload'),
                    _counts['pending'] ?? 0,
                    color: Colors.orange,
                  ),
                  _countTile(
                    Icons.warning_amber_rounded,
                    tr('syncConflicts'),
                    _counts['conflicts'] ?? 0,
                    color: Colors.red,
                  ),
                  _countTile(
                    Icons.photo_library_outlined,
                    'ExpenseIQ photos awaiting cloud sync',
                    _counts['photoPending'] ?? 0,
                    color: Colors.orange,
                  ),
                  _countTile(
                    Icons.cloud_done_outlined,
                    'ExpenseIQ photos uploaded from this phone',
                    _counts['photoUploaded'] ?? 0,
                    color: Colors.green,
                  ),
                  _countTile(
                    Icons.report_problem_outlined,
                    'ExpenseIQ photos needing attention',
                    _counts['photoFailed'] ?? 0,
                    color: Colors.red,
                  ),
                  if (_outbox.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ..._outbox.map(
                      (row) => Card(
                        child: ListTile(
                          dense: true,
                          title: Text(
                            _operationLabel(
                              row['entity_type']?.toString() ?? '',
                            ),
                          ),
                          subtitle: (row['last_error']?.toString() ?? '').isEmpty
                              ? Text(row['state']?.toString() ?? '')
                              : Text(
                                  row['last_error'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: Text(
                            '${row['count'] ?? 0}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_pendingDetails.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Pending operation details (read-only)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    ..._pendingDetails.map((operation) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText([
                          '${operation['type']} #${operation['id']} · ${operation['state']}',
                          'Record: ${operation['entity']}',
                          if ((operation['kind'] as String).isNotEmpty)
                            'Kind: ${operation['kind']}',
                          if (operation['type'] == 'finding_action')
                            'Finding action: ${operation['finding_action']} · previously attempted: ${operation['finding_mutation_attempted']}',
                          if ((operation['customer_id'] as String).isNotEmpty)
                            'Customer ID: ${operation['customer_id']}',
                          if ((operation['vehicle_id'] as String).isNotEmpty)
                            'Vehicle ID: ${operation['vehicle_id']}',
                          if ((operation['job_id'] as String).isNotEmpty)
                            'Job ID: ${operation['job_id']}',
                          'Attempts: ${operation['attempts']}',
                          'Linked local documents: ${operation['linked_documents']}',
                          'Linked local jobs: ${operation['linked_jobs']}',
                          if ((operation['error'] as String).isNotEmpty)
                            'Error: ${operation['error']}',
                        ].join('\n')),
                      ),
                    )),
                    const Text(
                      'Inspection only. No pending data is removed here.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  // Show the action on Owner's screen even when the cached
                  // eligibility summary is stale. The transactional handler
                  // still rechecks all identifiers and linked records.
                  if (widget.isOwner) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _syncing || !_pendingDetails.any((entry) =>
                        entry['id'] == 81 && entry['type'] == 'job_admin')
                          ? null : _cancelOrphanedTestJobUpdate,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Cancel orphaned test update #81'),
                    ),
                  ],
                  if (widget.isOwner &&
                      _pendingDetails.any((e) => e['id'] == 78 &&
                        e['type'] == 'document_draft_create' &&
                        e['entity'] ==
                          'local-estimate-ff67c47c-b116-437a-a8a4-2e3511695ef2')) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _syncing ? null : _removeTestEstimate78,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove disposable test estimate #78'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    tr('syncHistory'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  if (_syncStates.isEmpty)
                    Card(
                      child: ListTile(
                        title: Text(tr('notSyncedYet')),
                      ),
                    )
                  else
                    ..._syncStates.map(
                      (row) => Card(
                        child: ListTile(
                          title: Text(
                            _scopeLabel(row['scope']?.toString() ?? ''),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text([
                            "${tr('lastPull')}: ${_dateLabel(row['last_pull_at'])}",
                            "${tr('lastPush')}: ${_dateLabel(row['last_push_at'])}",
                            if ((row['last_error']?.toString() ?? '').isNotEmpty)
                              "Download failed: ${row['last_error']}",
                            if (row['bootstrapped'] != true)
                              'Download incomplete; offline list may be partial',
                          ].join('\n')),
                          trailing: Icon(
                            (row['last_error']?.toString() ?? '').isNotEmpty
                                ? Icons.error_outline
                                : row['bootstrapped'] == true
                                    ? Icons.check_circle_outline
                                    : Icons.hourglass_empty,
                            color: (row['last_error']?.toString() ?? '').isNotEmpty
                                ? Colors.red
                                : row['bootstrapped'] == true
                                    ? Colors.green
                                    : Colors.orange,
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('offlineTest'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            offlineReady
                                ? tr('offlineTestReady')
                                : tr('offlineTestNeedsCache'),
                          ),
                          const SizedBox(height: 8),
                          Text('1. ${tr('offlineStep1')}'),
                          Text('2. ${tr('offlineStep2')}'),
                          Text('3. ${tr('offlineStep3')}'),
                          Text('4. ${tr('offlineStep4')}'),
                        ],
                      ),
                    ),
                  ),
                  if ((_syncMessage ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _syncMessage!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if ((_error ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (widget.isOwner) ...[
                    OutlinedButton.icon(
                      onPressed: _copyGloriaRecoverySnapshot,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy Gloria recovery snapshot (read-only)'),
                    ),
                    const Text(
                      'Copies private customer, invoice and payment recovery data. Share only in a private conversation. No upload or local changes.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: _syncing ? null : _recoverPendingInvoices,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Recover pending invoices'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Uploads queued customers, vehicles, invoices and recorded '
                    'payments only. Does not run the 22-step full sync, '
                    'delete records or finalize payments.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _syncNow,
                    icon: _syncing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      _syncing ? tr('syncing') : tr('syncNow'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _syncing ? null : _repairImportedData,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: Text(tr('repairImportedData')),
                  ),
                ],
              ),
            ),
    );
  }
}
