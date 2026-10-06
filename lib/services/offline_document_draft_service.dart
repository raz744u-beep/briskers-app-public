import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'local_document_repository.dart';

class OfflineDocumentDraftService {
  OfflineDocumentDraftService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentDetailCache cache = const LocalDocumentDetailCache(),
    LocalDocumentRepository? documents,
  })  : _api = api,
        _cache = cache,
        _documents = documents ?? LocalDocumentRepository();

  final BriskersApi _api;
  final LocalDocumentDetailCache _cache;
  final LocalDocumentRepository _documents;
  final Random _random = Random.secure();

  bool isLocalDraftId(String id) => id.startsWith('local-estimate-');

  int _unixNow() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  String _localId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local-estimate-$now-$salt';
  }

  String _lineId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local-line-$now-$salt';
  }

  num _number(Object? raw) =>
      num.tryParse(raw?.toString() ?? '') ?? 0;

  Future<String> createEstimate(
    String businessId,
    String jobId,
  ) async {
    final rows = await localDatabase.customSelect(
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
    final now = DateTime.now().toUtc();
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

    await localDatabase.transaction(() async {
      await localDatabase.customStatement(
        '''
        INSERT INTO local_documents (
          id, business_id, job_id, customer_id, kind, document_number,
          status, display_status_code, closed_at, converted, total,
          created_at, server_updated_at, row_version, sync_state
        ) VALUES (?, ?, ?, ?, 'estimate', NULL, 'draft', 'draft',
                  NULL, 0, 0, ?, NULL, 1, 'pending')
        ''',
        [
          id,
          businessId,
          jobId,
          customerId,
          _unixNow(),
        ],
      );
      await localDatabase.customStatement(
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
    lines.add(<String, dynamic>{
      'id': _lineId(),
      'name': name,
      'description': description,
      'item_id': itemId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'tax_rate': taxRate,
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

    lines[index] = <String, dynamic>{
      ...lines[index],
      'name': name,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'tax_rate': taxRate,
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
    for (final line in lines) {
      if (line['line_kind']?.toString() == 'discount') continue;
      final amount =
          _number(line['quantity']) * _number(line['unit_price']);
      net += amount.toDouble();
      tax += (amount * _number(line['tax_rate'])).toDouble();
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

    await localDatabase.customStatement(
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
    final rows = await localDatabase.customSelect(
      '''
      SELECT id, entity_id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'document_draft_create'
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final localId = row.read<String>('entity_id');
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        final jobId = payload['job_id']?.toString() ?? '';
        if (jobId.isEmpty) {
          throw StateError('The offline estimate has no linked job.');
        }

        final localDetail = await _cache.load(businessId, localId);
        if (localDetail == null) {
          throw StateError('The offline estimate detail is missing.');
        }

        final serverId = await _api.createEstimate(businessId, jobId);
        var serverDetail =
            await _api.documentDetail(businessId, serverId);

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
          serverDetail =
              await _api.documentDetail(businessId, serverId);
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
          serverDetail =
              await _api.documentDetail(businessId, serverId);
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

        await _remapPendingEstimateMerges(
          businessId,
          localId,
          serverId,
        );

        await localDatabase.transaction(() async {
          await localDatabase.customStatement(
            'DELETE FROM local_documents WHERE business_id = ? AND id = ?',
            [businessId, localId],
          );
          await localDatabase.customStatement(
            'DELETE FROM sync_outbox WHERE id = ?',
            [outboxId],
          );
        });
      } catch (error) {
        await localDatabase.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
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
    final rows = await localDatabase.customSelect(
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
      await localDatabase.customStatement(
        'UPDATE sync_outbox SET entity_id = ?, payload_json = ? WHERE id = ?',
        [serverId, jsonEncode(payload), row.read<int>('id')],
      );
    }
  }
}
