import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';

class OfflineEstimateInvoiceService {
  OfflineEstimateInvoiceService({
    BriskersApi api = const BriskersApi(),
    LocalDocumentDetailCache cache = const LocalDocumentDetailCache(),
  })  : _api = api,
        _cache = cache;

  final BriskersApi _api;
  final LocalDocumentDetailCache _cache;
  final Random _random = Random.secure();

  String _operationId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'estimate-merge-$now-$salt';
  }

  int _unixNow() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  num _number(Object? raw) => num.tryParse(raw?.toString() ?? '') ?? 0;

  Future<List<Map<String, dynamic>>> eligibleLocalInvoices(
    String businessId,
    Map<String, dynamic> estimate,
  ) async {
    final customerId = estimate['customer_id']?.toString() ?? '';
    final vehicleId = estimate['vehicle_id']?.toString() ?? '';
    if (customerId.isEmpty) return const [];

    final rows = await localDatabase.customSelect(
      '''
      SELECT d.*, j.job_number, j.title AS job_title,
             j.vehicle_id, j.vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id=d.business_id AND j.id=d.job_id
      WHERE d.business_id=?
        AND d.kind='invoice'
        AND d.customer_id=?
        AND d.closed_at IS NULL
        AND lower(COALESCE(d.status,''))<>'void'
      ORDER BY d.created_at DESC, d.id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();

    final result = rows.map((row) {
      final invoiceVehicleId = row.readNullable<String>('vehicle_id') ?? '';
      return <String, dynamic>{
        'id': row.read<String>('id'),
        'document_number': row.readNullable<String>('document_number'),
        'total_amount': row.read<double>('total'),
        'status': row.readNullable<String>('status'),
        'job_id': row.readNullable<String>('job_id'),
        'job_number': row.readNullable<String>('job_number'),
        'job_title': row.readNullable<String>('job_title'),
        'vehicle_id': invoiceVehicleId,
        'vehicle': row.readNullable<String>('vehicle_label'),
        'same_vehicle': vehicleId.isNotEmpty &&
            invoiceVehicleId.isNotEmpty &&
            vehicleId == invoiceVehicleId,
      };
    }).toList();

    result.sort((a, b) {
      final av = a['same_vehicle'] == true ? 0 : 1;
      final bv = b['same_vehicle'] == true ? 0 : 1;
      return av.compareTo(bv);
    });
    return result;
  }

  Future<void> mergeLocal(
    String businessId, {
    required String estimateId,
    required String invoiceId,
  }) async {
    final estimate = await _cache.load(businessId, estimateId);
    final invoice = await _cache.load(businessId, invoiceId);
    if (estimate == null) {
      throw StateError(
        'This estimate is not saved locally yet. Open it online once, then retry.',
      );
    }
    if (invoice == null) {
      throw StateError(
        'This invoice is not saved locally yet. Open it online once, then retry.',
      );
    }
    if (estimate['converted'] == true) {
      throw StateError('This estimate has already been converted.');
    }

    final estimateLines = List<dynamic>.from(
      estimate['lines'] ?? const [],
    ).whereType<Map>().map((raw) {
      return Map<String, dynamic>.from(raw);
    }).toList();
    if (estimateLines.isEmpty) {
      throw StateError('Estimate has no items.');
    }

    final invoiceLines = List<dynamic>.from(
      invoice['lines'] ?? const [],
    ).whereType<Map>().map((raw) {
      return Map<String, dynamic>.from(raw);
    }).toList();

    var maxPosition = 0;
    for (final line in invoiceLines) {
      final p = int.tryParse(line['position']?.toString() ?? '') ?? 0;
      if (p > maxPosition) maxPosition = p;
    }

    final copied = <Map<String, dynamic>>[];
    for (var index = 0; index < estimateLines.length; index++) {
      copied.add({
        ...estimateLines[index],
        'id': 'local-merged-$estimateId-$index',
        'position': maxPosition + index + 1,
      });
    }

    final newNet =
        _number(invoice['net_amount']) + _number(estimate['net_amount']);
    final newTax =
        _number(invoice['tax_amount']) + _number(estimate['tax_amount']);
    final newTotal = newNet + newTax;
    final invoiceNumber = invoice['document_number']?.toString();

    final updatedEstimate = <String, dynamic>{
      ...estimate,
      'status': 'accepted',
      'converted': true,
      'converted_invoice_id': invoiceId,
      'converted_invoice_number': invoiceNumber,
      'converted_invoice_date': invoice['document_date'],
      'sync_state': 'pending',
    };
    final updatedInvoice = <String, dynamic>{
      ...invoice,
      'lines': [...invoiceLines, ...copied],
      'net_amount': newNet,
      'tax_amount': newTax,
      'total_amount': newTotal,
      'sync_state': 'pending',
    };

    final operationId = _operationId();

    await localDatabase.transaction(() async {
      await localDatabase.customStatement(
        '''
        UPDATE local_documents
        SET status='accepted', converted=1, sync_state='pending'
        WHERE business_id=? AND id=?
        ''',
        [businessId, estimateId],
      );
      await localDatabase.customStatement(
        '''
        UPDATE local_documents
        SET total=?, sync_state='pending'
        WHERE business_id=? AND id=?
        ''',
        [newTotal.toDouble(), businessId, invoiceId],
      );
      await localDatabase.customStatement(
        '''
        INSERT INTO sync_outbox(
          business_id,entity_type,entity_id,operation,payload_json,
          base_row_version,state,attempt_count,created_at,
          last_attempt_at,last_error
        ) VALUES(
          ?,'estimate_add_to_invoice',?,'merge',?,NULL,
          'pending',0,?,NULL,NULL
        )
        ''',
        [
          businessId,
          estimateId,
          jsonEncode({
            'operation_id': operationId,
            'estimate_id': estimateId,
            'invoice_id': invoiceId,
          }),
          _unixNow(),
        ],
      );
    });

    await _cache.save(businessId, estimateId, updatedEstimate);
    await _cache.save(businessId, invoiceId, updatedInvoice);
  }

  Future<void> flush(String businessId) async {
    final rows = await localDatabase.customSelect(
      '''
      SELECT *
      FROM sync_outbox
      WHERE business_id=?
        AND entity_type='estimate_add_to_invoice'
        AND state='pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );

      try {
        final estimateId = payload['estimate_id'].toString();
        final invoiceId = payload['invoice_id'].toString();

        await _api.addEstimateToExistingInvoice(
          businessId,
          estimateId: estimateId,
          invoiceId: invoiceId,
          operationId: payload['operation_id'].toString(),
        );

        final details = await Future.wait([
          _api.documentDetail(businessId, estimateId),
          _api.documentDetail(businessId, invoiceId),
        ]);
        final estimate = details[0];
        final invoice = details[1];

        await _cache.save(businessId, estimateId, estimate);
        await _cache.save(businessId, invoiceId, invoice);

        await localDatabase.transaction(() async {
          await localDatabase.customStatement(
            '''
            UPDATE local_documents
            SET status=?, converted=1, total=?, row_version=?,
                server_updated_at=?, sync_state='synced'
            WHERE business_id=? AND id=?
            ''',
            [
              estimate['status']?.toString(),
              _number(estimate['total_amount']).toDouble(),
              int.tryParse(estimate['row_version']?.toString() ?? ''),
              _unixNow(),
              businessId,
              estimateId,
            ],
          );
          await localDatabase.customStatement(
            '''
            UPDATE local_documents
            SET status=?, total=?, row_version=?,
                server_updated_at=?, sync_state='synced'
            WHERE business_id=? AND id=?
            ''',
            [
              invoice['status']?.toString(),
              _number(invoice['total_amount']).toDouble(),
              int.tryParse(invoice['row_version']?.toString() ?? ''),
              _unixNow(),
              businessId,
              invoiceId,
            ],
          );
          await localDatabase.customStatement(
            'DELETE FROM sync_outbox WHERE id=?',
            [outboxId],
          );
        });
      } catch (error) {
        await localDatabase.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count=attempt_count+1,
              last_attempt_at=?,
              last_error=?
          WHERE id=?
          ''',
          [_unixNow(), error.toString(), outboxId],
        );
        break;
      }
    }
  }
}
