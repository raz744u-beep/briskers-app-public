import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'local_document_repository.dart';

class OfflineDocumentDraftService {
  OfflineDocumentDraftService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentDetailCache cache = const LocalDocumentDetailCache(),
    LocalDocumentRepository? documents,
    BriskersLocalDatabase? database,
  })  : _api = api,
        _cache = cache,
        _database = database ?? localDatabase,
        _documents =
            documents ?? LocalDocumentRepository(database: database);

  final BriskersApi _api;
  final LocalDocumentDetailCache _cache;
  final BriskersLocalDatabase _database;
  final LocalDocumentRepository _documents;
  final Random _random = Random.secure();

  bool isLocalDraftId(String id) => id.startsWith('local-estimate-') || id.startsWith('local-invoice-');

  int _unixNow() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  String _localId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local-estimate-$now-$salt';
  }

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
  Future<String> createQuickInvoice(
    String businessId, {
    required String customerId,
    required String customerName,
    String? vehicleId,
    String? vehicleLabel,
  }) async {
    if (customerId.isEmpty) {
      throw StateError('Select a saved customer before creating an invoice.');
    }
    final operationId = _offlineOperationUuid();
    final id = 'local-invoice-$operationId';
    final provisionalJobId = 'local-job-$operationId';
    final now = DateTime.now();
    final date = now.toIso8601String().split('T').first;
    final detail = <String, dynamic>{
      'id': id,
      'kind': 'invoice',
      'document_number': null,
      'status': 'issued',
      'display_status': 'Pending sync',
      'display_status_code': 'open',
      'job_id': provisionalJobId,
      'customer_id': customerId,
      'customer_name': customerName,
      'vehicle_id': vehicleId,
      'vehicle': vehicleLabel,
      'document_date': date,
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
      'origin': 'native',
      'closed_at': null,
      'legacy_read_only': false,
      'legacy_editable': false,
      'sync_state': 'pending',
      '_local_snapshot': true,
      '_local_draft': true,
    };

    await _database.transaction(() async {
      // Keep a visible local Job linked to the offline invoice. Both
      // placeholders are replaced only after one idempotent server operation.
      await _database.customStatement(
        '''
        INSERT INTO local_jobs (
          id,business_id,access_scope,job_number,title,requested_work,
          status,status_name,customer_id,customer_name,vehicle_id,
          vehicle_label,created_at,sync_state
        ) VALUES (?,?,'full',NULL,'Invoice',NULL,'open','In progress',
                  ?,?,?,?,?,'pending')
        ''',
        [
          provisionalJobId,businessId,customerId,customerName,
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
      await _database.customStatement(
        '''
        INSERT INTO local_documents (
          id,business_id,job_id,customer_id,kind,document_number,
          status,display_status_code,closed_at,converted,total,
          document_date,created_at,server_updated_at,row_version,sync_state
        ) VALUES (?, ?, ?, ?, 'invoice', NULL, 'issued', 'open',
                  NULL, 0, 0, ?, ?, NULL, 1, 'pending')
        ''',
        [id,businessId,provisionalJobId,customerId,date,_unixNow()],
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
            'customer_id':customerId,'vehicle_id':vehicleId,
            'operation_id':operationId,'document_date':date,
            'provisional_job_id':provisionalJobId,
          }),_unixNow(),
        ],
      );
    });
    await _cache.save(businessId,id,detail);
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
  }

  String _lineId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local-line-$now-$salt';
  }

  num _number(Object? raw) =>
      num.tryParse(raw?.toString() ?? '') ?? 0;

  /// Create a quote locally without creating any Job. Operation UUID is
  /// replayed atomically on the server with its lines and notes.
  Future<String> createStandaloneEstimate(
    String businessId, {
    required String customerId,
    required String customerName,
    String? vehicleId,
    String? vehicleLabel,
  }) async {
    if (customerId.isEmpty) {
      throw StateError('Select a saved customer before creating an estimate.');
    }
    final operationId=_offlineOperationUuid();
    final id='local-estimate-$operationId';
    final now=DateTime.now();
    final date=now.toIso8601String().split('T').first;
    final detail=<String,dynamic>{
      'id':id,'kind':'estimate','document_number':null,
      'status':'draft','display_status':'Draft',
      'display_status_code':'draft',
      'job_id':null,'job_number':null,
      'customer_id':customerId,'customer_name':customerName,
      'vehicle_id':vehicleId,'vehicle':vehicleLabel,
      'document_date':date,
      'created_at':now.toIso8601String(),
      'updated_at':now.toIso8601String(),
      'memo':null,'lines':<Map<String,dynamic>>[],
      'net_amount':0,'tax_amount':0,'total_amount':0,
      'paid_amount':0,'pending_payment':0,
      'row_version':1,'converted':false,
      'sync_state':'pending','_local_snapshot':true,'_local_draft':true,
    };
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO local_documents(
          id,business_id,job_id,customer_id,kind,document_number,
          status,display_status_code,closed_at,converted,total,
          document_date,created_at,server_updated_at,row_version,sync_state
        ) VALUES (?, ?, NULL, ?, 'estimate', NULL, 'draft','draft',
                  NULL,0,0,?,?,NULL,1,'pending')
        ''',
        [id,businessId,customerId,date,_unixNow()],
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
    });
    await _cache.save(businessId,id,detail);
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

    final id = _localId();
    final now = DateTime.now();
    final detail = <String, dynamic>{
      'id': id,
      'kind': 'estimate',
      'document_number': null,
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
      await _database.customStatement(
        '''
        INSERT INTO local_documents (
          id, business_id, job_id, customer_id, kind, document_number,
          status, display_status_code, closed_at, converted, total,
          document_date, created_at, server_updated_at, row_version, sync_state
        ) VALUES (?, ?, ?, ?, 'estimate', NULL, 'draft', 'draft',
                  NULL, 0, 0, ?, ?, NULL, 1, 'pending')
        ''',
        [
          id,
          businessId,
          jobId,
          customerId,
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
          }),
          _unixNow(),
        ],
      );
    });

    await _cache.save(businessId, id, detail);
    return id;
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
  }) async {
    final detail = await _requireDraft(businessId, documentId);
    final lines = _lines(detail);
    final index =
        lines.indexWhere((line) => line['id']?.toString() == lineId);
    if (index < 0) throw StateError('The estimate line is not saved locally.');

    final netAmount = quantity * unitPrice;
    final taxAmount = netAmount * taxRate;
    lines[index] = <String, dynamic>{
      ...lines[index],
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
    if (documentId.startsWith('local-invoice-')) {
      if ((detail['_server_document_id']?.toString() ?? '').isNotEmpty) {
        throw StateError('This invoice has synced. Open the numbered invoice.');
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
        throw StateError('This invoice is no longer queued. Reopen the invoice.');
      }
      if (rows.isNotEmpty) {
        final row = rows.single;
        if (row.read<String>('state') != 'pending' ||
            row.read<int>('attempt_count') != 0 ||
            row.data['last_attempt_at'] != null) {
          throw StateError(
            'This invoice is synchronizing. Reopen it once sync finishes.',
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
    for (var i = 0; i < lines.length; i++) {
      lines[i] = <String, dynamic>{...lines[i], 'position': i + 1};
    }

    var net = 0.0;
    var tax = 0.0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line['line_kind']?.toString() == 'discount') continue;
      final amount =
          _number(line['quantity']) * _number(line['unit_price']);
      final lineTax = amount * _number(line['tax_rate']);
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

  Future<void> flush(String businessId) async {
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

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final localId = row.read<String>('entity_id');
      try {
        // Claim before sending any bytes. A delete can cancel only an
        // untouched operation; reconnect if an upload might have started.
        await _database.customStatement(
          "UPDATE sync_outbox SET state='inflight',last_attempt_at=? "
          "WHERE id=? AND state IN ('pending','inflight')",
          [_unixNow(),outboxId],
        );
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        final localDetail = await _cache.load(businessId, localId);
        if (localDetail == null) {
          throw StateError('The offline document draft is missing.');
        }

        late final String serverId;
        late Map<String, dynamic> serverDetail;
        if (payload['kind'] == 'invoice') {
          final operationId = payload['operation_id']?.toString() ?? '';
          final customerId = payload['customer_id']?.toString() ?? '';
          if (operationId.isEmpty || customerId.isEmpty) {
            throw StateError('Offline invoice is missing its sync identity.');
          }
          serverId = await _api.syncOfflineQuickInvoice(
            businessId,
            customerId: customerId,
            vehicleId: payload['vehicle_id']?.toString(),
            operationId: operationId,
            documentDate: payload['document_date']?.toString() ?? '',
            lines: _lines(localDetail),
            memo: localDetail['memo']?.toString(),
          );
          serverDetail = await _api.documentDetail(businessId,serverId);
          if ((serverDetail['job_id']?.toString() ?? '').isEmpty) {
            throw StateError('The synced invoice did not return its linked Job.');
          }
        } else {
          final jobId = payload['job_id']?.toString() ?? '';
          if (jobId.isEmpty) {
            final operationId=payload['operation_id']?.toString() ?? '';
            final customerId=payload['customer_id']?.toString() ?? '';
            if (operationId.isEmpty || customerId.isEmpty) {
              throw StateError('The offline estimate has no sync identity.');
            }
            serverId = await _api.syncOfflineStandaloneEstimate(
              businessId,
              customerId:customerId,
              vehicleId:payload['vehicle_id']?.toString(),
              operationId:operationId,
              documentDate:payload['document_date']?.toString() ?? '',
              lines:_lines(localDetail),
              memo:localDetail['memo']?.toString(),
            );
            serverDetail=await _api.documentDetail(businessId,serverId);
          } else {
          serverId = await _api.createEstimate(businessId, jobId);
          serverDetail = await _api.documentDetail(businessId, serverId);

          final lines = _lines(localDetail);
          for (final line in lines) {
            final version =
                int.tryParse(serverDetail['row_version']?.toString() ?? '') ?? 1;
            await _api.addDocumentLine(
              businessId,
              serverId,
              expectedVersion: version,
              name: line['name']?.toString() ?? 'Item',
              description: line['description']?.toString(),
              itemId: line['item_id']?.toString(),
              quantity: _number(line['quantity']),
              unitPrice: _number(line['unit_price']),
              taxRate: _number(line['tax_rate']),
              lineKind: line['line_kind']?.toString() ?? 'item',
            );
            serverDetail = await _api.documentDetail(businessId,serverId);
          }

          final memo = localDetail['memo']?.toString().trim() ?? '';
          if (memo.isNotEmpty) {
            final version =
                int.tryParse(serverDetail['row_version']?.toString() ?? '') ?? 1;
            await _api.updateDocumentNotes(
              businessId,
              serverId,
              expectedVersion: version,
              memo: memo,
            );
            serverDetail = await _api.documentDetail(businessId,serverId);
          }
          }
        }

        await _documents.upsertFromServer(
          businessId,
          [serverDetail],
        );
        await _cache.save(businessId, serverId, serverDetail);
        await _cache.save(
          businessId,
          localId,
          <String, dynamic>{
            ...serverDetail,
            '_server_document_id': serverId,
          },
        );

        if (payload['kind'] == 'estimate') {
          await _remapPendingEstimateMerges(
            businessId,
            localId,
            serverId,
          );
        }

        await _database.transaction(() async {
          if (payload['kind'] == 'invoice') {
            // Do not remove pending local Job until authoritative invoice
            // and its linked real Job are safely cached.
            final provisionalJobId =
                payload['provisional_job_id']?.toString() ?? '';
            if (provisionalJobId.isNotEmpty) {
              await _database.customStatement(
                'DELETE FROM local_job_visits WHERE business_id = ? AND job_id = ?',
                [businessId, provisionalJobId],
              );
              await _database.customStatement(
                'DELETE FROM local_jobs WHERE business_id = ? AND id = ? '
                "AND sync_state = 'pending'",
                [businessId, provisionalJobId],
              );
            }
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
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              state = 'pending',
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [_unixNow(), error.toString(), outboxId],
        );
        break;
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
