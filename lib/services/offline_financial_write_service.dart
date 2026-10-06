import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_financial_cache.dart';

class OfflineFinancialWriteService {
  OfflineFinancialWriteService({
    BriskersApi api = const BriskersApi(),
    LocalFinancialCache? cache,
  })  : _api = api,
        _cache = cache ?? LocalFinancialCache();

  final BriskersApi _api;
  final LocalFinancialCache _cache;
  final Random _random = Random.secure();

  String _operationId(String prefix) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return '$prefix-$now-$salt';
  }

  int _unixNow() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  Future<void> _enqueue(
    String businessId,
    String type,
    String entityId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    await localDatabase.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, base_row_version, state, attempt_count,
        created_at, last_attempt_at, last_error
      ) VALUES (?, ?, ?, ?, ?, NULL, 'pending', 0, ?, NULL, NULL)
      ''',
      [
        businessId,
        type,
        entityId,
        operation,
        jsonEncode(payload),
        _unixNow(),
      ],
    );
  }

  Future<File> _stageReceipt(
    String businessId,
    String transactionId,
    String filename,
    Uint8List bytes,
  ) async {
    final root = await getApplicationSupportDirectory();
    final op = _operationId('receipt');
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 && filename.length - dot <= 8
        ? filename.substring(dot).toLowerCase()
        : '.img';
    final dir = Directory(
      '${root.path}/briskers_media/$businessId/expenses/$transactionId',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$op$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<Map<String, dynamic>>> _allTransactions(
    String businessId,
  ) {
    return _cache.loadTransactions(businessId);
  }

  Future<void> _upsertSummary(
    String businessId,
    Map<String, dynamic> row,
  ) async {
    final rows = await _allTransactions(businessId);
    final id = row['id']?.toString() ?? '';
    final index = rows.indexWhere((item) => item['id']?.toString() == id);
    if (index >= 0) {
      rows[index] = {...rows[index], ...row};
    } else {
      rows.insert(0, row);
    }
    rows.sort((a, b) {
      final ad = a['transaction_date']?.toString() ?? '';
      final bd = b['transaction_date']?.toString() ?? '';
      return bd.compareTo(ad);
    });
    await _cache.saveTransactions(businessId, rows);
  }

  Future<Map<String, dynamic>> createLocalTransaction(
    String businessId, {
    required String direction,
    required String accountId,
    required String accountName,
    required String categoryId,
    required String categoryName,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
    String? contextLabel,
    required List<Map<String, dynamic>> receipts,
  }) async {
    final operationId = _operationId('financial-create');
    final localId = 'local-transaction-$operationId';
    final attachments = <Map<String, dynamic>>[];

    await localDatabase.transaction(() async {
      await _enqueue(
        businessId,
        'financial_create',
        localId,
        'create',
        {
          'operation_id': operationId,
          'local_transaction_id': localId,
          'direction': direction,
          'account_id': accountId,
          'category_id': categoryId,
          'amount': amount,
          'date': date.toIso8601String(),
          'job_id': jobId,
          'document_id': documentId,
          'counterparty_id': counterpartyId,
          'counterparty_name': counterpartyName,
          'remarks': remarks,
        },
      );

      for (final receipt in receipts) {
        final filename =
            receipt['filename']?.toString() ?? 'receipt.jpg';
        final mimeType =
            receipt['mime_type']?.toString() ?? 'image/jpeg';
        final bytes = receipt['bytes'] as Uint8List;
        final file = await _stageReceipt(
          businessId,
          localId,
          filename,
          bytes,
        );
        final photoOperationId = _operationId('financial-photo');
        final localPhotoId = 'local-receipt-$photoOperationId';

        attachments.add({
          'attachment_id': localPhotoId,
          'id': localPhotoId,
          'filename': filename,
          'mime_type': mimeType,
          'byte_size': bytes.length,
          'local_file_path': file.path,
          'upload_state': 'pending',
        });

        await _enqueue(
          businessId,
          'financial_photo',
          localPhotoId,
          'upload',
          {
            'operation_id': photoOperationId,
            'transaction_id': localId,
            'filename': filename,
            'mime_type': mimeType,
            'local_file_path': file.path,
          },
        );
      }
    });

    final cleanCounterparty =
        (counterpartyName ?? '').trim().isEmpty
            ? (direction == 'income' ? 'Income' : 'Expense')
            : counterpartyName!.trim();
    final dateText = date.toIso8601String().split('T').first;
    final contextParts = (contextLabel ?? '').split(' • ');
    String? jobNumber;
    String? documentNumber;
    for (final part in contextParts) {
      if (part.startsWith('Job ')) jobNumber = part.substring(4);
      if (part.startsWith('Invoice #')) {
        documentNumber = part.substring('Invoice #'.length);
      }
    }

    final summary = <String, dynamic>{
      'id': localId,
      'direction': direction,
      'amount': amount,
      'signed_amount': direction == 'expense' ? -amount : amount,
      'transaction_date': dateText,
      'counterparty': cleanCounterparty,
      'category': categoryName,
      'category_id': categoryId,
      'account': accountName,
      'account_id': accountId,
      'remarks': remarks ?? '',
      'job_id': jobId,
      'job_number': jobNumber,
      'document_id': documentId,
      'document_number': documentNumber,
      'receipt_count': attachments.length,
      'recurring': false,
      'sync_state': 'pending',
    };
    await _upsertSummary(businessId, summary);

    final detail = <String, dynamic>{
      ...summary,
      'date': dateText,
      'counterparty_id': counterpartyId,
      'editable': true,
      'deletable': false,
      'attachments': attachments,
    };
    await _cache.saveTransactionDetail(
      businessId,
      localId,
      detail,
    );
    return detail;
  }

  Future<Map<String, dynamic>> updateLocalTransaction(
    String businessId,
    String transactionId, {
    required String direction,
    required String accountId,
    required String accountName,
    required String categoryId,
    required String categoryName,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
    String? contextLabel,
  }) async {
    final dateText = date.toIso8601String().split('T').first;
    final cleanCounterparty =
        (counterpartyName ?? '').trim().isEmpty
            ? (direction == 'income' ? 'Income' : 'Expense')
            : counterpartyName!.trim();

    final existing =
        await _cache.loadTransactionDetail(businessId, transactionId) ??
            <String, dynamic>{};

    final summary = <String, dynamic>{
      'id': transactionId,
      'direction': direction,
      'amount': amount,
      'signed_amount': direction == 'expense' ? -amount : amount,
      'transaction_date': dateText,
      'counterparty': cleanCounterparty,
      'counterparty_id': counterpartyId,
      'category': categoryName,
      'category_id': categoryId,
      'account': accountName,
      'account_id': accountId,
      'remarks': remarks ?? '',
      'job_id': jobId,
      'document_id': documentId,
      'receipt_count': List<dynamic>.from(
        existing['attachments'] ?? const [],
      ).length,
      'recurring': false,
      'sync_state': 'pending',
    };
    await _upsertSummary(businessId, summary);

    final detail = <String, dynamic>{
      ...existing,
      ...summary,
      'date': dateText,
      'editable': true,
      'deletable': false,
    };
    await _cache.saveTransactionDetail(
      businessId,
      transactionId,
      detail,
    );

    final pendingCreate = await localDatabase.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'financial_create'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(transactionId),
      ],
    ).get();

    final payload = <String, dynamic>{
      'direction': direction,
      'account_id': accountId,
      'category_id': categoryId,
      'amount': amount,
      'date': date.toIso8601String(),
      'job_id': jobId,
      'document_id': documentId,
      'counterparty_id': counterpartyId,
      'counterparty_name': counterpartyName,
      'remarks': remarks,
    };

    if (pendingCreate.isNotEmpty) {
      final row = pendingCreate.first;
      final existingPayload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      existingPayload.addAll(payload);
      await localDatabase.customStatement(
        'UPDATE sync_outbox SET payload_json = ?, last_error = NULL WHERE id = ?',
        [jsonEncode(existingPayload), row.read<int>('id')],
      );
    } else {
      await _enqueue(
        businessId,
        'financial_update',
        transactionId,
        'update',
        {
          'transaction_id': transactionId,
          ...payload,
        },
      );
    }

    return detail;
  }

  Future<void> flush(String businessId) async {
    final rows = await localDatabase.customSelect(
      '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ?
        AND state = 'pending'
        AND entity_type IN (
          'financial_create',
          'financial_update',
          'financial_photo'
        )
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final type = row.read<String>('entity_type');
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );

      try {
        if (type == 'financial_create') {
          await _flushCreate(businessId, outboxId, payload);
        } else if (type == 'financial_update') {
          await _flushUpdate(businessId, outboxId, payload);
        } else if (type == 'financial_photo') {
          await _flushPhoto(businessId, outboxId, payload);
        }
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

  Future<void> _flushCreate(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final localId = payload['local_transaction_id'].toString();
    final response = await _api.syncCreateManualTransaction(
      businessId,
      operationId: payload['operation_id'].toString(),
      direction: payload['direction'].toString(),
      accountId: payload['account_id'].toString(),
      categoryId: payload['category_id'].toString(),
      amount: num.parse(payload['amount'].toString()),
      date: DateTime.parse(payload['date'].toString()),
      jobId: payload['job_id']?.toString(),
      documentId: payload['document_id']?.toString(),
      counterpartyId: payload['counterparty_id']?.toString(),
      counterpartyName: payload['counterparty_name']?.toString(),
      remarks: payload['remarks']?.toString(),
    );
    final serverId = response['transaction_id']?.toString() ?? '';
    if (serverId.isEmpty) {
      throw StateError('Server did not return a transaction ID.');
    }

    final rows = await _allTransactions(businessId);
    final index = rows.indexWhere(
      (item) => item['id']?.toString() == localId,
    );
    if (index >= 0) {
      rows[index] = {
        ...rows[index],
        'id': serverId,
        'sync_state': 'pending',
      };
      await _cache.saveTransactions(businessId, rows);
    }

    final detail =
        await _cache.loadTransactionDetail(businessId, localId);
    if (detail != null) {
      await _cache.saveTransactionDetail(
        businessId,
        serverId,
        {
          ...detail,
          'id': serverId,
          'sync_state': 'pending',
        },
      );
    }

    final photos = await localDatabase.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'financial_photo'
        AND state = 'pending'
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final photoRow in photos) {
      final photoPayload = Map<String, dynamic>.from(
        jsonDecode(photoRow.read<String>('payload_json')) as Map,
      );
      if (photoPayload['transaction_id']?.toString() != localId) continue;
      photoPayload['transaction_id'] = serverId;
      await localDatabase.customStatement(
        'UPDATE sync_outbox SET payload_json = ? WHERE id = ?',
        [jsonEncode(photoPayload), photoRow.read<int>('id')],
      );
    }

    await localDatabase.customStatement(
      'DELETE FROM sync_outbox WHERE id = ?',
      [outboxId],
    );
  }

  Future<void> _flushUpdate(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final transactionId = payload['transaction_id'].toString();
    await _api.updateManualTransaction(
      businessId,
      transactionId,
      direction: payload['direction'].toString(),
      accountId: payload['account_id'].toString(),
      categoryId: payload['category_id'].toString(),
      amount: num.parse(payload['amount'].toString()),
      date: DateTime.parse(payload['date'].toString()),
      jobId: payload['job_id']?.toString(),
      documentId: payload['document_id']?.toString(),
      counterpartyId: payload['counterparty_id']?.toString(),
      counterpartyName: payload['counterparty_name']?.toString(),
      remarks: payload['remarks']?.toString(),
    );
    await localDatabase.customStatement(
      'DELETE FROM sync_outbox WHERE id = ?',
      [outboxId],
    );
  }

  Future<void> _flushPhoto(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final transactionId = payload['transaction_id']?.toString() ?? '';
    if (transactionId.startsWith('local-transaction-')) {
      return;
    }

    final file = File(payload['local_file_path'].toString());
    final bytes = await file.readAsBytes();
    final registration = await _api.syncRegisterExpensePhoto(
      businessId,
      transactionId,
      operationId: payload['operation_id'].toString(),
      filename: payload['filename'].toString(),
      mimeType: payload['mime_type'].toString(),
    );

    await _api.uploadRegisteredAttachment(
      businessId,
      bucket: registration['bucket'].toString(),
      key: registration['key'].toString(),
      attachmentId: registration['attachment_id'].toString(),
      mimeType: payload['mime_type'].toString(),
      bytes: bytes,
    );

    await localDatabase.customStatement(
      'DELETE FROM sync_outbox WHERE id = ?',
      [outboxId],
    );
  }
}
