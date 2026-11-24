import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_job_quarantine.dart';
import 'local_financial_cache.dart';
import 'local_employee_reports.dart';
import 'local_owner_authorization.dart';
import 'local_financial_totals_journal.dart';
import 'payroll_expense_link_store.dart';
import 'payroll_expense_identity.dart';

typedef FinancialMediaDirectoryProvider = Future<Directory> Function();

class OfflineFinancialWriteService {
  OfflineFinancialWriteService({
    BriskersApi api = const BriskersApi(),
    LocalFinancialCache? cache,
    BriskersLocalDatabase? database,
    FinancialMediaDirectoryProvider? mediaDirectoryProvider,
  }) : _api = api,
       _database = database ?? localDatabase,
       _cache = cache ?? LocalFinancialCache(database: database),
       _mediaDirectoryProvider =
           mediaDirectoryProvider ?? getApplicationSupportDirectory;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final LocalFinancialCache _cache;
  final FinancialMediaDirectoryProvider _mediaDirectoryProvider;
  final Random _random = Random.secure();

  /// Local JSON projection of the existing receipt-details and receipt-items
  /// records. Stored in the same SQLite transaction as the expense and queue.
  Map<String, dynamic> _receiptProjection(
    String transactionId,
    Map<String, dynamic> extraction,
  ) {
    final parts = <Map<String, dynamic>>[];
    final raw = extraction['items'];
    if (raw is List) {
      for (final row in raw) {
        if (row is! Map) continue;
        parts.add(<String, dynamic>{
          'transaction_id': transactionId,
          'position': parts.length + 1,
          'description': row['description'],
          'sku': row['sku'],
          'quantity': row['quantity'],
          'unit_price': row['unit_price'],
          'total_amount': row['total_amount'],
        });
      }
    }
    return <String, dynamic>{
      'receipt_extraction': extraction,
      'receipt_details': <String, dynamic>{
        'transaction_id': transactionId,
        'vendor_invoice_number': extraction['vendor_invoice_number'],
        'receipt_date': extraction['receipt_date'],
        'receipt_total': extraction['receipt_total'],
        'item_summary': parts
            .map((row) => row['description']?.toString() ?? '')
            .where((text) => text.trim().isNotEmpty)
            .take(10)
            .join(', '),
        'extraction_source':
            extraction['extraction_source'] ?? 'existing_online_receipt_ai',
        'raw_data': extraction['raw_data'] ?? <String, dynamic>{},
      },
      'receipt_items': parts,
    };
  }

  Future<void> _enqueueReceiptExtraction(
    String businessId,
    String transactionId,
    Map<String, dynamic> extraction,
  ) async {
    if (extraction['review_confirmed'] != true) return;
    // Collapse queued review revisions: one authoritative set per expense.
    await _database.customStatement(
      "DELETE FROM sync_outbox WHERE business_id = ? "
      "AND entity_type = 'financial_receipt_extraction' "
      "AND entity_id = ? AND state = 'pending'",
      [businessId, transactionId],
    );
    await _enqueue(
      businessId,
      'financial_receipt_extraction',
      transactionId,
      'apply',
      <String, dynamic>{
        'transaction_id': transactionId,
        'extraction': extraction,
      },
    );
  }

  String _operationId(String prefix) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return '$prefix-$now-$salt';
  }

  int _unixNow() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  Future<void> _enqueue(
    String businessId,
    String type,
    String entityId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    await _database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, base_row_version, state, attempt_count,
        created_at, last_attempt_at, last_error
      ) VALUES (?, ?, ?, ?, ?, NULL, 'pending', 0, ?, NULL, NULL)
      ''',
      [businessId, type, entityId, operation, jsonEncode(payload), _unixNow()],
    );
  }

  Future<File> _stageReceipt(
    String businessId,
    String transactionId,
    String filename,
    Uint8List bytes,
  ) async {
    final root = await _mediaDirectoryProvider();
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

  Future<List<Map<String, dynamic>>> _queueReceipts(
    String businessId,
    String transactionId,
    List<Map<String, dynamic>> receipts,
  ) async {
    final attachments = <Map<String, dynamic>>[];
    for (final receipt in receipts) {
      final filename = receipt['filename']?.toString() ?? 'receipt.jpg';
      final mimeType = receipt['mime_type']?.toString() ?? 'image/jpeg';
      final bytes = receipt['bytes'] as Uint8List;
      final file = await _stageReceipt(
        businessId,
        transactionId,
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

      await _enqueue(businessId, 'financial_photo', localPhotoId, 'upload', {
        'operation_id': photoOperationId,
        'transaction_id': transactionId,
        'filename': filename,
        'mime_type': mimeType,
        'local_file_path': file.path,
      });
    }
    return attachments;
  }

  Future<List<Map<String, dynamic>>> _allTransactions(String businessId) async {
    final rows = await _cache.loadTransactions(businessId);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: true);
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
    Map<String, dynamic>? receiptExtraction,
    String? verifiedPayrollOperationId,
    String? copySourceId,
    String? payrollEmployeeId,
  }) async {
    final payrollOperation = verifiedPayrollOperationId?.trim();
    if (payrollEmployeeId != null &&
        (direction != 'expense' || categoryName.trim().toLowerCase() != 'payroll' ||
          payrollEmployeeId.trim().isEmpty || counterpartyId != null ||
          (counterpartyName?.trim().isEmpty ?? true))) {
      throw ArgumentError('Select a saved employee for the Payroll expense.');
    }
    if (copySourceId != null && verifiedPayrollOperationId != null) {
      throw ArgumentError('A payroll expense cannot be copied.');
    }
    if (verifiedPayrollOperationId != null &&
        (payrollOperation == null || payrollOperation.isEmpty ||
         direction != 'expense' || amount <= 0 || receipts.isNotEmpty ||
         receiptExtraction != null)) {
      throw ArgumentError('Invalid verified payroll expense projection.');
    }
    final operationId = payrollOperation == null
        ? _operationId('financial-create')
        : PayrollExpenseIdentity.expenseCreateOperation(businessId, payrollOperation);
    final localId = payrollOperation == null
        ? 'local-transaction-$operationId'
        : PayrollExpenseIdentity.transactionId(businessId, payrollOperation);
    final attachments = <Map<String, dynamic>>[];
    String? payrollMethod;

    return _database.transaction(() async {
      if (payrollOperation != null) {
        final existing = await PayrollExpenseLinkStore(_database)
            .transactionId(businessId, payrollOperation);
        if (existing != null) {
          final saved = await _cache.loadTransactionDetail(businessId, existing);
          if (saved == null ||
              saved['payroll_operation_id'] != payrollOperation ||
              saved['direction'] != 'expense' ||
              saved['amount'] is! num ||
              ((saved['amount'] as num) * 100).round() !=
                  (amount * 100).round()) {
            throw StateError('Linked payroll expense requires reconciliation.');
          }
          return saved;
        }
        // A caller cannot create a "payroll" expense from an unverified
        // draft or arbitrary amount: require the immutable payroll receipt.
        final receipts = await _database.customSelect(
          'SELECT net, method, verified_date FROM regular_payroll_payments '
          'WHERE business_id=? AND operation_id=?',
          variables: [
            Variable<String>(businessId),
            Variable<String>(payrollOperation),
          ],
        ).get();
        if (receipts.length != 1 ||
            receipts.single.read<int>('net') != (amount * 100).round() ||
            receipts.single.read<String>('verified_date') !=
                date.toIso8601String().split('T').first) {
          throw StateError('Verified payroll settlement does not match expense.');
        }
        payrollMethod = receipts.single.read<String>('method');
      }
      await _enqueue(businessId, 'financial_create', localId, 'create', {
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
      });

      attachments.addAll(await _queueReceipts(businessId, localId, receipts));
      if (receiptExtraction != null) {
        await _enqueueReceiptExtraction(businessId, localId, receiptExtraction);
      }

      final cleanCounterparty = (counterpartyName ?? '').trim().isEmpty
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

      final copyNumber = copySourceId == null
          ? null : await _cache.recordTransactionCopy(businessId, copySourceId, localId);
      final summary = <String, dynamic>{
        'id': localId,
        'direction': direction,
        'amount': amount,
        'signed_amount': direction == 'expense' ? -amount : amount,
        'transaction_date': dateText,
        'counterparty': cleanCounterparty,
        'employee_id': ?payrollEmployeeId,
        'copy_number': ?copyNumber,
        'counterparty_id': counterpartyId,
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
        if (payrollOperation != null) ...{
          'payroll_operation_id': payrollOperation,
          'payment_method': payrollMethod,
        },
      };
      await _upsertSummary(businessId, summary);
      // Financial projection is committed atomically with the queue and local
      // summary. A failed SQLite write rolls back all three.
      await LocalFinancialTotalsJournal(database: _database)
          .record(businessId, 'transaction:$localId', after: summary);

      final detail = <String, dynamic>{
        ...summary,
        'date': dateText,
        'counterparty_id': counterpartyId,
        'editable': true,
        'deletable': false,
        'attachments': attachments,
        if (receiptExtraction != null)
          ..._receiptProjection(localId, receiptExtraction),
      };
      await _cache.saveTransactionDetail(businessId, localId, detail);
      if (payrollOperation != null) {
        await PayrollExpenseLinkStore(_database)
            .link(businessId, payrollOperation, localId);
      }
      return detail;
    });
  }

  /// Replays only receipts queued by the verified payroll commit. Historical
  /// settlements require separate reconciliation against original expenses.
  Future<void> materializePendingPayrollExpenses(String businessId) async {
    await _database.transaction(() async {
      await PayrollExpenseLinkStore(_database).preparePending();
      final pending = await _database.customSelect(
        'SELECT operation_id FROM payroll_expense_projection_pending_v1 '
        'WHERE business_id = ? ORDER BY operation_id',
        variables: [Variable(businessId)],
      ).get();
      if (pending.isEmpty) return;
      final options = await _cache.loadOptions(businessId);
      List<Map<String, dynamic>> choices(String key) =>
          (options[key] as List? ?? const []).whereType<Map>()
              .map(Map<String, dynamic>.from).toList();
      final accounts = choices('accounts');
      final accountId = PayrollExpenseIdentity.uniqueOptionId(
        accounts, 'Business Checking - 9858',
      );
      final categoryId = PayrollExpenseIdentity.uniqueOptionId(
        choices('categories'), 'Payroll',
      );
      if (accountId == null || categoryId == null) return;
      final accountName = accounts.singleWhere((row) => row['id'] == accountId)['name'];
      for (final row in pending) {
        final operation = row.read<String>('operation_id');
        final payment = await _database.customSelect(
          'SELECT p.*, e.name AS employee_name FROM regular_payroll_payments p '
          'JOIN regular_payroll_employees e ON e.business_id = p.business_id '
          'AND e.id = p.employee_id WHERE p.business_id = ? AND p.operation_id = ?',
          variables: [Variable(businessId), Variable(operation)],
        ).getSingleOrNull();
        if (payment == null) continue;
        try {
          final existing = await _cache.loadTransactions(businessId, direction: 'expense');
          final match = PayrollExpenseIdentity.classify(
            businessId: businessId, payment: payment.data, existingExpenses: existing,
          );
          if (match == PayrollExpenseDecision.review) continue;
          if (match == PayrollExpenseDecision.alreadyLinked) {
            final expected = PayrollExpenseIdentity.transactionId(businessId, operation);
            final row = existing.singleWhere((row) =>
                row['payroll_operation_id'] == operation || row['id'] == expected);
            if ((row['transaction_date'] ?? row['date']) != payment.data['verified_date']) continue;
            await PayrollExpenseLinkStore(_database)
                .link(businessId, operation, row['id'] as String);
          } else {
            final projection = PayrollExpenseIdentity.expenseProjection(
              businessId: businessId,
              payment: payment.data,
              employeeName: payment.read<String>('employee_name'),
              accountId: accountId,
              categoryId: categoryId,
            );
            await createLocalTransaction(
              businessId,
              direction: 'expense',
              accountId: accountId,
              accountName: accountName as String,
              categoryId: categoryId,
              categoryName: 'Payroll',
              amount: projection['amount'] as num,
              date: DateTime.parse(projection['date'] as String),
              counterpartyName: projection['counterparty'] as String,
              remarks: projection['remarks'] as String,
              receipts: const [],
              verifiedPayrollOperationId: operation,
            );
          }
        } on StateError {
          // Keep this payout for review and continue with the other saved payouts.
          continue;
        }
        await _database.customStatement(
          'DELETE FROM payroll_expense_projection_pending_v1 '
          'WHERE business_id = ? AND operation_id = ?',
          [businessId, operation],
        );
      }
    });
  }

  /// The ledger calls this inside the amount correction transaction.
  Future<void> editPayrollExpenseAmount(
    String businessId,
    String operation, {
    required int previous,
    required int net,
    required String verifiedDate,
    required int revision,
  }) async {
    final id = await PayrollExpenseLinkStore(_database).transactionId(businessId, operation);
    final detail = id == null ? null : await _cache.loadTransactionDetail(businessId, id);
    final amount = num.tryParse(detail?['amount']?.toString() ?? '');
    if (id == null || detail == null || detail['payroll_operation_id'] != operation ||
        detail['direction'] != 'expense' || detail['sync_state'] == 'reversed' ||
        amount == null || (amount * 100).round() != previous ||
        (detail['transaction_date'] ?? detail['date']) != verifiedDate) {
      throw StateError('Review the linked expense before editing this payment.');
    }

    final local = id == PayrollExpenseIdentity.transactionId(businessId, operation);
    if (local) {
      final create = await _database.customSelect(
        'SELECT id,payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? '
        "AND entity_type='financial_create' AND state='pending' AND last_attempt_at IS NULL AND attempt_count=0",
        variables: [Variable(businessId), Variable(id)],
      ).getSingleOrNull();
      if (create == null) {
        throw StateError('Verify the expense synchronization result before editing this payment.');
      }
      final payload = Map<String, dynamic>.from(jsonDecode(create.read<String>('payload_json')) as Map);
      if (payload['operation_id'] != PayrollExpenseIdentity.expenseCreateOperation(businessId, operation) ||
          ((payload['amount'] as num) * 100).round() != previous) {
        throw StateError('The queued expense does not match the original payment.');
      }
      payload['amount'] = net / 100;
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json=? WHERE id=?',
        [jsonEncode(payload), create.read<int>('id')],
      );
    } else {
      await _enqueue(businessId, 'financial_update', id, 'update', {
        'payroll_amount_revision': revision,
        'transaction_id': id,
        'payroll_operation': operation,
        'expected_amount': previous / 100,
        'amount': net / 100,
        'verified_date': verifiedDate,
      });
    }

    final changes = {
      'id': id, 'amount': net / 100, 'signed_amount': -net / 100,
      'sync_state': 'pending',
      if (!local) 'payroll_amount_pending': true,
    };
    final rows = await _allTransactions(businessId);
    final before = rows.where((row) => row['id'] == id).singleOrNull ?? detail;
    await _cache.saveTransactionDetail(businessId, id, {...detail, ...changes});
    await _upsertSummary(businessId, {...before, ...changes});
    await LocalFinancialTotalsJournal(database: _database).record(
      businessId, 'transaction:$id', before: before, after: {...before, ...changes},
    );
  }

  /// Called inside the same SQLite transaction as the payroll reversal.
  Future<void> reversePayrollExpense(
    String businessId, String operation, {required int net, required String verifiedDate,}
  ) async {
    if (net == 0) return;
    final links = PayrollExpenseLinkStore(_database);
    await links.preparePending();
    final id = await links.transactionId(businessId, operation);
    if (id != null) {
      final detail = await _cache.loadTransactionDetail(businessId, id);
      final amount = num.tryParse(detail?['amount']?.toString() ?? '');
      if (detail?['payroll_operation_id'] != operation ||
          amount == null || (amount * 100).round() != net ||
          (detail?['transaction_date'] ?? detail?['date']) != verifiedDate) {
        throw StateError('The linked expense differs from the verified payroll receipt.');
      }
      final localId = PayrollExpenseIdentity.transactionId(businessId, operation);
      if (id == localId) {
        final receipt = await _database.customSelect(
          'SELECT id,last_attempt_at,attempt_count FROM sync_outbox '
          "WHERE business_id=? AND entity_id=? AND entity_type='financial_create' AND state='pending'",
          variables: [Variable(businessId), Variable(id)],
        ).getSingleOrNull();
        if (receipt == null || receipt.data['last_attempt_at'] != null ||
            receipt.read<int>('attempt_count') != 0) {
          throw StateError('Verify the expense synchronization result before reversing this payroll receipt.');
        }
        await _database.customStatement(
          "UPDATE sync_outbox SET state='reversed' WHERE business_id=? AND entity_id=? "
          "AND entity_type IN ('financial_create','financial_update') AND state='pending'",
          [businessId, id],
        );
      } else {
        await _enqueue(businessId, 'financial_payroll_reversal', id, 'reverse', {
          'transaction_id': id, 'payroll_operation': operation,
          'amount': net / 100, 'verified_date': verifiedDate,
        });
      }
      final rows = await _allTransactions(businessId);
      await _cache.saveTransactions(businessId, rows.where((r) => r['id'] != id).toList());
      await _cache.saveTransactionDetail(businessId, id, {
        ...detail!, 'status': 'void', 'editable': false, 'deletable': false,
        'sync_state': 'reversed',
      });
      await LocalFinancialTotalsJournal(database: _database).record(
        businessId, 'transaction:$id', before: detail, after: null,
      );
    } else {
      final pending = await _database.customSelect(
        'SELECT operation_id FROM payroll_expense_projection_pending_v1 '
        'WHERE business_id=? AND operation_id=?',
        variables: [Variable(businessId), Variable(operation)],
      ).getSingleOrNull();
      if (pending == null) {
        throw StateError('Verify the original historical expense before reversing this receipt.');
      }
    }
    await _database.customStatement(
      'DELETE FROM payroll_expense_projection_pending_v1 WHERE business_id=? AND operation_id=?',
      [businessId, operation],
    );
  }

  Future<void> updatePayrollExpenseAccount(
    String businessId,
    String transactionId, {
    required String expectedAccountId,
    required String accountId,
    required LocalOwnerGrant grant,
  }) async {
    grant.assertValid(businessId, grant.actorId);
    await _database.transaction(() async {
      final original = await _cache.loadPayrollExpenseForAccountEdit(businessId, transactionId);
      if (original == null || !LocalFinancialCache.requiresOwnerAccountEdit(original) ||
          original['recurring_rule_id'] != null ||
          original['account_id'] != expectedAccountId) {
        throw StateError('The original payroll expense changed. Reopen it to edit the account.');
      }
      if (accountId == expectedAccountId) return;
      final options = await _cache.loadOptions(businessId);
      final account = (options['accounts'] as List? ?? const [])
          .whereType<Map>()
          .where((row) => row['id'] == accountId && row['active'] != false)
          .singleOrNull;
      final accountName = account?['name']?.toString();
      if (accountName == null || accountName.isEmpty) {
        throw StateError('Choose an active account saved for this business.');
      }
      final changes = {
        'id': transactionId,
        'account_id': accountId,
        'account': accountName,
        'sync_state': 'pending',
        'payroll_account_pending': true,
      };
      grant.assertValid(businessId, grant.actorId);
      await _enqueue(businessId, 'financial_update', transactionId, 'update', {
        'transaction_id': transactionId,
        'payroll_account_only': true,
        'expected_account_id': expectedAccountId,
        'account_id': accountId,
      });
      await _cache.saveTransactionDetail(businessId, transactionId, {...original, ...changes});
      final rows = await _allTransactions(businessId);
      final summary = rows.where((row) => row['id'] == transactionId).firstOrNull;
      await _upsertSummary(businessId, {...(summary ?? original), ...changes});
      await LocalFinancialTotalsJournal(database: _database).record(
        businessId,
        'transaction:$transactionId',
        before: summary ?? original,
        after: {...(summary ?? original), ...changes},
      );
      grant.assertValid(businessId, grant.actorId);
    });
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
    List<Map<String, dynamic>> receipts = const [],
    Map<String, dynamic>? receiptExtraction,
  }) async {
    // Keep the edit, all prior attachments, and new upload operations atomic.
    // A retry after a failed local write cannot append a second copy.
    return _database.transaction(() async {
      final dateText = date.toIso8601String().split('T').first;
      final cleanCounterparty = (counterpartyName ?? '').trim().isEmpty
          ? (direction == 'income' ? 'Income' : 'Expense')
          : counterpartyName!.trim();

      final existing = await _cache.loadTransactionForEdit(businessId, transactionId) ??
          await _cache.loadTransactionDetail(businessId, transactionId);
      if (existing == null) {
        throw StateError('The original expense is unavailable. Reopen it before saving.');
      }
      if (LocalFinancialCache.requiresOwnerAccountEdit(existing)) {
        throw StateError('Open the payroll expense as Owner to change its account.');
      }
      if (existing['recurring_engine_owned'] == true) {
        throw StateError('Edit this expense from Recurring transactions so its occurrence identity is preserved.');
      }

      final pendingCreate = await _database
          .customSelect(
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
          )
          .get();

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
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json = ?, last_error = NULL WHERE id = ?',
          [jsonEncode(existingPayload), row.read<int>('id')],
        );
      } else {
        await _enqueue(
          businessId,
          'financial_update',
          transactionId,
          'update',
          {'transaction_id': transactionId, ...payload},
        );
      }

      final attachments = List<Map<String, dynamic>>.from(
        List<dynamic>.from(existing['attachments'] ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)),
      );
      attachments.addAll(
        await _queueReceipts(businessId, transactionId, receipts),
      );
      if (receiptExtraction != null) {
        await _enqueueReceiptExtraction(
          businessId,
          transactionId,
          receiptExtraction,
        );
      }

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
        'receipt_count': attachments.length,
        'recurring': false,
        'sync_state': 'pending',
      };
      final oldRows = await _allTransactions(businessId);
      Map<String, dynamic>? previous;
      for (final row in oldRows) {
        if (row['id']?.toString() == transactionId) {
          previous = row;
          break;
        }
      }
      await _upsertSummary(businessId, summary);
      await LocalFinancialTotalsJournal(database: _database).record(
        businessId,
        'transaction:$transactionId',
        before: previous,
        after: summary,
      );

      final detail = <String, dynamic>{
        ...existing,
        ...summary,
        'date': dateText,
        'editable': true,
        'deletable': false,
        'attachments': attachments,
        if (receiptExtraction != null)
          ..._receiptProjection(transactionId, receiptExtraction),
      };
      await _cache.saveTransactionDetail(businessId, transactionId, detail);

      return detail;
    });
  }

  /// Receipt-only write: never creates a manual financial transaction or
  /// changes the recurring amount. Uploaded after recurrence reconciliation.
  Future<void> attachRecurringReceipts(String businessId, String transactionId, {
    required List<Map<String, dynamic>> receipts,
    required void Function() assertAuthorized,
    Map<String, dynamic>? receiptExtraction,
  }) async {
    assertAuthorized();
    await _database.transaction(() async {
      final existing = await _cache.loadTransactionDetail(businessId, transactionId);
      if (existing == null || existing['recurring_engine_owned'] != true) {
        throw StateError('Recurring expense is not available locally.');
      }
      final attachments = <Map<String, dynamic>>[
        for (final raw in existing['attachments'] as List? ?? [])
          Map<String, dynamic>.from(raw as Map),
        ...await _queueReceipts(businessId, transactionId, receipts),
      ];
      if (receiptExtraction != null) {
        if (receiptExtraction['review_confirmed'] != true) {
          throw StateError('Confirm receipt details before saving.');
        }
        await _enqueueReceiptExtraction(businessId, transactionId, receiptExtraction);
      }
      final updated = {...existing, 'attachments': attachments,
        'receipt_count': attachments.length,
        if (receiptExtraction != null) ..._receiptProjection(transactionId, receiptExtraction)};
      await _cache.saveTransactionDetail(businessId, transactionId, updated);
      await _upsertSummary(businessId, updated);
      assertAuthorized();
    });
  }

  Future<void> voidSavedExpense(
    String business, String transaction, {
    required String ownerId,
    required void Function() assertAuthorized,
  }) async {
    assertAuthorized();
    await _database.transaction(() async {
      await _ensureLocalVoids();
      if ((await _cache.locallyVoidedExpenseIds(business)).contains(transaction)) return;
      final original = await _cache.loadTransactionDetail(business, transaction);
      if (ownerId.isEmpty || transaction.startsWith('local-') ||
          !LocalFinancialCache.canVoidSavedExpense(original) ||
          LocalFinancialCache.validatedEditSource(original, business, transaction) == null) {
        throw StateError('This expense requires a verified original and accounting review before deletion.');
      }
      final queued = await _database.customSelect(
        "SELECT 1 FROM sync_outbox WHERE business_id=? AND state IN ('pending','inflight') "
        "AND (entity_id=? OR (json_valid(payload_json) AND json_extract(payload_json,'\$.transaction_id')=?)) "
        "LIMIT 1",
        variables: [Variable(business), Variable(transaction), Variable(transaction)],
      ).getSingleOrNull();
      if (queued != null) throw StateError('Finish pending corrections to this expense first.');
      await _database.customStatement(
        'INSERT INTO local_financial_voids VALUES(?,?,?,?,?)',
        [business, transaction, ownerId, DateTime.now().toUtc().toIso8601String(), jsonEncode(original)],
      );
      await LocalFinancialTotalsJournal(database: _database).record(
        business, 'transaction:$transaction', before: original,
      );
      assertAuthorized();
    });
  }

  Future<void> _ensureLocalVoids() async {
    await _database.customStatement('''CREATE TABLE IF NOT EXISTS local_financial_voids(
        business_id TEXT NOT NULL, transaction_id TEXT NOT NULL, owner_id TEXT NOT NULL,
        voided_at TEXT NOT NULL, original TEXT NOT NULL,
        PRIMARY KEY(business_id,transaction_id))''');
  }

  Future<void> voidDuplicatePayrollExpense(
    String business, {
    required String duplicateId,
    required String keepId,
    required String ownerId,
    required void Function() assertAuthorized,
  }) async {
    assertAuthorized();
    if (ownerId.isEmpty || duplicateId.isEmpty || keepId.isEmpty ||
        duplicateId == keepId) {
      throw StateError('Choose two separate saved payroll expenses.');
    }
    await _database.transaction(() async {
      await _ensureLocalVoids();
      if ((await _cache.locallyVoidedExpenseIds(business)).contains(duplicateId)) {
        return;
      }
      final groups = await LocalEmployeeReports(database: _database)
          .duplicateGroups(business, isOwner: true);
      final matching = groups.where((group) {
        final ids = group.entries.map((entry) => entry.expense?['id']);
        return ids.contains(duplicateId) && ids.contains(keepId);
      }).singleOrNull;
      if (matching == null) {
        throw StateError('The selected expenses no longer match. Reopen the review.');
      }
      final candidate = matching.entries.singleWhere(
        (entry) => entry.expense?['id'] == duplicateId,
      );
      final original = candidate.expense!;
      if (candidate.operationId != null ||
          original['invoice_payment_id'] != null ||
          original['document_id'] != null || original['job_id'] != null ||
          original['recurring_rule_id'] != null ||
          original['recurring_engine_owned'] == true ||
          original['recurring'] == true ||
          original['transfer_group_id'] != null) {
        throw StateError('This expense is linked to another record. Review it separately.');
      }

      final queued = await _database.customSelect(
        "SELECT * FROM sync_outbox WHERE business_id=? AND state!='reversed' "
        "AND (entity_id=? OR (json_valid(payload_json) AND "
        "(json_extract(payload_json,'\$.transaction_id')=? OR "
        "json_extract(payload_json,'\$.local_transaction_id')=?)))",
        variables: [
          Variable(business), Variable(duplicateId),
          Variable(duplicateId), Variable(duplicateId),
        ],
      ).get();
      final pendingCreate = queued.singleOrNull;
      final safePendingCreate = pendingCreate != null &&
          pendingCreate.read<String>('entity_type') == 'financial_create' &&
          pendingCreate.read<String>('state') == 'pending' &&
          pendingCreate.data['last_attempt_at'] == null &&
          pendingCreate.read<int>('attempt_count') == 0;
      final needsQueueProof = queued.isNotEmpty ||
          duplicateId.startsWith('local-') || original['sync_state'] == 'pending';
      if (needsQueueProof && !safePendingCreate) {
        throw StateError('This expense has unresolved sync activity. Review its sync status first.');
      }
      if (safePendingCreate) {
        await _database.customStatement(
          "UPDATE sync_outbox SET state='reversed' WHERE id=?",
          [pendingCreate.read<int>('id')],
        );
      }
      await _database.customStatement(
        'INSERT INTO local_financial_voids VALUES(?,?,?,?,?)',
        [business, duplicateId, ownerId, DateTime.now().toUtc().toIso8601String(),
         jsonEncode({...original, 'duplicate_kept_id': keepId})],
      );
      await LocalFinancialTotalsJournal(database: _database).record(
        business, 'transaction:$duplicateId', before: {
          ...original,
          'direction': 'expense',
          'amount': matching.cents / 100,
          'transaction_date': matching.date.toIso8601String().split('T').first,
        },
      );
      assertAuthorized();
    });
  }

  Future<void> flush(String businessId) async {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    final rows = await _database
        .customSelect(
          '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ?
        AND state = 'pending'
        AND entity_type IN (
          'financial_create',
          'financial_update',
          'financial_photo',
          'financial_receipt_extraction',
          'financial_payroll_reversal'
        )
      ORDER BY id
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();

    for (final row in rows) {
      if (BriskersConnectionModeController.instance.forceOffline) return;
      final outboxId = row.read<int>('id');
      // A preceding create can remap queued photos to the server transaction.
      // Reload instead of replaying the original, stale snapshot payload.
      final current = await _database
          .customSelect(
            "SELECT entity_type, payload_json FROM sync_outbox "
            "WHERE business_id = ? AND id = ? AND state = 'pending'",
            variables: [Variable<String>(businessId), Variable<int>(outboxId)],
          )
          .getSingleOrNull();
      if (current == null) continue;
      final type = current.read<String>('entity_type');
      final payload = Map<String, dynamic>.from(
        jsonDecode(current.read<String>('payload_json')) as Map,
      );

      // Keep dependent expenses queued until the payee's permanent ID is acknowledged.
      if (payload['counterparty_id'] != null) {
        final options = await _cache.loadOptions(businessId);
        if ((options['counterparties'] as List? ?? const []).whereType<Map>().any(
            (r) => r['id'] == payload['counterparty_id'] && r['sync_state'] == 'pending')) {
          break;
        }
      }
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: outboxId,
        );
        if (type == 'financial_create') {
          await _flushCreate(businessId, outboxId, payload);
        } else if (type == 'financial_update') {
          await _flushUpdate(businessId, outboxId, payload);
        } else if (type == 'financial_payroll_reversal') {
          await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => _api.syncPayrollExpenseReversal(
              businessId,
              operation: payload['payroll_operation'] as String,
              transactionId: payload['transaction_id'] as String,
              amount: payload['amount'] as num,
              date: payload['verified_date'] as String,
            ),
            outboxId: outboxId,
          );
          await _database.customStatement(
            "DELETE FROM sync_outbox WHERE business_id=? AND id=? AND state='pending'",
            [businessId, outboxId],
          );
        } else if (type == 'financial_photo') {
          await _flushPhoto(businessId, outboxId, payload);
        } else if (type == 'financial_receipt_extraction') {
          await _flushReceiptExtraction(businessId, outboxId, payload);
        }
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
    final isPayroll = payload['operation_id'].toString().startsWith('payroll-financial-');
    // Mark dispatch before a duplicate review can cancel the queued creation.
    final marked = await _database.customUpdate(
      "UPDATE sync_outbox SET last_attempt_at=? WHERE business_id=? AND id=? AND state='pending' AND payload_json=?",
      variables: [Variable(_unixNow()), Variable(businessId), Variable(outboxId), Variable(jsonEncode(payload))],
    );
    if (marked == 0) return;

    final response = await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.syncCreateManualTransaction(
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
      ),
      outboxId: outboxId,
    );
    final serverId = response['transaction_id']?.toString() ?? '';
    if (serverId.isEmpty) {
      throw StateError('Server did not return a transaction ID.');
    }

    await _database.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(
        _database,
        businessId,
        outboxId: outboxId,
      );
      final rows = await _allTransactions(businessId);
      final index = rows.indexWhere(
        (item) => item['id']?.toString() == localId,
      );
      if (index >= 0) {
        final local = rows[index];
        final canonical = isPayroll
            ? rows.where((row) => row['id'] == serverId).firstOrNull
            : null;
        if (canonical != null &&
            (canonical['direction'] != 'expense' ||
             num.tryParse(canonical['amount']?.toString() ?? '') != local['amount'] ||
             canonical['transaction_date'] != local['transaction_date'])) {
          throw StateError('The synchronized payroll expense differs from its saved payment.');
        }
        rows[index] = {
          ...local, ...?canonical,
          'id': serverId, 'sync_state': 'pending',
          if (isPayroll) ...{
            'payroll_operation_id': local['payroll_operation_id'],
            'payment_method': local['payment_method'],
          },
        };
        await _cache.saveTransactions(businessId, [
          for (var i = 0; i < rows.length; i++)
            if (!isPayroll || i == index || rows[i]['id'] != serverId) rows[i],
        ]);
      }
      await LocalFinancialTotalsJournal(database: _database).remap(
        businessId,
        'transaction:$localId',
        'transaction:$serverId',
        newTransactionId: serverId,
      );

      final copies = await _database.customSelect(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_financial_copies'",
      ).getSingleOrNull();
      if (copies != null) {
        await _database.customStatement(
          'UPDATE local_financial_copies SET transaction_id=? WHERE business_id=? AND transaction_id=?',
          [serverId, businessId, localId],
        );
      }
      await PayrollExpenseLinkStore(_database).remap(businessId, localId, serverId);
      final detail = await _cache.loadTransactionDetail(businessId, localId);
      if (detail != null) {
        final savedCanonical = isPayroll
            ? await _cache.loadTransactionDetail(businessId, serverId)
            : null;
        await _cache.saveTransactionDetail(businessId, serverId, {
          ...detail,
          if ((savedCanonical?['attachments'] as List? ?? []).isNotEmpty)
            'attachments': savedCanonical!['attachments'],
          'id': serverId,
          'sync_state': 'pending',
          if (detail['receipt_extraction'] is Map)
            ..._receiptProjection(
              serverId,
              Map<String, dynamic>.from(detail['receipt_extraction'] as Map),
            ),
        });
      }

      final corrections = await _database.customSelect(
        "SELECT id, payload_json FROM sync_outbox WHERE business_id = ? "
        "AND entity_type = 'financial_update' AND entity_id = ? AND state = 'pending'",
        variables: [Variable(businessId), Variable(localId)],
      ).get();
      for (final correction in corrections) {
        final body = Map<String, dynamic>.from(
          jsonDecode(correction.read<String>('payload_json')) as Map,
        );
        if (body['payroll_account_only'] != true) continue;
        body['transaction_id'] = serverId;
        await _database.customStatement(
          'UPDATE sync_outbox SET entity_id = ?, payload_json = ? WHERE id = ?',
          [serverId, jsonEncode(body), correction.read<int>('id')],
        );
      }

      final photos = await _database
          .customSelect(
            '''
        SELECT id, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type IN ('financial_photo', 'financial_receipt_extraction')
          AND state = 'pending'
        ''',
            variables: [Variable<String>(businessId)],
          )
          .get();

      for (final photoRow in photos) {
        final photoPayload = Map<String, dynamic>.from(
          jsonDecode(photoRow.read<String>('payload_json')) as Map,
        );
        if (photoPayload['transaction_id']?.toString() != localId) continue;
        photoPayload['transaction_id'] = serverId;
        await _database.customStatement(
          "UPDATE sync_outbox SET payload_json = ?, "
          "entity_id = CASE WHEN entity_type = 'financial_receipt_extraction' "
          "THEN ? ELSE entity_id END WHERE id = ? AND business_id = ?",
          [
            jsonEncode(photoPayload),
            serverId,
            photoRow.read<int>('id'),
            businessId,
          ],
        );
      }

      await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
        outboxId,
      ]);
    });
  }

  Future<void> _flushUpdate(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final transactionId = payload['transaction_id'].toString();
    final amountRevision = payload['payroll_amount_revision'] as int?;
    if (payload['payroll_account_only'] == true || amountRevision != null) {
      await LocalJobQuarantine.guardReplay(
        _database,
        businessId,
        () => amountRevision == null
            ? _api.syncPayrollExpenseAccount(
                businessId,
                transactionId,
                expectedAccountId: payload['expected_account_id'].toString(),
                accountId: payload['account_id'].toString(),
              )
            : _api.syncPayrollExpenseAmount(
                businessId,
                transactionId: transactionId,
                operation: payload['payroll_operation'] as String,
                previous: payload['expected_amount'] as num,
                amount: payload['amount'] as num,
                date: payload['verified_date'] as String,
                revision: amountRevision,
              ),
        outboxId: outboxId,
      );
      await _database.transaction(() async {
        await LocalJobQuarantine.assertReplayAllowed(
          _database, businessId, outboxId: outboxId,
        );
        await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [outboxId]);
        final remaining = await _database.customSelect(
          "SELECT id FROM sync_outbox WHERE business_id = ? AND entity_id = ? "
          "AND entity_type = 'financial_update' AND state = 'pending' LIMIT 1",
          variables: [Variable(businessId), Variable(transactionId)],
        ).getSingleOrNull();
        if (remaining != null) return;
        final detail = await _cache.loadTransactionDetail(businessId, transactionId);
        if (detail != null && detail['sync_state'] != 'reversed' &&
            (detail['payroll_account_pending'] == true ||
            detail['payroll_amount_pending'] == true)) {
          final syncState = {
            'sync_state': 'synced',
            'payroll_account_pending': false,
            'payroll_amount_pending': false,
          };
          await _cache.saveTransactionDetail(businessId, transactionId, {...detail, ...syncState});
          await _upsertSummary(businessId, {'id': transactionId, ...syncState});
        }
      });
      return;
    }
    await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.updateManualTransaction(
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
      ),
      outboxId: outboxId,
    );
    await _database.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(
        _database,
        businessId,
        outboxId: outboxId,
      );
      await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
        outboxId,
      ]);
    });
  }

  /// Confirmed receipt details are saved locally with the expense first.
  /// The queued server projection is deferred until financial synchronization
  /// is independently permitted; Force Offline never triggers this method.
  Future<void> _flushReceiptExtraction(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final transactionId = payload['transaction_id']?.toString() ?? '';
    if (transactionId.startsWith('local-transaction-') ||
        transactionId.startsWith('local-recurring-')) {
      return;
    }
    final extraction = payload['extraction'];
    if (extraction is! Map || extraction['review_confirmed'] != true) {
      throw StateError('Unconfirmed receipt cannot be synchronized.');
    }
    await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.applyExpenseReceiptExtraction(
        businessId,
        transactionId,
        Map<String, dynamic>.from(extraction),
      ),
      outboxId: outboxId,
    );
    await _database.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(
        _database,
        businessId,
        outboxId: outboxId,
      );
      await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
        outboxId,
      ]);
    });
  }

  Future<void> _flushPhoto(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final transactionId = payload['transaction_id']?.toString() ?? '';
    if (transactionId.startsWith('local-transaction-') ||
        transactionId.startsWith('local-recurring-')) {
      return;
    }

    final file = File(payload['local_file_path'].toString());
    final bytes = await file.readAsBytes();
    final registration = await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.syncRegisterExpensePhoto(
        businessId,
        transactionId,
        operationId: payload['operation_id'].toString(),
        filename: payload['filename'].toString(),
        mimeType: payload['mime_type'].toString(),
      ),
      outboxId: outboxId,
    );

    await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.uploadRegisteredAttachment(
        businessId,
        bucket: registration['bucket'].toString(),
        key: registration['key'].toString(),
        attachmentId: registration['attachment_id'].toString(),
        mimeType: payload['mime_type'].toString(),
        bytes: bytes,
        replayGuard: <T>(Future<T> Function() operation) =>
            LocalJobQuarantine.guardReplay<T>(
              _database,
              businessId,
              operation,
              outboxId: outboxId,
            ),
      ),
      outboxId: outboxId,
    );

    await _database.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(
        _database,
        businessId,
        outboxId: outboxId,
      );
      final detail = await _cache.loadTransactionDetail(
        businessId,
        transactionId,
      );
      if (detail != null) {
        final localPhotoId = 'local-receipt-${payload['operation_id']}';
        final attachments =
            List<dynamic>.from(detail['attachments'] ?? const [])
                .whereType<Map>()
                .map((raw) {
                  final attachment = Map<String, dynamic>.from(raw);
                  if (attachment['attachment_id']?.toString() != localPhotoId) {
                    return attachment;
                  }
                  return <String, dynamic>{
                    ...attachment,
                    'id': registration['attachment_id'],
                    'attachment_id': registration['attachment_id'],
                    'bucket': registration['bucket'],
                    'key': registration['key'],
                    'upload_state': 'synced',
                  };
                })
                .toList();
        await _cache.saveTransactionDetail(businessId, transactionId, {
          ...detail,
          'attachments': attachments,
          'receipt_count': attachments.length,
        });
      }
      await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
        outboxId,
      ]);
    });
  }
}

