import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'local_catalog_repository.dart';

class OfflineDocumentEditService {
  OfflineDocumentEditService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentDetailCache cache = const LocalDocumentDetailCache(),
    BriskersLocalDatabase? database,
    LocalCatalogRepository? catalog,
  })  : _api = api,
        _cache = cache,
        _database = database ?? localDatabase,
        _catalog = catalog ?? LocalCatalogRepository(database: database);

  final BriskersApi _api;
  final LocalDocumentDetailCache _cache;
  final BriskersLocalDatabase _database;
  final LocalCatalogRepository _catalog;
  final Random _random = Random.secure();

  int _unixNow() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  String _localLineId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local-doc-line-$now-$salt';
  }

  num _number(Object? raw) =>
      num.tryParse(raw?.toString() ?? '') ?? 0;

  List<Map<String, dynamic>> _lines(Map<String, dynamic> detail) =>
      List<dynamic>.from(detail['lines'] ?? const <dynamic>[])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();

  Future<Map<String, dynamic>> _requireCached(
    String businessId,
    String documentId,
  ) async {
    final detail = await _cache.load(businessId, documentId);
    if (detail == null) {
      throw StateError(
        'This document is not saved locally yet. Open it online once, then retry.',
      );
    }
    if (detail['converted'] == true) {
      throw StateError('This estimate is read-only because it was converted.');
    }
    return detail;
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
    final detail = await _requireCached(businessId, documentId);
    final lines = _lines(detail);
    final localId = _localLineId();
    final netAmount = quantity * unitPrice;
    final taxAmount = netAmount * taxRate;
    lines.add(<String, dynamic>{
      'id': localId,
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
      '_local_pending': true,
    });

    await _saveDesired(businessId, documentId, detail, lines);
    await _queue(
      businessId,
      documentId,
      'add_line',
      {
        'local_line_id': localId,
        'name': name,
        'description': description,
        'item_id': itemId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'tax_rate': taxRate,
        'line_kind': lineKind,
      },
    );
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
    final detail = await _requireCached(businessId, documentId);
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
      '_local_pending': true,
    };
    await _saveDesired(businessId, documentId, detail, lines);
    await _queue(
      businessId,
      documentId,
      'update_line',
      {
        'line_id': lineId,
        'name': name,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'tax_rate': taxRate,
        'line_kind': lineKind,
      },
    );
  }

  Future<void> deleteLine(
    String businessId,
    String documentId,
    String lineId,
  ) async {
    final detail = await _requireCached(businessId, documentId);
    final lines = _lines(detail)
      ..removeWhere((line) => line['id']?.toString() == lineId);
    await _saveDesired(businessId, documentId, detail, lines);
    await _queue(
      businessId,
      documentId,
      'delete_line',
      {'line_id': lineId},
    );
  }

  Future<void> copyLine(
    String businessId,
    String documentId,
    String lineId,
  ) async {
    final detail = await _requireCached(businessId, documentId);
    final lines = _lines(detail);
    final index =
        lines.indexWhere((line) => line['id']?.toString() == lineId);
    if (index < 0) throw StateError('The estimate line is not saved locally.');

    final localId = _localLineId();
    lines.insert(
      index + 1,
      <String, dynamic>{
        ...lines[index],
        'id': localId,
        '_local_pending': true,
      },
    );
    await _saveDesired(businessId, documentId, detail, lines);
    await _queue(
      businessId,
      documentId,
      'copy_line',
      {
        'source_line_id': lineId,
        'local_line_id': localId,
      },
    );
  }

  Future<void> moveLine(
    String businessId,
    String documentId,
    String lineId,
    String direction,
  ) async {
    final detail = await _requireCached(businessId, documentId);
    final lines = _lines(detail);
    final index =
        lines.indexWhere((line) => line['id']?.toString() == lineId);
    if (index < 0) throw StateError('The estimate line is not saved locally.');

    final target = direction == 'up' ? index - 1 : index + 1;
    if (target < 0 || target >= lines.length) return;
    final line = lines.removeAt(index);
    lines.insert(target, line);
    await _saveDesired(businessId, documentId, detail, lines);
    await _queue(
      businessId,
      documentId,
      'move_line',
      {
        'line_id': lineId,
        'direction': direction,
      },
    );
  }

  Future<void> saveMemo(
    String businessId,
    String documentId,
    String? memo,
  ) async {
    final detail = await _requireCached(businessId, documentId);
    final updated = <String, dynamic>{
      ...detail,
      'memo': memo,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'pending',
    };
    await _cache.save(businessId, documentId, updated);
    await _queue(
      businessId,
      documentId,
      'memo',
      {'memo': memo},
      replaceSameOperation: true,
    );
  }

  Future<void> _saveDesired(
    String businessId,
    String documentId,
    Map<String, dynamic> detail,
    List<Map<String, dynamic>> lines,
  ) async {
    for (var index = 0; index < lines.length; index++) {
      lines[index] = <String, dynamic>{
        ...lines[index],
        'position': index + 1,
      };
    }

    var net = 0.0;
    var tax = 0.0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final kind = line['line_kind']?.toString() ?? 'item';
      if (kind == 'discount') {
        net += _number(line['net_amount']).toDouble();
        tax += _number(line['tax_amount']).toDouble();
        continue;
      }
      final quantity = _number(line['quantity']);
      final unitPrice = _number(line['unit_price']);
      final amount = quantity * unitPrice;
      final lineTax = amount * _number(line['tax_rate']);
      final lineTotal = amount + lineTax;
      lines[index] = <String, dynamic>{
        ...line,
        'net_amount': amount.toDouble(),
        'tax_amount': lineTax.toDouble(),
        'total_amount': lineTotal.toDouble(),
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

  Future<void> _queue(
    String businessId,
    String documentId,
    String operation,
    Map<String, dynamic> payload, {
    bool replaceSameOperation = false,
  }) async {
    if (replaceSameOperation) {
      final existing = await _database.customSelect(
        '''
        SELECT id
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'document_edit'
          AND entity_id = ?
          AND operation = ?
          AND state = 'pending'
        ORDER BY id DESC
        LIMIT 1
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(documentId),
          Variable<String>(operation),
        ],
      ).get();
      if (existing.isNotEmpty) {
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET payload_json = ?, last_error = NULL
          WHERE id = ?
          ''',
          [
            jsonEncode(payload),
            existing.first.read<int>('id'),
          ],
        );
        return;
      }
    }

    await _database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation, payload_json,
        state, attempt_count, created_at, last_attempt_at, last_error
      ) VALUES (?, 'document_edit', ?, ?, ?, 'pending', 0, ?, NULL, NULL)
      ''',
      [
        businessId,
        documentId,
        operation,
        jsonEncode(payload),
        _unixNow(),
      ],
    );
  }

  Future<int> repairPendingCatalogTaxes(
    String businessId,
    num defaultTaxRate,
  ) async {
    if (defaultTaxRate <= 0) return 0;

    final catalogItems = await _catalog.items(
      businessId,
      includeInactive: true,
    );
    final taxableById = <String, bool>{
      for (final item in catalogItems)
        if ((item['id']?.toString() ?? '').isNotEmpty)
          item['id'].toString(): item['taxable'] == true,
    };

    final pendingRows = await _database.customSelect(
      '''
      SELECT DISTINCT entity_id
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'document_edit'
        AND state = 'pending'
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    var repaired = 0;
    for (final row in pendingRows) {
      final documentId = row.read<String>('entity_id');
      final detail = await _cache.load(businessId, documentId);
      if (detail == null) continue;

      final lines = _lines(detail);
      final repairedIds = <String>{};
      var changed = false;

      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line['_local_pending'] != true) continue;
        final itemId = line['item_id']?.toString() ?? '';
        if (itemId.isEmpty || taxableById[itemId] != true) continue;
        if (_number(line['tax_rate']) > 0) continue;

        final quantity = _number(line['quantity']);
        final unitPrice = _number(line['unit_price']);
        final netAmount = quantity * unitPrice;
        final taxAmount = netAmount * defaultTaxRate;
        final lineId = line['id']?.toString() ?? '';

        lines[index] = <String, dynamic>{
          ...line,
          'tax_rate': defaultTaxRate,
          'net_amount': netAmount,
          'tax_amount': taxAmount,
        };
        if (lineId.isNotEmpty) repairedIds.add(lineId);
        repaired++;
        changed = true;
      }

      if (!changed) continue;
      await _saveDesired(businessId, documentId, detail, lines);

      final queued = await _database.customSelect(
        '''
        SELECT id, operation, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'document_edit'
          AND entity_id = ?
          AND state = 'pending'
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(documentId),
        ],
      ).get();

      for (final queuedRow in queued) {
        Map<String, dynamic> payload;
        try {
          payload = Map<String, dynamic>.from(
            jsonDecode(queuedRow.read<String>('payload_json')) as Map,
          );
        } catch (_) {
          continue;
        }
        final operation = queuedRow.read<String>('operation');
        final targetId = operation == 'add_line'
            ? payload['local_line_id']?.toString() ?? ''
            : payload['line_id']?.toString() ?? '';
        if (!repairedIds.contains(targetId)) continue;
        payload['tax_rate'] = defaultTaxRate;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json = ?, last_error = NULL WHERE id = ?',
          [jsonEncode(payload), queuedRow.read<int>('id')],
        );
      }
    }

    return repaired;
  }

  Future<void> flush(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'document_edit'
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    final documentIds = <String>[];
    for (final row in rows) {
      final id = row.read<String>('entity_id');
      if (!documentIds.contains(id)) documentIds.add(id);
    }

    for (final documentId in documentIds) {
      final pending = rows
          .where((row) => row.read<String>('entity_id') == documentId)
          .toList();
      try {
        await _flushDocument(
          businessId,
          documentId,
          pending,
        );
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _flushDocument(
    String businessId,
    String documentId,
    List<QueryRow> rows,
  ) async {
    Map<String, dynamic> serverDetail =
        await _api.documentDetail(businessId, documentId);

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final operation = row.read<String>('operation');
      var payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );

      try {
        payload = await _refreshPayload(outboxId, payload);
        final version =
            int.tryParse(serverDetail['row_version']?.toString() ?? '') ?? 1;

        if (operation == 'add_line') {
          final beforeIds = _serverLineIds(serverDetail);
          await _api.addDocumentLine(
            businessId,
            documentId,
            expectedVersion: version,
            name: payload['name']?.toString() ?? 'Item',
            description: payload['description']?.toString(),
            itemId: payload['item_id']?.toString(),
            quantity: _number(payload['quantity']),
            unitPrice: _number(payload['unit_price']),
            taxRate: _number(payload['tax_rate']),
            lineKind: payload['line_kind']?.toString() ?? 'item',
          );
          serverDetail = await _api.documentDetail(businessId, documentId);
          final serverLineId = _findAddedLine(
            beforeIds,
            serverDetail,
            payload,
          );
          final localLineId = payload['local_line_id']?.toString() ?? '';
          if (localLineId.isNotEmpty && serverLineId.isNotEmpty) {
            await _remapLineId(
              businessId,
              documentId,
              localLineId,
              serverLineId,
            );
          }
        } else if (operation == 'update_line') {
          await _api.updateDocumentLineV2(
            businessId,
            payload['line_id'].toString(),
            expectedVersion: version,
            name: payload['name']?.toString() ?? 'Item',
            quantity: _number(payload['quantity']),
            unitPrice: _number(payload['unit_price']),
            taxRate: _number(payload['tax_rate']),
            description: payload['description']?.toString(),
            lineKind: payload['line_kind']?.toString() ?? 'item',
          );
          serverDetail = await _api.documentDetail(businessId, documentId);
        } else if (operation == 'delete_line') {
          await _api.deleteDocumentLine(
            businessId,
            payload['line_id'].toString(),
            expectedVersion: version,
          );
          serverDetail = await _api.documentDetail(businessId, documentId);
        } else if (operation == 'copy_line') {
          final beforeIds = _serverLineIds(serverDetail);
          var serverLineId = await _api.copyDocumentLine(
            businessId,
            payload['source_line_id'].toString(),
            expectedVersion: version,
          );
          serverDetail = await _api.documentDetail(businessId, documentId);
          if (serverLineId.isEmpty) {
            serverLineId = _findAddedLine(
              beforeIds,
              serverDetail,
              const <String, dynamic>{},
            );
          }
          final localLineId = payload['local_line_id']?.toString() ?? '';
          if (localLineId.isNotEmpty && serverLineId.isNotEmpty) {
            await _remapLineId(
              businessId,
              documentId,
              localLineId,
              serverLineId,
            );
          }
        } else if (operation == 'move_line') {
          await _api.moveDocumentLine(
            businessId,
            payload['line_id'].toString(),
            expectedVersion: version,
            direction: payload['direction']?.toString() ?? 'down',
          );
          serverDetail = await _api.documentDetail(businessId, documentId);
        } else if (operation == 'memo') {
          await _api.updateDocumentNotes(
            businessId,
            documentId,
            expectedVersion: version,
            memo: payload['memo']?.toString(),
          );
          serverDetail = await _api.documentDetail(businessId, documentId);
        }

        await _database.customStatement(
          'DELETE FROM sync_outbox WHERE id = ?',
          [outboxId],
        );
      } catch (error) {
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [_unixNow(), error.toString(), outboxId],
        );
        rethrow;
      }
    }

    await _cache.save(businessId, documentId, serverDetail);
    await _database.customStatement(
      '''
      UPDATE local_documents
      SET status = ?, total = ?, row_version = ?,
          server_updated_at = ?, sync_state = 'synced'
      WHERE business_id = ? AND id = ?
      ''',
      [
        serverDetail['status']?.toString(),
        _number(serverDetail['total_amount']).toDouble(),
        int.tryParse(serverDetail['row_version']?.toString() ?? ''),
        _unixNow(),
        businessId,
        documentId,
      ],
    );
  }

  Future<Map<String, dynamic>> _refreshPayload(
    int outboxId,
    Map<String, dynamic> fallback,
  ) async {
    final rows = await _database.customSelect(
      'SELECT payload_json FROM sync_outbox WHERE id = ? LIMIT 1',
      variables: [Variable<int>(outboxId)],
    ).get();
    if (rows.isEmpty) return fallback;
    return Map<String, dynamic>.from(
      jsonDecode(rows.first.read<String>('payload_json')) as Map,
    );
  }

  Set<String> _serverLineIds(Map<String, dynamic> detail) =>
      _lines(detail)
          .map((line) => line['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

  String _findAddedLine(
    Set<String> beforeIds,
    Map<String, dynamic> detail,
    Map<String, dynamic> payload,
  ) {
    final candidates = _lines(detail)
        .where((line) {
          final id = line['id']?.toString() ?? '';
          return id.isNotEmpty && !beforeIds.contains(id);
        })
        .toList();
    if (candidates.length == 1) {
      return candidates.first['id']?.toString() ?? '';
    }

    for (final line in candidates.reversed) {
      final nameMatches = payload.isEmpty ||
          line['name']?.toString() == payload['name']?.toString();
      final kindMatches = payload.isEmpty ||
          line['line_kind']?.toString() ==
              (payload['line_kind']?.toString() ?? 'item');
      final quantityMatches = payload.isEmpty ||
          (_number(line['quantity']) - _number(payload['quantity'])).abs() <
              0.0001;
      final priceMatches = payload.isEmpty ||
          (_number(line['unit_price']) - _number(payload['unit_price'])).abs() <
              0.0001;
      if (nameMatches && kindMatches && quantityMatches && priceMatches) {
        return line['id']?.toString() ?? '';
      }
    }
    return '';
  }

  Future<void> _remapLineId(
    String businessId,
    String documentId,
    String localId,
    String serverId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'document_edit'
        AND entity_id = ?
        AND state = 'pending'
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(documentId),
      ],
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

      var changed = false;
      for (final key in const ['line_id', 'source_line_id']) {
        if (payload[key]?.toString() == localId) {
          payload[key] = serverId;
          changed = true;
        }
      }
      if (changed) {
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json = ? WHERE id = ?',
          [jsonEncode(payload), row.read<int>('id')],
        );
      }
    }

    final cached = await _cache.load(businessId, documentId);
    if (cached == null) return;
    final lines = _lines(cached);
    var changed = false;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index]['id']?.toString() == localId) {
        lines[index] = <String, dynamic>{
          ...lines[index],
          'id': serverId,
        };
        changed = true;
      }
    }
    if (changed) {
      await _cache.save(
        businessId,
        documentId,
        <String, dynamic>{...cached, 'lines': lines},
      );
    }
  }
}
