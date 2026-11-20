import 'invoice_labor_work_summary.dart';
import 'local_repair_groups.dart';
import 'local_warranty_companies.dart';
import 'local_customer_vehicle_identity.dart';
import 'invoice_tax_proposal.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'offline_invoice_finalization.dart';
import 'sync_replay_fence.dart';
import 'dart:convert';
import 'local_number_allocator.dart';
import 'local_estimate_number.dart';
import 'local_invoice_task_store.dart';
import 'local_owner_authorization.dart';
import '../core/connection_mode.dart';
import 'dart:math';

import 'package:drift/drift.dart';
import '../core/mileage_workflow.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_job_quarantine.dart';
import 'local_document_detail_cache.dart';
import 'local_document_repository.dart';
import 'local_job_repository.dart';
import 'offline_invoice_payment_ledger.dart';

class OfflineDocumentDraftService {
  OfflineDocumentDraftService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentDetailCache? cache,
    LocalDocumentRepository? documents,
    BriskersLocalDatabase? database,
  })  : _api = api,
        _cache = cache ?? LocalDocumentDetailCache(database: database),
        _database = database ?? localDatabase,
        _documents =
            documents ?? LocalDocumentRepository(database: database);

  final BriskersApi _api;
  final LocalDocumentDetailCache _cache;
  final BriskersLocalDatabase _database;
  final LocalDocumentRepository _documents;
  // Share each in-flight upload across Auto and manual Sync Now on this device.
  static final Expando<Map<String, Future<void>>> _activeFlushes = Expando();
  final Random _random = Random.secure();

  bool isLocalDraftId(String id) => id.startsWith('local-estimate-') || id.startsWith('local-invoice-');

  int _unixNow() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  String _offlineOperationUuid() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-'
        '${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  /// Store a blank invoice with a temporary local ID; the server allocates
  /// its number atomically after reconnecting. No fake invoice number is used.
  /// Prefill copied documents BEFORE enqueuing creation. Sync therefore
  /// observes a complete draft rather than a half-copied series of line edits.
  List<Map<String, dynamic>> _prepareCopiedLines(
      List<Map<String, dynamic>> source) {
    return [
      for (var index = 0; index < source.length; index++)
        <String, dynamic>{
          'id': _lineId(),
          'name': source[index]['name']?.toString() ?? '',
          'description': source[index]['description']?.toString(),
          'item_id': source[index]['item_id']?.toString(),
          'line_kind': source[index]['line_kind']?.toString() ?? 'item',
          'quantity': _number(source[index]['quantity']),
          'unit_price': _number(source[index]['unit_price']),
          'tax_rate': _number(source[index]['tax_rate']),
          'position': index + 1,
          '_local_draft_line': true,
        },
    ];
  }

  ({double net, double tax, double total}) _copiedTotals(
      List<Map<String, dynamic>> lines) {
    var net = 0.0;
    var tax = 0.0;
    for (final line in lines) {
      if (line['line_kind'] == 'discount') continue;
      final price = (_number(line['quantity']) *
          _number(line['unit_price']) * 100).round() / 100;
      final lineTax = (price * _number(line['tax_rate']) * 100).round() / 100;
      line['net_amount'] = price;
      line['tax_amount'] = lineTax;
      line['total_amount'] = price + lineTax;
      net += price;
      tax += lineTax;
    }
    return (net: net, tax: tax, total: net + tax);
  }

  Future<String> createQuickInvoice(
    String businessId, {
    required String customerId,
    required String customerName,
    String? vehicleId,
    String? vehicleLabel,
    String? existingJobId,
    int? reuseInvoiceNumber,
    int? reuseJobNumber,
    LocalOwnerGrant? reuseGrant,
    List<Map<String, dynamic>> initialLines = const [],
    String? initialMemo,
  }) async {
    if (customerId.isEmpty) {
      throw StateError('Select a saved customer before creating an invoice.');
    }
    final reusing = reuseInvoiceNumber != null || reuseJobNumber != null;
    void checkReuseAuthorization() {
      if (!reusing) return;
      if (reuseGrant == null ||
          !BriskersConnectionModeController.instance.forceOffline) {
        throw StateError('Owner authorization and Force Offline are required to reuse numbers.');
      }
      reuseGrant.assertValid(businessId, reuseGrant.actorId);
      if (existingJobId != null && reuseJobNumber != null) {
        throw StateError('An existing job keeps its number.');
      }
    }
    checkReuseAuthorization();
    final operationId = _offlineOperationUuid();
    final id = 'local-invoice-$operationId';
    final provisionalJobId = existingJobId ?? 'local-job-$operationId';
    String? jobNumber;
    String? invoiceNumber;
    final now = DateTime.now();
    final date = now.toIso8601String().split('T').first;
    final copiedLines = _prepareCopiedLines(initialLines);
    final totals = _copiedTotals(copiedLines);
    final detail = <String, dynamic>{
      'id': id,
      'kind': 'invoice',
      'document_number': null,
      'mileage_schema_version': 2,
      'mileage_out': null,
      'status': 'issued',
      'display_status': 'Open',
      'display_status_code': 'open',
      'job_id': provisionalJobId,
      'job_number': jobNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'vehicle_id': vehicleId,
      'vehicle': vehicleLabel,
      'document_date': date,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'memo': initialMemo,
      'lines': copiedLines,
      'net_amount': totals.net,
      'tax_amount': totals.tax,
      'total_amount': totals.total,
      'paid_amount': 0,
      'pending_payment': 0,
      'row_version': 1,
      'origin': 'native',
      'closed_at': null,
      'legacy_read_only': false,
      'legacy_editable': false,
      'sync_state': 'pending',
      '_local_snapshot': true,
      '_local_draft': true,
    };

    await _database.transaction(() async {
      final identities = LocalCustomerVehicleIdentity(_database);
      customerId = (await identities.resolve(businessId, customerId))!;
      vehicleId = await identities.resolve(businessId, vehicleId);
      detail['customer_id'] = customerId;
      detail['vehicle_id'] = vehicleId;
      final numbers=LocalNumberAllocator(_database);
      checkReuseAuthorization();
      for (final choice in {'invoice': reuseInvoiceNumber, 'job': reuseJobNumber}.entries) {
        if (choice.value != null &&
            !(await numbers.availableNumbers(businessId, choice.key)).contains(choice.value)) {
          throw StateError('That ${choice.key} number is no longer available. Choose again.');
        }
      }
      invoiceNumber=(await numbers.allocate(businessId,'invoice',id,
          requested: reuseInvoiceNumber)).toString();
      if(existingJobId==null) {
        jobNumber=numbers.display('job',await numbers.allocate(businessId,'job',provisionalJobId, requested: reuseJobNumber));
      } else {
        final jobs=await _database.customSelect('SELECT job_number FROM local_jobs WHERE business_id=? AND id=?',
          variables:[Variable<String>(businessId),Variable<String>(existingJobId)]).get();
        if(jobs.length!=1) throw StateError('Open the saved Job before creating an offline invoice.');
        jobNumber=jobs.single.read<String>('job_number');
      }
      detail['document_number']=invoiceNumber;
      detail['job_number']=jobNumber;
      // A standalone invoice creates one Job; a Job invoice keeps its existing parent.
      if(existingJobId==null) {
      await _database.customStatement(
        '''
        INSERT INTO local_jobs (
          id,business_id,access_scope,job_number,title,requested_work,
          status,status_name,customer_id,customer_name,vehicle_id,
          vehicle_label,created_at,sync_state
        ) VALUES (?,?,'full',?,'Invoice',NULL,'open','In progress',
                  ?,?,?,?,?,'pending')
        ''',
        [
          provisionalJobId,businessId,jobNumber,customerId,customerName,
          vehicleId,vehicleLabel,_unixNow(),
        ],
      );
      await _database.customStatement(
        '''
        INSERT INTO local_job_visits (
          id,business_id,job_id,visit_number,reason,opened_at,sync_state
        ) VALUES (?,?,?,1,'Initial visit',?,'pending')
        ''',
        ['local-visit-$operationId',businessId,provisionalJobId,_unixNow()],
      );
      }
      await _database.customStatement(
        '''
        INSERT INTO local_documents (
          id,business_id,job_id,customer_id,kind,document_number,
          status,display_status_code,closed_at,converted,total,
          document_date,created_at,server_updated_at,row_version,sync_state
        ) VALUES (?, ?, ?, ?, 'invoice', ?, 'issued', 'open',
                  NULL, 0, ?, ?, ?, NULL, 1, 'pending')
        ''',
        [id,businessId,provisionalJobId,customerId,invoiceNumber,totals.total,date,_unixNow()],
      );
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id,entity_type,entity_id,operation,payload_json,
          base_row_version,state,attempt_count,created_at,
          last_attempt_at,last_error
        ) VALUES (?, 'document_draft_create', ?, 'create_quick_invoice', ?,
                  NULL, 'pending', 0, ?, NULL, NULL)
        ''',
        [
          businessId,id,jsonEncode({
            'local_id':id,'kind':'invoice',
            'local_document_number':invoiceNumber,'local_job_number':jobNumber,
            'customer_id':customerId,'vehicle_id':vehicleId,
            'operation_id':operationId,'document_date':date,
            'provisional_job_id':provisionalJobId,
          }),_unixNow(),
        ],
      );
      // A sync worker cannot observe the queued copy before its full detail.
      await _cache.save(businessId, id, detail);
      checkReuseAuthorization();
    });
    return id;
  }

  /// Owner cancellation for a never-uploaded local Quick Invoice only.
  /// A previously attempted upload may already exist on the server, so we
  /// refuse unsafe offline deletion instead of orphaning a numbered invoice.
  Future<void> cancelNeverSyncedQuickInvoice(
    String businessId,
    String documentId,
  ) async {
    if (!documentId.startsWith('local-invoice-')) {
      throw StateError('Only an unsynced local invoice can be canceled offline.');
    }
    final snapshot = await _cache.load(businessId, documentId);
    if (snapshot == null || snapshot['_server_document_id'] != null) {
      throw StateError('This invoice has synced; reconnect before deleting.');
    }
    String? restoredEstimateId;
    Map<String, dynamic>? restoredEstimate;
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        '''
        SELECT id,payload_json,attempt_count,last_attempt_at,state
        FROM sync_outbox
        WHERE business_id=? AND entity_id=?
          AND entity_type='document_draft_create'
        LIMIT 1
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(documentId),
        ],
      ).get();
      if (rows.length != 1) {
        throw StateError('The invoice sync state is uncertain. Reconnect first.');
      }
      final row = rows.single;
      if (row.read<String>('state') != 'pending' ||
          row.read<int>('attempt_count') != 0 ||
          row.data['last_attempt_at'] != null) {
        throw StateError(
          'This invoice may already be syncing. Reconnect before deleting.',
        );
      }
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      final jobId = payload['provisional_job_id']?.toString() ?? '';
      // Converted estimates may already have a job, or use a
      // local-conversion-job- placeholder. Never apply quick-invoice rules
      // to them. Restore the source estimate only when neither operation
      // has ever been sent to the server.
      if (payload['kind'] == 'convert_invoice') {
        final estimateId = payload['estimate_id']?.toString() ?? '';
        if (!estimateId.startsWith('local-estimate-')) {
          throw StateError('Converted source is not a never-synced estimate.');
        }
        final original = await _cache.load(businessId, estimateId);
        if (original == null ||
            original['_server_document_id'] != null ||
            original['converted_invoice_id']?.toString() != documentId ||
            snapshot['converted_from_estimate_id']?.toString() != estimateId) {
          throw StateError('Estimate conversion references cannot be verified.');
        }
        final otherOps = await _database.customSelect(
          """SELECT COUNT(*) AS count FROM sync_outbox
             WHERE business_id=? AND entity_id=?
               AND entity_type='invoice_payment_received'""",
          variables: [
            Variable<String>(businessId),
            Variable<String>(documentId),
          ],
        ).getSingle();
        if (otherOps.read<int>('count') != 0) {
          throw StateError('Reconcile queued payments before cancellation.');
        }
        final originJob = original['job_id']?.toString() ?? '';
        final expectedPlaceholder =
            'local-conversion-job-${payload['operation_id']}';
        if (jobId.isNotEmpty && jobId != expectedPlaceholder) {
          throw StateError('Converted temporary Job link is inconsistent.');
        }
        if ((snapshot['job_id']?.toString() ?? '') !=
            (jobId.isNotEmpty ? jobId : originJob)) {
          throw StateError('Invoice Job does not match its source estimate.');
        }
        final shared = jobId.isEmpty
            ? 0
            : (await _database.customSelect(
                'SELECT COUNT(*) AS count FROM local_documents '
                'WHERE business_id=? AND job_id=? AND id<>?',
                variables: [
                  Variable<String>(businessId),
                  Variable<String>(jobId),
                  Variable<String>(documentId),
                ],
              ).getSingle()).read<int>('count');
        if (shared != 0) {
          throw StateError('Temporary Job is shared with other documents.');
        }
        await _database.customStatement(
          'DELETE FROM sync_outbox WHERE id=?', [row.read<int>('id')]);
        await _database.customStatement(
          'DELETE FROM local_documents WHERE business_id=? AND id=?',
          [businessId, documentId]);
        await _database.customStatement(
          """UPDATE local_documents SET converted=0, status='draft'
             WHERE business_id=? AND id=? AND sync_state='pending'""",
          [businessId, estimateId]);
        if (jobId.isNotEmpty) {
          await _database.customStatement(
            "DELETE FROM local_jobs WHERE business_id=? AND id=? AND sync_state='pending'",
            [businessId, jobId],
          );
        }
        // Cache writes happen after the database transaction below; mark
        // the restored source in memory so the outer method can save it.
        restoredEstimateId = estimateId;
        restoredEstimate = {
          ...original,
          'converted': false,
          'status': 'draft',
          'converted_invoice_id': null,
        };
        return;
      }
      if (jobId != 'local-job-${payload['operation_id']}') {
        throw StateError('The temporary Job link is inconsistent.');
      }
      // A local job shared by another document is not safe to delete.
      final linked = await _database.customSelect(
        'SELECT count(*) AS count FROM local_documents '
        'WHERE business_id=? AND job_id=? AND id<>?',
        variables: [
          Variable<String>(businessId),
          Variable<String>(jobId),
          Variable<String>(documentId),
        ],
      ).getSingle();
      if (linked.read<int>('count') != 0) {
        throw StateError('Other documents still refer to this Job.');
      }
      // A payment may have been captured while offline. Never erase the
      // invoice or its temporary Job while an unacknowledged payment exists.
      final pendingPayments = await _database.customSelect(
        '''SELECT COUNT(*) AS count FROM sync_outbox
           WHERE business_id=? AND entity_id=?
             AND entity_type='invoice_payment_received' ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(documentId),
        ],
      ).getSingle();
      if (pendingPayments.read<int>('count') != 0) {
        throw StateError(
          'This invoice has a queued payment. Reconcile it before deleting.',
        );
      }
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id=?',
        [row.read<int>('id')],
      );
      await _database.customStatement(
        'DELETE FROM local_documents WHERE business_id=? AND id=?',
        [businessId,documentId],
      );
      await _database.customStatement(
        'DELETE FROM local_job_visits WHERE business_id=? AND job_id=?',
        [businessId,jobId],
      );
      await _database.customStatement(
        "DELETE FROM local_jobs WHERE business_id=? AND id=? AND sync_state='pending'",
        [businessId,jobId],
      );
    });
    await _cache.remove(businessId, documentId);
    if (restoredEstimateId != null && restoredEstimate != null) {
      await _cache.save(businessId, restoredEstimateId!, restoredEstimate!);
    }
  }

  Future<void> deleteEstimate(String businessId, String estimateId) async {
    final snapshot = await _cache.load(businessId, estimateId);
    final syncedId = snapshot?['_server_document_id']?.toString();
    if (estimateId.startsWith('local-estimate-') && syncedId == null) {
      await cancelNeverSyncedStandaloneEstimate(businessId, estimateId);
      return;
    }
    final id = syncedId ?? estimateId;
    final savedNumber = await LocalEstimateNumber.stored(_database, businessId, id)
        ?? LocalEstimateNumber.existing(snapshot?['document_number']);
    await _api.deleteEstimate(businessId, id);
    await _database.transaction(() async {
      // Builds before the pool change kept the reservation on the draft ID.
      final numbers = LocalNumberAllocator(_database);
      await numbers.ensureSchema();
      await _database.customStatement(
        'UPDATE local_number_reservations SET entity_id=? WHERE business_id=? '
        "AND kind='estimate' AND entity_id=? AND active=1",
        [id, businessId, 'local-estimate-$id'],
      );
      if (estimateId != id) {
        await _documents.recordEstimateDeleted(businessId, estimateId);
      }
      await numbers.release(businessId, 'estimate', id, previousNumber: savedNumber);
      await _documents.recordEstimateDeleted(businessId, id);
    });
  }

  /// Cancel a draft before any upload attempt or conversion.
  Future<void> cancelNeverSyncedStandaloneEstimate(
    String businessId,
    String estimateId,
  ) async {
    if (!estimateId.startsWith('local-estimate-')) {
      throw StateError('Only local estimates can be canceled.');
    }
    final snapshot = await _cache.load(businessId, estimateId);
    if (snapshot == null ||
        snapshot['_server_document_id'] != null ||
        snapshot['converted'] == true ||
        (snapshot['converted_invoice_id']?.toString().isNotEmpty ?? false)) {
      throw StateError('This estimate is synced or linked to a conversion.');
    }
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        """SELECT id,operation,payload_json,attempt_count,last_attempt_at,state
           FROM sync_outbox
           WHERE business_id=? AND entity_id=?
             AND entity_type='document_draft_create'""",
        variables: [
          Variable<String>(businessId),
          Variable<String>(estimateId),
        ],
      ).get();
      if (rows.length != 1) {
        throw StateError(
          'Estimate cannot be deleted safely: expected one local create '
          'operation, found ${rows.length}. It may have synchronized.',
        );
      }
      final upload = rows.single;
      if (upload.read<String>('operation') != 'create_estimate') {
        throw StateError(
          'Estimate cannot be deleted safely: its creation operation is '
          'not an estimate.',
        );
      }
      if (upload.read<String>('state') != 'pending') {
        throw StateError(
          'Estimate cannot be deleted safely: upload is not pending.',
        );
      }
      if (upload.read<int>('attempt_count') != 0 ||
          upload.data['last_attempt_at'] != null) {
        throw StateError(
          'Estimate cannot be deleted safely: a server upload was already '
          'attempted. Reconcile the server record first.',
        );
      }
      final payload = Map<String, dynamic>.from(
        jsonDecode(rows.single.read<String>('payload_json')) as Map,
      );
      if (payload['local_id']?.toString() != estimateId ||
          payload['kind']?.toString() != 'estimate' ||
          payload['job_id']?.toString() != snapshot['job_id']?.toString()) {
        throw StateError('Saved estimate references do not match.');
      }
      final related = await _database.customSelect(
        """SELECT COUNT(*) AS count FROM sync_outbox
           WHERE business_id=? AND entity_id=?
             AND entity_type<>'document_draft_create'""",
        variables: [
          Variable<String>(businessId),
          Variable<String>(estimateId),
        ],
      ).getSingle();
      if (related.read<int>('count') != 0) {
        throw StateError('Estimate has other queued operations.');
      }
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id=?',
        [rows.single.read<int>('id')],
      );
      final estimate = await _database.customSelect(
        "SELECT document_number FROM local_documents WHERE business_id=? AND id=? "
        "AND kind='estimate' AND sync_state='pending' AND converted=0",
        variables: [Variable(businessId), Variable(estimateId)],
      ).getSingleOrNull();
      if (estimate == null) throw StateError('The estimate changed while deleting.');
      await LocalNumberAllocator(_database).release(businessId, 'estimate',
        estimateId, previousNumber: estimate.data['document_number']);
      await _documents.recordEstimateDeleted(businessId, estimateId);
    });
  }

  String _lineId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local-line-$now-$salt';
  }

  num _number(Object? raw) =>
      num.tryParse(raw?.toString() ?? '') ?? 0;

  int _strictMoneyCents(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '');
    if (value == null || !value.isFinite || value < 0 || value > 1e12) {
      throw StateError('Local invoice amount is missing or invalid.');
    }
    return (value * 100).round();
  }

  /// Create a quote locally without creating any Job. Operation UUID is
  /// replayed atomically on the server with its lines and notes.
  Future<String> createStandaloneEstimate(
    String businessId, {
    required String customerId,
    required String customerName,
    String? vehicleId,
    String? vehicleLabel,
    List<Map<String, dynamic>> initialLines = const [],
    String? initialMemo,
    int? reuseEstimateNumber,
    LocalOwnerGrant? reuseGrant,
  }) async {
    if (customerId.isEmpty) {
      throw StateError('Select a saved customer before creating an estimate.');
    }
    final operationId=_offlineOperationUuid();
    final id='local-estimate-$operationId';
    final now=DateTime.now();
    final date=now.toIso8601String().split('T').first;
    final copiedLines = _prepareCopiedLines(initialLines);
    final totals = _copiedTotals(copiedLines);
    final detail=<String,dynamic>{
      'id':id,'kind':'estimate',
      'status':'draft','display_status':'Draft',
      'display_status_code':'draft',
      'job_id':null,'job_number':null,
      'customer_id':customerId,'customer_name':customerName,
      'vehicle_id':vehicleId,'vehicle':vehicleLabel,
      'document_date':date,
      'created_at':now.toIso8601String(),
      'updated_at':now.toIso8601String(),
      'memo':initialMemo,'lines':copiedLines,
      'net_amount':totals.net,'tax_amount':totals.tax,'total_amount':totals.total,
      'paid_amount':0,'pending_payment':0,
      'row_version':1,'converted':false,
      'sync_state':'pending','_local_snapshot':true,'_local_draft':true,
    };
    await _database.transaction(() async {
      final identities = LocalCustomerVehicleIdentity(_database);
      customerId = (await identities.resolve(businessId, customerId))!;
      vehicleId = await identities.resolve(businessId, vehicleId);
      detail['customer_id'] = customerId;
      detail['vehicle_id'] = vehicleId;
      if (reuseEstimateNumber != null) {
        final grant = reuseGrant;
        if (grant == null) throw StateError('Owner authorization is required.');
        grant.assertValid(businessId, grant.actorId);
        final available = await LocalNumberAllocator(_database)
            .availableNumbers(businessId, 'estimate');
        if (!available.contains(reuseEstimateNumber)) {
          throw StateError('That estimate number is no longer available. Choose again.');
        }
      }
      final number = await LocalEstimateNumber.allocate(
        _database, businessId, id, requested: reuseEstimateNumber,
      );
      detail['document_number'] = number;
      await _database.customStatement(
        '''
        INSERT INTO local_documents(
          id,business_id,job_id,customer_id,kind,document_number,
          status,display_status_code,closed_at,converted,total,
          document_date,created_at,server_updated_at,row_version,sync_state
        ) VALUES (?, ?, NULL, ?, 'estimate', ?, 'draft','draft',
                  NULL,0,?,?,?,NULL,1,'pending')
        ''',
        [id,businessId,customerId,number,totals.total,date,_unixNow()],
      );
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox(
          business_id,entity_type,entity_id,operation,payload_json,
          base_row_version,state,attempt_count,created_at,
          last_attempt_at,last_error
        ) VALUES (?, 'document_draft_create', ?, 'create_estimate', ?,
                  NULL,'pending',0,?,NULL,NULL)
        ''',
        [
          businessId,id,
          jsonEncode({
            'local_id':id,'kind':'estimate',
            'customer_id':customerId,'vehicle_id':vehicleId,
            'operation_id':operationId,'document_date':date,
          }),
          _unixNow(),
        ],
      );
      // A sync worker cannot observe the queued copy before its full detail.
      await _cache.save(businessId, id, detail);
      if (reuseEstimateNumber != null) reuseGrant!.assertValid(businessId, reuseGrant.actorId);
    });
    return id;
  }

  Future<String> createEstimate(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, job_number, title, customer_id, customer_name,
             vehicle_id, vehicle_label
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    if (rows.isEmpty) {
      throw StateError(
        'This job is not saved on this device yet. Open it while online once, then retry.',
      );
    }

    final job = rows.first;
    final customerId =
        job.readNullable<String>('customer_id') ?? '';
    if (customerId.isEmpty) {
      throw StateError('The saved job does not have a customer.');
    }

    final operationId = _offlineOperationUuid();
    final id = 'local-estimate-$operationId';
    final now = DateTime.now();
    final detail = <String, dynamic>{
      'id': id,
      'kind': 'estimate',
      'status': 'draft',
      'display_status': 'Draft',
      'display_status_code': 'draft',
      'job_id': jobId,
      'job_number': job.readNullable<String>('job_number'),
      'job_title': job.read<String>('title'),
      'customer_id': customerId,
      'customer_name':
          job.readNullable<String>('customer_name') ?? 'Customer',
      'vehicle_id': job.readNullable<String>('vehicle_id'),
      'vehicle': job.readNullable<String>('vehicle_label'),
      'document_date': now.toIso8601String().split('T').first,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'memo': null,
      'lines': <Map<String, dynamic>>[],
      'net_amount': 0,
      'tax_amount': 0,
      'total_amount': 0,
      'paid_amount': 0,
      'pending_payment': 0,
      'row_version': 1,
      'converted': false,
      'sync_state': 'pending',
      '_local_snapshot': true,
      '_local_draft': true,
    };

    await _database.transaction(() async {
      final number = await LocalEstimateNumber.allocate(_database, businessId, id);
      detail['document_number'] = number;
      await _database.customStatement(
        '''
        INSERT INTO local_documents (
          id, business_id, job_id, customer_id, kind, document_number,
          status, display_status_code, closed_at, converted, total,
          document_date, created_at, server_updated_at, row_version, sync_state
        ) VALUES (?, ?, ?, ?, 'estimate', ?, 'draft', 'draft',
                  NULL, 0, 0, ?, ?, NULL, 1, 'pending')
        ''',
        [
          id,
          businessId,
          jobId,
          customerId,
          number,
          detail['document_date'],
          _unixNow(),
        ],
      );
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation, payload_json,
          base_row_version, state, attempt_count, created_at,
          last_attempt_at, last_error
        ) VALUES (?, 'document_draft_create', ?, 'create_estimate', ?,
                  NULL, 'pending', 0, ?, NULL, NULL)
        ''',
        [
          businessId,
          id,
          jsonEncode({
            'local_id': id,
            'job_id': jobId,
            'kind': 'estimate',
            'operation_id': operationId,
          }),
          _unixNow(),
        ],
      );
      await _cache.save(businessId, id, detail);
    });
    return id;
  }

  /// Save a warranty draft on a never-synced invoice. No network request
  /// is made; the invoice's existing create/convert operation owns replay.
  Future<void> savePendingInvoiceWarranty(
    String businessId,
    String documentId,
    Map<String, dynamic> warranty,
  ) async {
    if (!documentId.startsWith('local-invoice-')) {
      throw StateError('This warranty draft requires an unsynced local invoice.');
    }
    final detail = await _requireDraft(businessId, documentId);
    await _cache.save(businessId, documentId, {
      ...detail,
      'offline_warranty_detail': Map<String, dynamic>.from(warranty),
      'sync_state': 'pending',
    });
  }

  Future<Map<String, dynamic>> _applyPendingInvoiceWarranty(
    String businessId,
    String serverInvoiceId,
    Map<String, dynamic> localInvoice,
    int outboxId,
  ) async {
    final raw = localInvoice['offline_warranty_detail'];
    if (raw is! Map) {
      return _api.documentDetail(businessId, serverInvoiceId);
    }
    final warranty = Map<String, dynamic>.from(raw);
    String? companyId = warranty['warranty_company_id']?.toString();
    if (companyId?.startsWith('local-warranty-') == true) {
      companyId = await LocalJobQuarantine.guardReplay(_database, businessId,
        () => LocalWarrantyCompanies(database: _database, api: _api).serverId(businessId, companyId),
        outboxId: outboxId);
    }
    if (warranty['extended_warranty'] == true &&
        (companyId == null || companyId.isEmpty)) {
      final name = warranty['warranty_company_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        final existing = await _api.warrantyCompanies(businessId);
        for (final company in existing) {
          if ((company['name']?.toString().trim().toLowerCase() ?? '') ==
              name.toLowerCase()) {
            companyId = company['id']?.toString();
            break;
          }
        }
        companyId ??= await LocalJobQuarantine.guardReplay(
          _database,
          businessId,
          () => _api.createWarrantyCompany(
            businessId,
            name: name,
            claimsPhone: warranty['claims_phone']?.toString(),
            submissionEmail: warranty['submission_email']?.toString(),
          ),
          outboxId: outboxId,
        );
      }
    }
    final current = await _api.documentDetail(businessId, serverInvoiceId);
    final version = int.tryParse(current['row_version']?.toString() ?? '') ?? 1;
    await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.updateDocumentWarranty(
        businessId, serverInvoiceId,
        expectedVersion: version,
        extendedWarranty: warranty['extended_warranty'] == true,
        warrantyCompanyId: companyId,
        claimNumber: warranty['claim_number']?.toString(),
        authorizationNumber: warranty['authorization_number']?.toString(),
        approvedAmount: num.tryParse(warranty['approved_amount']?.toString() ?? ''),
        surchargeRate: num.tryParse(warranty['surcharge_rate']?.toString() ?? '') ?? 0.03,
      ),
      outboxId: outboxId,
    );
    return _api.documentDetail(businessId, serverInvoiceId);
  }

  /// Converts a cached estimate without creating another Job. The server
  /// conversion is deferred until the source estimate has a permanent ID.
  Future<String> convertEstimateOffline(String businessId, String estimateId) =>
      _database.transaction(() => _convertEstimateOffline(businessId, estimateId));

  Future<String> _convertEstimateOffline(String businessId, String estimateId) async {
    final source = await _cache.load(businessId, estimateId);
    if (source == null) {
      throw StateError('Open the estimate once while online to cache it.');
    }
    if (source['converted'] == true) {
      final id = source['converted_invoice_id']?.toString() ?? '';
      final prior = id.isEmpty ? null : await _cache.loadReadOnly(businessId, id);
      if (prior?['converted_from_estimate_id'] == estimateId) return id;
      throw StateError('This estimate is already converted.');
    }
    final estimate = await LocalRepairGroups(database: _database, cache: _cache)
        .authorizedDocument(businessId, estimateId, source);
    final lines = _lines(estimate);
    if (lines.isEmpty) throw StateError('Add at least one item first.');

    final operationId = _offlineOperationUuid();
    final invoiceId = 'local-invoice-$operationId';
    final originalJobId = estimate['job_id']?.toString() ?? '';
    final provisionalJobId = originalJobId.isEmpty ? 'local-conversion-job-$operationId' : null;
    final effectiveJobId = provisionalJobId ?? originalJobId;
    String? jobNumber;
    String? invoiceNumber;
    final now = DateTime.now();
    final detail = <String, dynamic>{
      ...estimate,
      'id': invoiceId,
      'kind': 'invoice',
      'document_number': null,
      'status': 'issued',
      'display_status': 'Open',
      'display_status_code': 'open',
      'converted': false,
      'converted_from_estimate_id': estimateId,
      'converted_from_estimate_number': estimate['document_number'],
      'job_id': effectiveJobId,
      'job_number': provisionalJobId != null ? jobNumber : estimate['job_number'],
      'job_title': estimate['job_title'] ?? estimate['title'] ?? 'Estimate repair',
      'paid_amount': 0,
      'pending_payment': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'sync_state': 'pending',
      '_local_snapshot': true,
      '_local_draft': true,
      'lines': lines.map((line) => <String, dynamic>{
        ...line,
        'id': 'local-conversion-$operationId-${lines.indexOf(line)}',
        '_local_draft_line': true,
      }).toList(),
    };
    final modifiedEstimate = <String, dynamic>{
      ...source,
      'converted': true,
      'status': 'accepted',
      'converted_invoice_id': invoiceId,
      'sync_state': 'pending',
    };
    await _database.transaction(() async {
      final numbers=LocalNumberAllocator(_database);
      invoiceNumber=(await numbers.allocate(businessId,'invoice',invoiceId)).toString();
      detail['document_number']=invoiceNumber;
      if(provisionalJobId!=null) {
        jobNumber=numbers.display('job',await numbers.allocate(businessId,'job',provisionalJobId));
        detail['job_number']=jobNumber;
      }
      if (provisionalJobId != null) {
        await _database.customStatement(
          '''INSERT INTO local_jobs (id,business_id,access_scope,job_number,title,
               status,status_name,customer_id,customer_name,vehicle_id,vehicle_label,
               created_at,sync_state)
             VALUES (?,?,'full',?,?,'open','Open',?,?,?,?,?,'pending')''',
          [provisionalJobId,businessId,jobNumber,
           (estimate['job_title'] ?? estimate['title'] ?? 'Estimate repair').toString(),
           estimate['customer_id'],estimate['customer_name'],estimate['vehicle_id'],
           estimate['vehicle'],_unixNow()],
        );
      }
      await _database.customStatement(
        '''INSERT INTO local_documents (
          id,business_id,job_id,customer_id,kind,document_number,
          status,display_status_code,closed_at,converted,total,
          document_date,created_at,server_updated_at,row_version,sync_state
        ) VALUES (?, ?, ?, ?, 'invoice', ?, 'issued', 'open',
                  NULL, 0, ?, ?, ?, NULL, 1, 'pending')''',
        [invoiceId, businessId, effectiveJobId, estimate['customer_id'], invoiceNumber,
         _number(estimate['total_amount']).toDouble(),
         estimate['document_date'], _unixNow()],
      );
      await _database.customStatement(
        "UPDATE local_documents SET converted=1,status='accepted',sync_state='pending' "
        "WHERE business_id=? AND id=?",
        [businessId, estimateId],
      );
      await _database.customStatement(
        '''INSERT INTO sync_outbox (
          business_id,entity_type,entity_id,operation,payload_json,
          base_row_version,state,attempt_count,created_at,
          last_attempt_at,last_error
        ) VALUES (?, 'document_draft_create', ?, 'convert_estimate', ?,
                  NULL, 'pending', 0, ?, NULL, NULL)''',
        [businessId, invoiceId, jsonEncode({
          'local_id': invoiceId, 'kind': 'convert_invoice',
          'local_document_number':invoiceNumber,'local_job_number':jobNumber,
          'estimate_id': estimateId, 'operation_id': operationId,
          'provisional_job_id': provisionalJobId,
        }), _unixNow()],
      );
      await _cache.save(businessId, invoiceId, detail);
      await _cache.save(businessId, estimateId, modifiedEstimate);
    });
    return invoiceId;
  }

  Future<void> addLine(
    String businessId,
    String documentId, {
    required String name,
    String? description,
    String? itemId,
    required num quantity,
    required num unitPrice,
    required num taxRate,
    required String lineKind,
  }) async {
    final detail = await _requireDraft(businessId, documentId);
    final lines = _lines(detail);
    final netAmount = quantity * unitPrice;
    final taxAmount = netAmount * taxRate;
    lines.add(<String, dynamic>{
      'id': _lineId(),
      'name': name,
      'description': description,
      'item_id': itemId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'tax_rate': taxRate,
      'net_amount': netAmount,
      'tax_amount': taxAmount,
      'line_kind': lineKind,
      'position': lines.length + 1,
      '_local_draft_line': true,
    });
    await _saveDraft(businessId, documentId, detail, lines);
  }

  Future<void> updateLine(
    String businessId,
    String documentId,
    String lineId, {
    required String name,
    String? description,
    required num quantity,
    required num unitPrice,
    required num taxRate,
    required String lineKind,
    String? replacementItemId,
    String? replacementPricingUnit,
  }) async {
    final detail = await _requireDraft(businessId, documentId);
    final lines = _lines(detail);
    final index =
        lines.indexWhere((line) => line['id']?.toString() == lineId);
    if (index < 0) throw StateError('The estimate line is not saved locally.');
    if (replacementItemId != null && isInvoiceLaborLine(lines[index]) &&
        !isInvoiceLaborLine({'name': name, 'line_kind': lineKind})) {
      throw StateError('Keep labor allocations on a labor line.');
    }

    final netAmount = quantity * unitPrice;
    final taxAmount = netAmount * taxRate;
    lines[index] = <String, dynamic>{
      ...lines[index],
      if (replacementItemId != null) ...{
        'item_id': replacementItemId, 'pricing_unit': replacementPricingUnit,
      },
      'name': name,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'tax_rate': taxRate,
      'net_amount': netAmount,
      'tax_amount': taxAmount,
      'line_kind': lineKind,
    };
    await _saveDraft(businessId, documentId, detail, lines);
  }

  Future<void> updateTaxRate(
    String businessId, String documentId, {
    required num oldRate, required num newRate,
  }) async {
    await _database.transaction(() async {
      final detail = await _requireDraft(businessId, documentId);
      if (detail['kind'] != 'invoice' || detail['closed_at'] != null ||
          _number(detail['paid_amount']) > 0 || _number(detail['pending_payment']) > 0) {
        throw StateError('Review recorded payments before changing tax.');
      }
      final lines = _lines(detail);
      final taxable = lines.where((line) => _number(line['tax_rate']) > 0).toList();
      if (taxable.isEmpty || taxable.any((line) =>
          (_number(line['tax_rate']) - oldRate).abs() > 0.0000001)) {
        throw StateError('Tax rates changed. Reopen the invoice.');
      }
      InvoiceTaxProposal.preview(lines: [
        for (final line in lines) {...line,
          'tax_mode': _number(line['tax_rate']) == 0 ? 'exempt' : 'default'},
      ], rate: newRate);
      final history = List<dynamic>.from(detail['_local_tax_history'] ?? const []);
      history.add({'at': DateTime.now().toUtc().toIso8601String(),
        'old_rate': oldRate, 'new_rate': newRate,
        'old_tax': detail['tax_amount'], 'old_total': detail['total_amount']});
      for (final line in taxable) { line['tax_rate'] = newRate; }
      await _saveDraft(businessId, documentId,
        {...detail, '_local_tax_history': history}, lines);
    });
  }

  Future<void> deleteLine(
    String businessId,
    String documentId,
    String lineId,
  ) async {
    final detail = await _requireDraft(businessId, documentId);
    final lines = _lines(detail)
      ..removeWhere((line) => line['id']?.toString() == lineId);
    await _saveDraft(businessId, documentId, detail, lines);
  }

  Future<void> copyLine(
    String businessId,
    String documentId,
    String lineId,
  ) async {
    final detail = await _requireDraft(businessId, documentId);
    final lines = _lines(detail);
    final index =
        lines.indexWhere((line) => line['id']?.toString() == lineId);
    if (index < 0) throw StateError('The estimate line is not saved locally.');

    lines.insert(
      index + 1,
      <String, dynamic>{
        ...lines[index],
        'id': _lineId(),
        '_local_draft_line': true,
      },
    );
    await _saveDraft(businessId, documentId, detail, lines);
  }

  Future<void> moveLine(
    String businessId,
    String documentId,
    String lineId,
    String direction,
  ) async {
    final detail = await _requireDraft(businessId, documentId);
    final lines = _lines(detail);
    final index =
        lines.indexWhere((line) => line['id']?.toString() == lineId);
    if (index < 0) throw StateError('The estimate line is not saved locally.');

    final next = direction == 'up' ? index - 1 : index + 1;
    if (next < 0 || next >= lines.length) return;
    final line = lines.removeAt(index);
    lines.insert(next, line);
    await _saveDraft(businessId, documentId, detail, lines);
  }

  /// Estimate headers have their own local path; never route them through
  /// invoice mileage/warranty editing. Preserve the saved items and totals.
  Future<void> updatePendingEstimateDetails(
    String businessId, String documentId, {
    required DateTime documentDate,
    required String customerId,
    required String customerName,
    String? vehicleId,
    String? vehicleLabel,
    String? mileage,
    String? claimNumber,
    String? authorizationNumber,
  }) async {
    if (customerId.isEmpty) throw StateError('Select a saved customer.');
    if (!documentId.startsWith('local-estimate-')) {
      throw StateError('This operation requires a pending local estimate.');
    }
    await _database.transaction(() async {
      final detail = await _requireDraft(businessId, documentId);
      if (detail['kind'] != 'estimate' || detail['converted'] == true ||
          (detail['converted_invoice_id']?.toString().isNotEmpty ?? false)) {
        throw StateError('Converted estimates cannot be edited.');
      }
      if ((detail['job_id']?.toString().isNotEmpty ?? false) &&
          (detail['customer_id'] != customerId || detail['vehicle_id'] != vehicleId)) {
        throw StateError('Change this estimate customer or vehicle after its linked Job has synced.');
      }
      final identities = LocalCustomerVehicleIdentity(_database);
      final customer = (await identities.resolve(businessId, customerId))!;
      final vehicle = await identities.resolve(businessId, vehicleId);
      final date = documentDate.toIso8601String().split('T').first;
      final updated = <String, dynamic>{...detail,
        'customer_id': customer, 'customer_name': customerName,
        'vehicle_id': vehicle, 'vehicle': vehicleLabel,
        'claim_number': claimNumber, 'authorization_number': authorizationNumber,
        'document_date': date,
        if (mileage != null) 'odometer_in': mileage.isEmpty ? null : num.tryParse(mileage),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final queued = await _database.customSelect(
        "SELECT id,payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? "
        "AND entity_type='document_draft_create' AND state='pending'",
        variables: [Variable(businessId), Variable(documentId)],
      ).getSingle();
      final payload = Map<String, dynamic>.from(jsonDecode(queued.read<String>('payload_json')) as Map);
      await _database.customStatement('UPDATE sync_outbox SET payload_json=? WHERE id=?',
        [jsonEncode({...payload, 'customer_id': customer, 'vehicle_id': vehicle,
          'document_date': date}), queued.read<int>('id')]);
      await _database.customStatement(
        'UPDATE local_documents SET customer_id=?,document_date=? WHERE business_id=? AND id=?',
        [customer,date,businessId,documentId]);
      await _cache.save(businessId, documentId, updated);
    });
  }

  /// Edit metadata on a queued local invoice without sending a temporary ID
  /// to UUID-only server RPCs. Refuse edits after replay has been attempted:
  /// the server may already hold a numbered version of this document.
  Future<void> updatePendingInvoiceDetails(
    String businessId,
    String documentId, {
    required DateTime documentDate,
    String? mileage,
    String? mileageOut,
    String? claimNumber,
    String? authorizationNumber,
    bool updateWarrantyIdentifiers = true,
  }) async {
    if (!documentId.startsWith('local-invoice-')) {
      throw StateError('This operation requires a pending local invoice.');
    }
    final detail = await _requireDraft(businessId, documentId);
    final date = documentDate.toIso8601String().split('T').first;
    // The invoice editor always treats pending local invoices as Miles Out.
    // Older drafts may lack the numeric v2 marker even though the editor
    // clearly requests departure mileage. Persist the explicit field, never
    // silently fall back to the ambiguous legacy odometer_in.
    final departure = mileageOut != null ||
        detail['mileage_schema_version']?.toString() == '2' ||
        detail.containsKey('mileage_out');
    final updated = <String, dynamic>{
      ...detail,
      'document_date': date,
      if (departure) ...{
        'mileage_schema_version': 2,
        if (mileageOut != null)
          'mileage_out': mileageOut.isEmpty
              ? null : MileageWorkflow.parse(mileageOut),
      } else if (mileage != null)
        'odometer_in': mileage.isEmpty ? null : num.tryParse(mileage),
      if (updateWarrantyIdentifiers) ...{
        'claim_number': claimNumber,
        'authorization_number': authorizationNumber,
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'pending',
    };
    await _database.transaction(() async {
      await _database.customStatement(
        'UPDATE local_documents SET document_date=?, sync_state=? '
        'WHERE business_id=? AND id=?',
        [date, 'pending', businessId, documentId],
      );
      await _cache.save(businessId, documentId, updated);
    });
  }

  Future<void> saveMemo(
    String businessId,
    String documentId,
    String? memo,
  ) async {
    final detail = await _requireDraft(businessId, documentId);
    final updated = <String, dynamic>{
      ...detail,
      'memo': memo,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'pending',
    };
    await _cache.save(businessId, documentId, updated);
  }

  Future<Map<String, dynamic>> _requireDraft(
    String businessId,
    String documentId,
  ) async {
    if (!isLocalDraftId(documentId)) {
      throw StateError('This is not a local estimate draft.');
    }
    final detail = await _cache.load(businessId, documentId);
    if (detail == null) {
      throw StateError('The local estimate draft could not be found.');
    }
    if (documentId.startsWith('local-invoice-') ||
        documentId.startsWith('local-estimate-')) {
      if ((detail['_server_document_id']?.toString() ?? '').isNotEmpty) {
        throw StateError('This document has synced. Open its numbered record.');
      }
      final rows = await _database.customSelect(
        "SELECT state,attempt_count,last_attempt_at FROM sync_outbox "
        "WHERE business_id=? AND entity_id=? "
        "AND entity_type='document_draft_create' LIMIT 1",
        variables: [
          Variable<String>(businessId),
          Variable<String>(documentId),
        ],
      ).get();
      if (rows.isEmpty) {
        throw StateError('This document is no longer queued. Reopen it.');
      }
      if (rows.isNotEmpty) {
        final row = rows.single;
        if (row.read<String>('state') != 'pending' ||
            row.read<int>('attempt_count') != 0 ||
            row.data['last_attempt_at'] != null) {
          throw StateError(
            'This document is synchronizing. Reopen it once sync finishes.',
          );
        }
      }
    }
    return detail;
  }

  List<Map<String, dynamic>> _lines(Map<String, dynamic> detail) =>
      List<dynamic>.from(detail['lines'] ?? const <dynamic>[])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();

  Future<void> _saveDraft(
    String businessId,
    String documentId,
    Map<String, dynamic> detail,
    List<Map<String, dynamic>> lines,
  ) async {
    if (detail['repair_group_invoice'] != null) {
      throw StateError('Renew repair authorization before changing these invoice items.');
    }
    if (lines.any((line) => line['line_kind'] == 'discount') &&
        (detail['repair_group_invoice'] != null ||
          await LocalRepairGroups(database: _database, cache: _cache).enabled(businessId, documentId))) {
      throw StateError('This discounted repair quote cannot be edited here yet. The saved amounts have not changed.');
    }
    for (var i = 0; i < lines.length; i++) {
      lines[i] = <String, dynamic>{...lines[i], 'position': i + 1};
    }

    var net = 0.0;
    var tax = 0.0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line['line_kind']?.toString() == 'discount') continue;
      final amount = (_number(line['quantity']) *
          _number(line['unit_price']) * 100).round() / 100;
      final lineTax = (amount * _number(line['tax_rate']) * 100).round() / 100;
      lines[index] = <String, dynamic>{
        ...line,
        'net_amount': amount.toDouble(),
        'tax_amount': lineTax.toDouble(),
        'total_amount': (amount + lineTax).toDouble(),
      };
      net += amount.toDouble();
      tax += lineTax.toDouble();
    }
    final total = net + tax;

    final updated = <String, dynamic>{
      ...detail,
      'lines': lines,
      'net_amount': net,
      'tax_amount': tax,
      'total_amount': total,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'pending',
    };

    await _database.customStatement(
      '''
      UPDATE local_documents
      SET total = ?, sync_state = 'pending'
      WHERE business_id = ? AND id = ?
      ''',
      [total, businessId, documentId],
    );
    await _cache.save(businessId, documentId, updated);
  }

  // Reconcile a converted invoice to the latest locally edited draft.
  // Every retry fetches current server lines and applies at most one change,
  // so an interrupted response cannot add a duplicate on replay.
  Future<Map<String, dynamic>> _reconcileConvertedInvoice(
    String businessId, String invoiceId, Map<String, dynamic> localDetail,
    int outboxId,
  ) async {
    final desired = _lines(localDetail);
    for (var attempt = 0; attempt < desired.length * 4 + 40; attempt++) {
      final remote = await _api.documentDetail(businessId, invoiceId);
      final existing = _lines(remote);
      bool same(Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['item_id'] == null || a['item_id'] == b['item_id']) &&
          (a['name']?.toString() ?? '') == (b['name']?.toString() ?? '') &&
          (a['description']?.toString() ?? '') == (b['description']?.toString() ?? '') &&
          (a['line_kind']?.toString() ?? '') == (b['line_kind']?.toString() ?? '') &&
          (_number(a['quantity']) - _number(b['quantity'])).abs() < 0.00001 &&
          (_number(a['unit_price']) - _number(b['unit_price'])).abs() < 0.00001 &&
          (_number(a['tax_rate']) - _number(b['tax_rate'])).abs() < 0.00001;
      if (existing.length == desired.length &&
          List.generate(desired.length, (i) => same(existing[i], desired[i]))
              .every((ok) => ok)) {
        return remote;
      }
      final version = int.tryParse(remote['row_version']?.toString() ?? '') ?? 1;
      if (existing.length > desired.length) {
        await LocalJobQuarantine.guardReplay(
          _database,
          businessId,
          () => _api.deleteDocumentLine(businessId, existing.last['id'].toString(),
              expectedVersion: version),
          outboxId: outboxId,
        );
        continue;
      }
      var corrected = false;
      for (var i = 0; i < existing.length; i++) {
        final a = existing[i];
        final b = desired[i];
        if (same(a, b)) continue;
        if (a['name'] == b['name'] && a['line_kind'] == b['line_kind'] &&
            (b['item_id'] == null || a['item_id'] == b['item_id'])) {
          await LocalJobQuarantine.guardReplay(_database, businessId,
            () => _api.updateDocumentLine(businessId, a['id'].toString(),
              expectedVersion: version, quantity: _number(b['quantity']),
              unitPrice: _number(b['unit_price']), taxRate: _number(b['tax_rate']),
              description: b['description']?.toString()), outboxId: outboxId);
        } else {
          await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => _api.updateDocumentLineV2(businessId, a['id'].toString(),
              expectedVersion: version, name: b['name']?.toString() ?? 'Item',
              quantity: _number(b['quantity']),
              unitPrice: _number(b['unit_price']), taxRate: _number(b['tax_rate']),
              description: b['description']?.toString(),
              lineKind: b['line_kind']?.toString() ?? 'item',
              replacementItemId: a['item_id'] == b['item_id']
                  ? null : b['item_id']?.toString()),
            outboxId: outboxId,
          );
        }
        corrected = true;
        break;
      }
      if (corrected) continue;
      final next = desired[existing.length];
      await LocalJobQuarantine.guardReplay(
        _database,
        businessId,
        () => _api.addDocumentLine(businessId, invoiceId,
          expectedVersion: version, name: next['name']?.toString() ?? 'Item',
          description: next['description']?.toString(),
          itemId: next['item_id']?.toString(),
          quantity: _number(next['quantity']),
          unitPrice: _number(next['unit_price']),
          taxRate: _number(next['tax_rate']),
          lineKind: next['line_kind']?.toString() ?? 'item'),
        outboxId: outboxId,
      );
    }
    throw StateError('Converted invoice line reconciliation did not complete safely.');
  }

  Future<void> flush(String businessId, {bool exactTotalRecovery = false}) {
    if (BriskersConnectionModeController.instance.forceOffline) return Future.value();
    final active = _activeFlushes[_database] ??= <String, Future<void>>{};
    final existing = active[businessId];
    if (existing != null) return existing;
    final work = _flushInternal(businessId, exactTotalRecovery: exactTotalRecovery);
    active[businessId] = work;
    return work.whenComplete(() {
      if (identical(active[businessId], work)) active.remove(businessId);
    });
  }

  Future<void> _flushInternal(String businessId, {bool exactTotalRecovery = false}) async {
    await LocalEstimateNumber.ensureRepairQueue(_database);
    final repairs = await _database.customSelect(
      'SELECT * FROM local_estimate_number_sync_v2 WHERE business_id=? AND conflict IS NULL LIMIT 50',
      variables: [Variable(businessId)],
    ).get();
    for (final repair in repairs) {
      if (BriskersConnectionModeController.instance.forceOffline) return;
      final id = repair.read<String>('estimate_id');
      try {
        await _api.syncEstimateNumber(businessId, id,
          number: repair.read<String>('public_number'),
          ownerConfirmed: repair.read<int>('owner_confirmed') == 1,
        );
        await _database.customStatement(
          'DELETE FROM local_estimate_number_sync_v2 WHERE business_id=? AND estimate_id=?',
          [businessId, id],
        );
      } on PostgrestException catch (error) {
        if (const {'PT409', '23505', '42501', '22023'}.contains(error.code)) {
          await _database.customStatement(
            'UPDATE local_estimate_number_sync_v2 SET conflict=? WHERE business_id=? AND estimate_id=?',
            [error.message, businessId, id],
          );
          continue;
        }
        break;
      } catch (_) {
        // The local number is already usable. Leave its optional upload queued
        // for the next sync and let other draft operations proceed.
        break;
      }
    }
    final rows = await _database.customSelect(
      '''
      SELECT id, entity_id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'document_draft_create'
        AND state IN ('pending','inflight')
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final queued in rows) {
      if (BriskersConnectionModeController.instance.forceOffline) return;
      // Re-read dependencies, as a preceding customer/vehicle sync may have
      // replaced temporary IDs after this batch was originally selected.
      final fresh = await _database.customSelect(
        "SELECT id, entity_id, payload_json, last_attempt_at FROM sync_outbox "
        "WHERE id=? AND business_id=? AND entity_type='document_draft_create' "
        "AND state IN ('pending','inflight') LIMIT 1",
        variables: [Variable<int>(queued.read<int>('id')),
          Variable<String>(businessId)],
      ).get();
      if (fresh.isEmpty) continue;
      final row = fresh.single;
      final outboxId = row.read<int>('id');
      final localId = row.read<String>('entity_id');
      // A dependent record is not a failed upload: leave it queued until
      // its customer, vehicle, or job obtains an authoritative server UUID.
      // In particular, never pass "local-vehicle-..." into UUID RPC fields.
      final preflight = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      // Legacy estimate upload has no repair-group/authorization contract.
      // Do not publish an ungrouped copy that could later bill declined work.
      if (await LocalRepairGroups(database: _database, cache: _cache)
          .enabled(businessId, localId)) {
        continue;
      }
      // Device-numbered invoices remain local until explicit reconciliation exists.
      if(preflight['local_document_number'] != null) continue;
      final dependencies = <String>[
        preflight['customer_id']?.toString() ?? '',
        preflight['vehicle_id']?.toString() ?? '',
        preflight['job_id']?.toString() ?? '',
      ];
      if (dependencies.any((id) => id.startsWith('local-'))) {
        await _database.customStatement(
          "UPDATE sync_outbox SET state='pending', "
          "last_error='Waiting for local customer / vehicle / job ID reconciliation' "
          "WHERE id=?",
          [outboxId],
        );
        continue;
      }
      if (preflight['kind'] == 'estimate' && preflight['job_id'] != null &&
          preflight['operation_id'] == null && row.data['last_attempt_at'] != null) {
        await _database.customStatement(
          "UPDATE sync_outbox SET last_error='Verify an earlier estimate upload before retrying' WHERE id=?",
          [outboxId],
        );
        continue;
      }
      if (preflight['kind'] == 'estimate' && preflight['operation_id'] == null) {
        preflight['operation_id'] = LocalEstimateNumber.identity(businessId, localId);
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [jsonEncode(preflight), outboxId],
        );
      }
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: outboxId,
        );
        // Claim before sending any bytes. A delete can cancel only an
        // untouched operation; reconnect if an upload might have started.
        await _database.customStatement(
          "UPDATE sync_outbox SET state='inflight',last_attempt_at=? "
          "WHERE id=? AND state IN ('pending','inflight')",
          [_unixNow(),outboxId],
        );
        final payload = preflight;
        final localDetail = await _cache.load(businessId, localId);
        if (localDetail == null) {
          throw StateError('The offline document draft is missing.');
        }

        late final String serverId;
        late Map<String, dynamic> serverDetail;
        String? convertedEstimateId;
        if (payload['kind'] == 'convert_invoice') {
          final localEstimateId = payload['estimate_id']?.toString() ?? '';
          final cachedEstimate = await _cache.load(businessId, localEstimateId);
          final estimateServerId = cachedEstimate?['_server_document_id']?.toString() ??
              (localEstimateId.startsWith('local-') ? '' : localEstimateId);
          if (estimateServerId.isEmpty) {
            throw StateError('Source estimate needs to synchronize first.');
          }
          convertedEstimateId = estimateServerId;
          final currentEstimate = await _api.documentDetail(businessId, estimateServerId);
          final alreadyConverted = currentEstimate['converted'] == true;
          if (alreadyConverted) {
            serverId = currentEstimate['converted_invoice_id']?.toString() ?? '';
            if (serverId.isEmpty) {
              throw StateError('Converted estimate has no invoice reference.');
            }
          } else {
            serverId = await LocalJobQuarantine.guardReplay(
              _database,
              businessId,
              () => _api.convertEstimate(businessId, estimateServerId),
              outboxId: outboxId,
            );
          }
          serverDetail = await _reconcileConvertedInvoice(
              businessId, serverId, localDetail, outboxId);
          final localMemo = localDetail['memo']?.toString().trim() ?? '';
          final remoteMemo = serverDetail['memo']?.toString().trim() ?? '';
          if (localMemo != remoteMemo) {
            final version = int.tryParse(
                serverDetail['row_version']?.toString() ?? '') ?? 1;
            await LocalJobQuarantine.guardReplay(
              _database,
              businessId,
              () => _api.updateDocumentNotes(
                businessId, serverId,
                expectedVersion: version,
                memo: localMemo.isEmpty ? null : localMemo,
              ),
              outboxId: outboxId,
            );
            serverDetail = await _api.documentDetail(businessId, serverId);
          }
        } else if (payload['kind'] == 'invoice') {
          final operationId = payload['operation_id']?.toString() ?? '';
          final customerId = payload['customer_id']?.toString() ?? '';
          if (operationId.isEmpty || customerId.isEmpty) {
            throw StateError('Offline invoice is missing its sync identity.');
          }
          final sourceLines = _lines(localDetail);
          final expectedNetCents = _strictMoneyCents(
            localDetail['net_amount']);
          final expectedTaxCents = _strictMoneyCents(
            localDetail['tax_amount']);
          var serverLineNetCents = 0;
          var serverLineTaxCents = 0;
          for (final line in sourceLines) {
            if (line['line_kind'] == 'discount') {
              throw StateError(
                'Offline discounts require a separate reviewed recovery path.');
            }
            final qty = _number(line['quantity']);
            final unitPrice = _number(line['unit_price']);
            final rate = _number(line['tax_rate']);
            if (!qty.isFinite || !unitPrice.isFinite || !rate.isFinite ||
                qty <= 0 || unitPrice < 0 || rate < 0 || rate > 1) {
              throw StateError('Invalid local invoice line in recovery.');
            }
            // Match PostgreSQL numeric(18,2) line net/tax rounding.
            final cents = (qty * unitPrice * 100).round();
            serverLineNetCents += cents;
            serverLineTaxCents += (cents * rate).round();
          }
          final requiresExactTotal =
              expectedNetCents != serverLineNetCents ||
              expectedTaxCents != serverLineTaxCents;
          if (requiresExactTotal && !exactTotalRecovery) {
            throw StateError(
              'Local invoice totals differ from standard per-line rounding. '
              'Automatic v1 upload is blocked to prevent a financial mismatch; '
              'use Owner > Recover pending invoices once the exact-total '
              'recovery backend is installed.');
          }
          // Explicit Owner recovery uses verified exact net/tax cents.
          // A missing or incompatible v2 RPC fails without v1 fallback:
          // leave the existing outbox and recorded payment untouched.
          serverId = await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => requiresExactTotal
                ? _api.syncOfflineQuickInvoiceExactTotal(
                    businessId,
                    customerId: customerId,
                    vehicleId: payload['vehicle_id']?.toString(),
                    operationId: operationId,
                    documentDate: payload['document_date']?.toString() ?? '',
                    lines: sourceLines,
                    memo: localDetail['memo']?.toString(),
                    expectedNetCents: expectedNetCents,
                    expectedTaxCents: expectedTaxCents,
                  )
                : _api.syncOfflineQuickInvoice(
                    businessId,
                    customerId: customerId,
                    vehicleId: payload['vehicle_id']?.toString(),
                    operationId: operationId,
                    documentDate: payload['document_date']?.toString() ?? '',
                    lines: sourceLines,
                    memo: localDetail['memo']?.toString(),
                  ),
            outboxId: outboxId,
          );
          serverDetail = await _api.documentDetail(businessId,serverId);
          if ((serverDetail['job_id']?.toString() ?? '').isEmpty) {
            throw StateError('The synced invoice did not return its linked Job.');
          }
        } else {
          final publicNumber = LocalEstimateNumber.existing(localDetail['document_number']);
          if (publicNumber == null) {
            throw StateError('Confirm the estimate number correction before synchronizing.');
          }
          final jobId = payload['job_id']?.toString();
          final operationId = payload['operation_id'] as String;
          final date = localDetail['document_date']?.toString() ?? '';
          final lines = _lines(localDetail);
          final memo = localDetail['memo']?.toString();
          serverId = await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => jobId == null || jobId.isEmpty
                ? _api.syncOfflineStandaloneEstimate(
                    businessId,
                    customerId: payload['customer_id'] as String,
                    vehicleId: payload['vehicle_id']?.toString(),
                    operationId: operationId, publicNumber: publicNumber,
                    documentDate: date,
                    lines: lines,
                    memo: memo,
                  )
                : _api.syncOfflineJobEstimate(
                    businessId, jobId: jobId, operationId: operationId, publicNumber: publicNumber,
                    documentDate: date, lines: lines, memo: memo,
                  ),
            outboxId: outboxId,
          );
          serverDetail = await _api.documentDetail(businessId, serverId);
          final expectedNumber = publicNumber;
          if (serverId != operationId || LocalEstimateNumber.existing(serverDetail['document_number']) != expectedNumber) {
            throw StateError('The synchronized estimate number differs from the saved estimate.');
          }
        }

        if ((payload['kind'] == 'invoice' ||
                payload['kind'] == 'convert_invoice') &&
            localDetail['mileage_schema_version'] == 2 &&
            localDetail['mileage_out'] != null) {
          // A provisional local invoice cannot call UUID-only mileage RPCs.
          // Transfer its verified departure reading AFTER the permanent
          // invoice exists, before retiring the same durable draft outbox.
          if (serverDetail['mileage_schema_version'] != 2) {
            throw StateError('Mileage Out server schema is not available yet.');
          }
          final desired = MileageWorkflow.parse(localDetail['mileage_out']);
          if (desired == null) {
            throw StateError('Invalid unsynced invoice departure mileage.');
          }
          if (MileageWorkflow.parse(serverDetail['mileage_out']) != desired) {
            final version = int.tryParse(
              serverDetail['row_version']?.toString() ?? '',
            );
            if (version == null || version < 1) {
              throw StateError('Invoice row revision is missing.');
            }
            try {
              await LocalJobQuarantine.guardReplay(
                _database, businessId,
                () => _api.saveInvoiceMileageOut(
                  businessId, serverId,
                  expectedVersion: version,
                  mileageOut: desired,
                ),
                outboxId: outboxId,
              );
            } catch (error) {
              if (error is SyncReplayDeferred) rethrow;
              // A lost acknowledgment may follow a committed write.
              // Never retry this mutation with a new guessed revision.
              final proof = await _api.documentDetail(
                businessId, serverId);
              if (proof['mileage_schema_version'] != 2 ||
                  MileageWorkflow.parse(proof['mileage_out']) != desired) {
                rethrow;
              }
            }
            serverDetail = await _api.documentDetail(businessId, serverId);
          }
        }

        if (payload['kind'] == 'convert_invoice' && localDetail['converted_from_estimate_number'] != null) {
          serverDetail = {...serverDetail,
            'converted_from_estimate_number': localDetail['converted_from_estimate_number']};
        }
        if (payload['kind'] == 'invoice' || payload['kind'] == 'convert_invoice') {
          serverDetail = await _applyPendingInvoiceWarranty(
            businessId, serverId, localDetail, outboxId);
        }
        if (payload['kind'] == 'convert_invoice') {
          serverDetail = {...serverDetail,
            'converted_from_estimate_id': convertedEstimateId,
            'converted_from_estimate_number': localDetail['converted_from_estimate_number']};
        }
        if (payload['kind'] == 'estimate' && localDetail['converted'] == true) {
          serverDetail = {...serverDetail, 'converted': true,
            'converted_invoice_id': localDetail['converted_invoice_id'],
            'converted_invoice_number': localDetail['converted_invoice_number'],
            'converted_invoice_date': localDetail['converted_invoice_date']};
        }
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: outboxId,
          );
          if (payload['kind'] == 'invoice' || payload['kind'] == 'convert_invoice') {
            final provisionalJobId =
                payload['provisional_job_id']?.toString() ?? '';
            if (provisionalJobId.isNotEmpty) {
              final jobNumber = await LocalJobRepository(database: _database)
                  .remapProvisionalJob(
                businessId,
                provisionalJobId,
                serverDetail['job_id']?.toString() ?? '',
                jobNumber: serverDetail['job_number']?.toString(),
              );
              // Some document responses omit the number. Keep the same visible,
              // clickable TEMP label until the real Job number is downloaded.
              serverDetail = {...serverDetail, 'job_number': jobNumber};
            }
          }
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: outboxId,
          );
          await _documents.upsertFromServer(
            businessId,
            [serverDetail],
          );
          await LocalInvoiceTaskStore(_database).remapDraft(
            businessId, localId, localDetail, serverDetail);
          await _cache.save(businessId, serverId, serverDetail);
          await _cache.save(
            businessId,
            localId,
            <String, dynamic>{
              ...serverDetail,
              '_server_document_id': serverId,
            },
          );

          if (payload['kind'] == 'convert_invoice') {
            final originalId = payload['estimate_id']?.toString() ?? '';
            final original = await _cache.load(businessId, originalId);
            if (original != null) {
              await _cache.save(businessId, originalId, {
                ...original,
                'converted': true,
                'converted_invoice_id': serverId,
                'sync_state': 'synced',
              });
              final estimateId = convertedEstimateId!;
              await _database.customStatement(
                "UPDATE local_documents SET converted=1 WHERE business_id=? AND id=? AND kind='estimate'",
                [businessId, estimateId]);
              await _cache.save(businessId, estimateId, {
                ...original, 'id': estimateId, 'converted': true,
                'converted_invoice_id': serverId,
                'converted_invoice_number': serverDetail['document_number'],
                'converted_invoice_date': serverDetail['document_date'],
                'sync_state': 'synced',
              });
            }
          }
          if (payload['kind'] == 'invoice' || payload['kind'] == 'convert_invoice') {
            await OfflineInvoiceFinalization(database:_database).remap(businessId,localId,serverId);
            await OfflineInvoicePaymentLedger(database: _database).remapInvoice(
              businessId,
              localId,
              serverId,
            );
          }

          if (payload['kind'] == 'estimate') {
            await LocalNumberAllocator(_database).ensureSchema();
            await _database.customStatement(
              'UPDATE local_number_reservations SET entity_id=? WHERE business_id=? '
              "AND kind='estimate' AND entity_id=? AND active=1",
              [serverId, businessId, localId],
            );
            await _remapPendingEstimateMerges(
              businessId,
              localId,
              serverId,
            );
          }

          await _database.customStatement(
            'DELETE FROM local_documents WHERE business_id = ? AND id = ?',
            [businessId, localId],
          );
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id = ?',
            [outboxId],
          );
        });
      } catch (error) {
        final conflict = preflight['kind'] == 'estimate' &&
            error is PostgrestException &&
            const {'PT409','23505','42501','22023'}.contains(error.code);
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              state = ?,
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [conflict ? 'conflict' : 'pending', _unixNow(), error.toString(), outboxId],
        );
        if (!conflict) break;
      }
    }
  }

  Future<void> _remapPendingEstimateMerges(
    String businessId,
    String localId,
    String serverId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'estimate_add_to_invoice'
        AND state = 'pending'
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
      } catch (_) {
        continue;
      }
      if (payload['estimate_id']?.toString() != localId) continue;
      payload['estimate_id'] = serverId;
      await _database.customStatement(
        'UPDATE sync_outbox SET entity_id = ?, payload_json = ? WHERE id = ?',
        [serverId, jsonEncode(payload), row.read<int>('id')],
      );
    }
  }
}

