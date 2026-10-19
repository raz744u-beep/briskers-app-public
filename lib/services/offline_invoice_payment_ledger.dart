import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import '../core/connection_mode.dart';
import 'briskers_api.dart';
import 'local_job_quarantine.dart';
import 'local_job_deletion_v3.dart';
import 'offline_job_purge.dart';
import 'local_document_detail_cache.dart';

/// Durable *local* payment capture and idempotent replay. This class records
/// received payments only; it never finalizes payments or posts income.
///
/// Outbox payloads are the source of truth until the server acknowledges them.
/// Use [pendingForInvoice] after restart to rebuild the invoice's local display.
class OfflineInvoicePaymentLedger {
  OfflineInvoicePaymentLedger({
    BriskersLocalDatabase? database,
    BriskersApi api = const BriskersApi(),
  }) : _database = database ?? localDatabase,
       _api = api;

  final BriskersLocalDatabase _database;
  final BriskersApi _api;
  final Random _random = Random.secure();
  static final Expando<Map<String, Future<void>>> _activeFlushes = Expando();

  static int cents(num value) {
    if (!value.isFinite || value <= 0 || !(value * 100).isFinite) {
      throw ArgumentError.value(value, 'amount', 'Must be positive and finite');
    }
    final rounded = (value * 100).round();
    if (rounded <= 0) {
      throw ArgumentError.value(value, 'amount', 'Must be at least one cent');
    }
    return rounded;
  }

  static int remainingCents({
    required num total,
    required num finalized,
    required num pendingOnServer,
    required Iterable<num> queuedLocally,
  }) {
    int toCents(num n) => (n * 100).round();
    final received = toCents(finalized) +
        toCents(pendingOnServer) +
        queuedLocally.fold<int>(0, (sum, amount) => sum + toCents(amount));
    return max(0, toCents(total) - received);
  }

  /// Local queue entries are retired only after their payment appears in
  /// authoritative server detail. Never rely on matching amounts alone.
  static bool serverAcknowledgesPayment(
    Map<String, dynamic> detail,
    String paymentId, {
    String? operationId,
  }) {
    final entries = detail['payments'];
    if (entries is! List) return false;
    return entries.whereType<Map>().any((payment) {
      // A projected local receipt must never acknowledge itself.
      if (payment['pending_sync'] == true ||
          payment['_local_pending_payment'] == true) {
        return false;
      }
      return (paymentId.isNotEmpty &&
              payment['id']?.toString() == paymentId) ||
          (operationId != null && operationId.isNotEmpty &&
              (payment['operation_id']?.toString() == operationId ||
                  payment['client_operation_id']?.toString() == operationId));
    });
  }

  static num _number(dynamic value) {
    final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : 0;
  }

  /// Overlay the durable queue on any cached or refreshed invoice snapshot.
  /// The input is not mutated. Reapplying the projection does not add money
  /// twice, and server payment identity always takes precedence over the queue.
  static Map<String, dynamic> projectPendingPayments(
    Map<String, dynamic> detail,
    Iterable<Map<String, dynamic>> queued,
  ) {
    final projected = Map<String, dynamic>.from(detail);
    final rawPayments = detail['payments'];
    final payments = rawPayments is List
        ? rawPayments.whereType<Map>()
            .map((payment) => Map<String, dynamic>.from(payment)).toList()
        : <Map<String, dynamic>>[];
    final previousLocalCents = payments
        .where((payment) => payment['_local_pending_payment'] == true)
        .fold<int>(0, (sum, payment) =>
            sum + (_number(payment['_local_projected_payment_amount'] ??
                payment['amount']) * 100).round());
    payments.removeWhere(
      (payment) => payment['_local_pending_payment'] == true,
    );
    final authoritative = <String, dynamic>{'payments': payments};
    final operationIds = <String>{};
    final localPayments = <Map<String, dynamic>>[];
    var queuedCents = 0;
    var projectedCents = 0;
    var requiresReconciliation = false;
    for (final receipt in queued) {
      final operationId = receipt['operation_id']?.toString() ?? '';
      if (operationId.isEmpty || !operationIds.add(operationId)) continue;
      if (serverAcknowledgesPayment(
        authoritative,
        receipt['server_payment_id']?.toString() ?? '',
        operationId: operationId,
      )) {
        continue;
      }
      final amountCents = _number(receipt['amount_cents']).round();
      if (amountCents <= 0) continue;
      queuedCents += amountCents;
      // Finalizing on another device can replace the pending server payment
      // with an unrelated posted ID. Without a shared operation identity we
      // cannot tell whether that payment represents this receipt. Keep it
      // visible and queued, but do not add its amount to the server aggregate.
      final attempted = receipt['replay_attempted'] == true ||
          (receipt['server_payment_id']?.toString().isNotEmpty ?? false);
      final ambiguous = attempted && payments.isNotEmpty;
      final contributionCents = ambiguous ? 0 : amountCents;
      projectedCents += contributionCents;
      requiresReconciliation = requiresReconciliation || ambiguous;
      localPayments.add(<String, dynamic>{
        'id': operationId,
        'operation_id': operationId,
        'state': 'pending',
        'amount': amountCents / 100,
        'payment_method_name': receipt['method_name'],
        'payment_method_id': receipt['method_id'],
        'entered_at': receipt['payment_date'] ?? receipt['received_at'],
        'payment_date': receipt['payment_date'],
        'pending_sync': true,
        '_local_pending_payment': true,
        'reconciliation_required': ambiguous,
        '_local_projected_payment_amount': contributionCents / 100,
      });
    }
    final serverPendingCents =
        (_number(detail['pending_payment']) * 100).round() - previousLocalCents;
    projected['pending_payment'] = (serverPendingCents + projectedCents) / 100;
    projected['payments'] = [...payments, ...localPayments];
    projected['_local_pending_payment'] = localPayments.isNotEmpty;
    projected['_local_pending_payment_amount'] = queuedCents / 100;
    projected['_payment_reconciliation_required'] = requiresReconciliation;
    // Capture this snapshot before opening a payment dialog. It also includes
    // acknowledged rows awaiting cache retirement, which are not displayed as
    // local payments but still need to participate in the stale-capture guard.
    projected['_local_queued_payment_operation_ids'] = operationIds.toList();
    return projected;
  }

  String _operationId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Record a payment already received or approved through its real channel.
  /// Briskers records the received payment only; it never processes cards.
  Future<String> recordReceivedPayment(
    String businessId,
    String invoiceId, {
    required num amount,
    required int remainingBeforePaymentCents,
    required String methodId,
    required String methodName,
    Iterable<String>? expectedQueuedOperationIds,
  }) async {
    final visibilityGeneration = await LocalJobDeletionV3.captureVisibilityGeneration(_database, businessId);
    if (businessId.isEmpty || invoiceId.isEmpty || methodId.isEmpty) {
      throw ArgumentError('Business, invoice and payment method are required.');
    }
    final method = methodName.trim();
    if (method.isEmpty) throw ArgumentError('Payment method is required.');
    final amountCents = cents(amount);
    if (remainingBeforePaymentCents < amountCents) {
      throw StateError('Payment exceeds the remaining invoice balance.');
    }
    final operationId = _operationId();
    // Capture the payment's shop-local calendar date before any later sync.
    // The UTC receipt timestamp stays immutable for provenance.
    final capturedAt = DateTime.now();
    final capturedUtc = capturedAt.toUtc();
    final capturedDate = '${capturedAt.year.toString().padLeft(4, '0')}-'
        '${capturedAt.month.toString().padLeft(2, '0')}-'
        '${capturedAt.day.toString().padLeft(2, '0')}';
    final now = capturedUtc.millisecondsSinceEpoch ~/ 1000;
    final payload = <String, dynamic>{
      'operation_id': operationId,
      'invoice_id': invoiceId,
      'method_id': methodId,
      'method_name': method,
      'amount_cents': amountCents,
      'received_at': capturedUtc.toIso8601String(),
      'payment_date': capturedDate,
    };
    await _database.transaction(() async {
      await LocalJobDeletionV3.assertVisibilityGeneration(_database, businessId, visibilityGeneration);
      await OfflineJobPurge.recordNewIntent(_database, businessId, [operationId]);
      if (expectedQueuedOperationIds != null) {
        final current = await pendingForInvoice(businessId, invoiceId);
        final currentIds = current
            .map((payment) => payment['operation_id'].toString()).toSet();
        final expectedIds = expectedQueuedOperationIds.toSet();
        if (currentIds.length != expectedIds.length ||
            !currentIds.containsAll(expectedIds)) {
          throw StateError(
            'Invoice payments changed. Reload the invoice before recording payment.',
          );
        }
      }
      // Never submit this through the legacy add-payment RPC, which has no
      // operation-id idempotency argument. A dedicated server RPC is required.
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation, payload_json,
          base_row_version, state, attempt_count, created_at,
          last_attempt_at, last_error
        ) VALUES (?, 'invoice_payment_received', ?, 'record_received_payment', ?,
                  NULL, 'pending', 0, ?, NULL, NULL)
        ''',
        [businessId, invoiceId, jsonEncode(payload), now],
      );
    });
    return operationId;
  }

  Future<void> editNeverSubmittedPayment(
    String businessId, String invoiceId, String operationId, {
    required num amount,
    required int maximumAllowedCents,
    required String methodId,
    required String methodName,
    required String paymentDate,
  }) async {
    final amountCents = cents(amount);
    final date = DateTime.tryParse(paymentDate);
    if (amountCents > maximumAllowedCents) {
      throw StateError('Payment exceeds available invoice balance.');
    }
    if (methodId.isEmpty || methodName.trim().isEmpty ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(paymentDate) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != paymentDate) {
      throw ArgumentError('Select a valid amount, date and method.');
    }
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        """SELECT id, state, attempt_count, last_attempt_at, payload_json
        FROM sync_outbox WHERE business_id=? AND entity_id=?
        AND entity_type='invoice_payment_received'
        AND state IN ('pending','inflight')""",
        variables: [Variable<String>(businessId), Variable<String>(invoiceId)],
      ).get();
      final matching = rows.where((row) {
        try {
          final value = jsonDecode(row.read<String>('payload_json')) as Map;
          return value['operation_id']?.toString() == operationId;
        } catch (_) { return false; }
      }).toList();
      if (matching.length != 1) {
        throw StateError('Payment not found. Reload before editing.');
      }
      final row = matching.single;
      final value = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map);
      if (row.read<String>('state') != 'pending' ||
          row.read<int>('attempt_count') != 0 ||
          row.readNullable<int>('last_attempt_at') != null ||
          value['replay_attempted'] == true ||
          (value['server_payment_id']?.toString().isNotEmpty ?? false)) {
        throw StateError(
          'Payment may have reached the server. Reconcile before editing.');
      }
      // Retain pre-sync changes as client-reported history and forward it
      // with the original UUID. Server records it separately from trusted
      // server-side edits, rather than pretending the old values never existed.
      final previousHistory = (value['local_edit_history'] is List)
          ? List<dynamic>.from(value['local_edit_history'] as List)
          : <dynamic>[];
      if (previousHistory.length >= 100) {
        throw StateError('Too many local edits; reconcile this payment first.');
      }
      previousHistory.add({
        'changed_at_device': DateTime.now().toUtc().toIso8601String(),
        'old_amount_cents': value['amount_cents'],
        'new_amount_cents': amountCents,
        'old_method_id': value['method_id'],
        'new_method_id': methodId,
        'old_payment_date': value['payment_date'] ??
            (value['received_at']?.toString().split('T').first),
        'new_payment_date': paymentDate,
      });
      value['local_edit_history'] = previousHistory;
      value['amount_cents'] = amountCents;
      value['method_id'] = methodId;
      value['method_name'] = methodName.trim();
      // Preserve received_at as originally captured; only shop date changes.
      value['payment_date'] = paymentDate;
      value['local_edit_at'] = DateTime.now().toUtc().toIso8601String();
      await _database.customStatement(
        "UPDATE sync_outbox SET payload_json=?,last_error=NULL WHERE id=?",
        [jsonEncode(value), row.read<int>('id')],
      );
    });
  }


  /// Offline corrections to server-pending receipts retain the payment ID
  /// and the originally read server version. No payment is created or charged.
  /// Queue changes to a server-pending receipt without changing its UUID.
  /// Older v3 snapshots did not carry payment row_version. In that case keep
  /// the original amount/method/timestamp and fail closed at replay unless
  /// the authoritative receipt remains a pristine version-1 match.
  Future<void> queueServerPendingEdit(
    String businessId, String invoiceId, String paymentId, {
    required int? expectedRowVersion,
    required num amount,
    required int maximumAllowedCents,
    required String methodId,
    required String methodName,
    required String paymentDate,
    int? originalAmountCents,
    String? originalMethodId,
    String? originalEnteredAt,
    String? originalPaymentDate,
  }) async {
    final amountCents = cents(amount);
    final date = DateTime.tryParse(paymentDate);
    if ((expectedRowVersion != null && expectedRowVersion < 1) ||
        amountCents > maximumAllowedCents ||
        methodId.isEmpty || methodName.trim().isEmpty ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(paymentDate) ||
        date == null || date.toIso8601String().substring(0, 10) != paymentDate) {
      throw ArgumentError('Invalid payment correction or balance.');
    }
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        """SELECT id,state,attempt_count,last_attempt_at,payload_json
           FROM sync_outbox WHERE business_id=? AND entity_id=?
           AND entity_type='invoice_pending_payment_edit'
           AND state IN ('pending','inflight','conflict')""",
        variables: [Variable<String>(businessId),Variable<String>(invoiceId)],
      ).get();
      final matched = rows.where((row) {
        try {
          final p = jsonDecode(row.read<String>('payload_json')) as Map;
          return p['payment_id']?.toString() == paymentId;
        } catch (_) { return false; }
      }).toList();
      if (matched.length > 1) {
        throw StateError('Conflicting queued payment corrections.');
      }
      final row = matched.isEmpty ? null : matched.single;
      if (row != null &&
          (row.read<String>('state') != 'pending' ||
           row.read<int>('attempt_count') != 0 ||
           row.readNullable<int>('last_attempt_at') != null)) {
        throw StateError('Correction may have reached the server. Reconcile first.');
      }
      final previous = row == null ? null : Map<String,dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map);
      if (previous != null &&
          previous['expected_row_version'] != expectedRowVersion) {
        throw StateError('Pending payment changed; refresh before editing.');
      }
      final baseAmount = previous?['original_amount_cents'] ??
          originalAmountCents;
      final baseMethod = previous?['original_method_id'] ??
          originalMethodId;
      final baseEntered = previous?['original_entered_at'] ??
          originalEnteredAt;
      final baseDate = previous == null
          ? originalPaymentDate : previous['original_payment_date'];
      if (expectedRowVersion == null &&
          ((num.tryParse(baseAmount?.toString() ?? '') ?? 0) <= 0 ||
           (baseMethod?.toString().isEmpty ?? true) ||
           (baseEntered?.toString().isEmpty ?? true))) {
        throw StateError('Original payment details are missing. '
            'Open this invoice online once before editing.');
      }
      final now = DateTime.now().toUtc();
      final payload = <String,dynamic>{
        'invoice_id': invoiceId,
        'payment_id': paymentId,
        'expected_row_version': expectedRowVersion,
        'original_amount_cents': baseAmount,
        'original_method_id': baseMethod,
        'original_entered_at': baseEntered,
        'original_payment_date': baseDate,
        'amount_cents': amountCents,
        'method_id': methodId,
        'method_name': methodName.trim(),
        'payment_date': paymentDate,
        'created_at': previous?['created_at'] ?? now.toIso8601String(),
        'local_edit_at': now.toIso8601String(),
      };
      if (row == null) {
        await _database.customStatement(
          """INSERT INTO sync_outbox
             (business_id,entity_type,entity_id,operation,payload_json,
              base_row_version,state,attempt_count,created_at,
              last_attempt_at,last_error)
             VALUES (?,'invoice_pending_payment_edit',?,'edit_pending_payment',
                     ?,?,'pending',0,?,NULL,NULL)""",
          [businessId,invoiceId,jsonEncode(payload),
           expectedRowVersion,now.millisecondsSinceEpoch ~/ 1000],
        );
      } else {
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=?,last_error=NULL WHERE id=?',
          [jsonEncode(payload),row.read<int>('id')],
        );
      }
    });
  }

  Future<List<Map<String,dynamic>>> pendingEditsForInvoice(
    String businessId,String invoiceId,
  ) async {
    final rows = await _database.customSelect(
      """SELECT payload_json,state FROM sync_outbox
      WHERE business_id=? AND entity_id=?
        AND entity_type='invoice_pending_payment_edit'
        AND state IN ('pending','inflight','conflict')
      ORDER BY id""",
      variables: [Variable<String>(businessId),Variable<String>(invoiceId)],
    ).get();
    return rows.map((row) => <String,dynamic>{
      ...Map<String,dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map),
      '_queue_state': row.read<String>('state'),
    }).toList();
  }

  /// Pure local preview of corrections to already-server-pending receipts.
  /// The receipt keeps the same ID. Adjust totals by its exact delta.
  static Map<String,dynamic> projectPendingEdits(
    Map<String,dynamic> detail,
    Iterable<Map<String,dynamic>> pendingEdits,
  ) {
    final updated=Map<String,dynamic>.from(detail);
    final raw=detail['payments'];
    if(raw is! List) return updated;
    final payments=raw.whereType<Map>()
      .map((p)=>Map<String,dynamic>.from(p)).toList();
    var delta=0;
    var conflict=false;
    final identities=<String>{};
    for(final edit in pendingEdits){
      if (edit['_queue_state'] == 'conflict') {
        conflict = true; // Show original receipt; never project rejected data.
        continue;
      }
      final id=edit['payment_id']?.toString()??'';
      if(id.isEmpty||!identities.add(id)){conflict=true;continue;}
      final i=payments.indexWhere((p)=>p['id']?.toString()==id &&
          p['state']?.toString()=='pending' && p['_local_pending_payment']!=true);
      if(i<0){conflict=true;continue;}
      final previous=payments[i];
      final version=int.tryParse(previous['row_version']?.toString()??'');
      final expected=int.tryParse(edit['expected_row_version']?.toString()??'');
      if (expected != null && (version == null || version != expected)) {
        conflict=true;continue;
      }
      if (expected == null &&
          ((num.tryParse(edit['original_amount_cents']?.toString() ?? '') ?? -1)
                  .round() != (_number(previous['amount']) * 100).round() ||
           edit['original_method_id']?.toString() !=
                  previous['payment_method_id']?.toString() ||
           !_sameEnteredAt(edit['original_entered_at']?.toString(),
                  previous['entered_at']?.toString()))) {
        conflict=true;continue;
      }
      final newCents=(num.tryParse(edit['amount_cents'].toString())??0).round();
      if(newCents<=0){conflict=true;continue;}
      delta+=newCents-(_number(previous['amount'])*100).round();
      payments[i]={
        ...previous,
        'amount':newCents/100,
        'payment_method_id':edit['method_id'],
        'payment_method_name':edit['method_name'],
        'payment_date':edit['payment_date'],
        'pending_sync':true,
        '_local_pending_edit':true,
      };
    }
    updated['pending_payment']=(_number(detail['pending_payment'])*100).round()/100 +
      delta/100;
    updated['payments']=payments;
    if(conflict) updated['_payment_reconciliation_required']=true;
    return updated;
  }

  /// Equivalent timestamps can have different zone/fractional formats.
  static bool _sameEnteredAt(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    final first = DateTime.tryParse(a);
    final second = DateTime.tryParse(b);
    return first != null && second != null && first.isAtSameMomentAs(second);
  }

  /// Owner-only UI may discard a local receipt that is proven never sent.
  /// A submitted/uncertain receipt cannot be removed through this operation.
  Future<void> deleteNeverSubmittedPayment(
    String businessId, String invoiceId, String operationId,
  ) async {
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        """SELECT id,state,attempt_count,last_attempt_at,payload_json
        FROM sync_outbox WHERE business_id=? AND entity_id=?
          AND entity_type='invoice_payment_received'""",
        variables: [Variable<String>(businessId),Variable<String>(invoiceId)],
      ).get();
      final matched = rows.where((row) {
        try {
          final p = jsonDecode(row.read<String>('payload_json')) as Map;
          return p['operation_id']?.toString() == operationId;
        } catch (_) { return false; }
      }).toList();
      if (matched.length != 1) {
        throw StateError('Local payment not found. Reload before removing.');
      }
      final row = matched.single;
      final p = Map<String,dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map);
      if (row.read<String>('state') != 'pending' ||
          row.read<int>('attempt_count') != 0 ||
          row.readNullable<int>('last_attempt_at') != null ||
          p['replay_attempted'] == true ||
          (p['server_payment_id']?.toString().isNotEmpty ?? false)) {
        throw StateError('This payment may have reached the server. '
            'Removal requires verified reconciliation.');
      }
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id=?', [row.read<int>('id')]);
    });
  }

  /// Replace a local invoice reference only after the authoritative server
  /// document has been saved; preserve each payment operation UUID.
  Future<void> remapInvoice(
    String businessId,
    String localId,
    String serverId,
  ) async {
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        """SELECT id,payload_json FROM sync_outbox WHERE business_id=?
        AND entity_type='invoice_payment_received' AND entity_id=?""",
        variables: [Variable<String>(businessId), Variable<String>(localId)],
      ).get();
      for (final row in rows) {
        final payload = Map<String,dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        payload['invoice_id'] = serverId;
        await _database.customStatement(
          'UPDATE sync_outbox SET entity_id=?, payload_json=? WHERE id=?',
          [serverId,jsonEncode(payload),row.read<int>('id')],
        );
      }
    });
  }

  /// Retry replay with the *same* saved UUID, never the legacy non-idempotent
  /// payment API. Fail closed and retain the row when server support is absent.
  Future<void> flush(
    String businessId, {
    Future<String> Function(String businessId, String invoiceId, num amount,
            String methodId, String operationId)? submitPayment,
    Future<Map<String, dynamic>> Function(String businessId, String invoiceId)?
        fetchInvoice,
    Future<void> Function(String businessId, String invoiceId,
            Map<String, dynamic> detail)? cacheInvoice,
  }) {
    // Multiple sync triggers in the same app process share one replay.
    // The database and server operation UUID remain the durable safety nets.
    final active = _activeFlushes[_database] ??= {};
    final existing = active[businessId];
    if (existing != null) return existing;
    final work = _flushInternal(
      businessId,
      submitPayment: submitPayment,
      fetchInvoice: fetchInvoice,
      cacheInvoice: cacheInvoice,
    );
    active[businessId] = work;
    return work.whenComplete(() {
      if (identical(active[businessId], work)) {
        active.remove(businessId);
      }
    });
  }

  Future<void> _flushInternal(
    String businessId, {
    Future<String> Function(String businessId, String invoiceId, num amount,
            String methodId, String operationId)? submitPayment,
    Future<Map<String, dynamic>> Function(String businessId, String invoiceId)?
        fetchInvoice,
    Future<void> Function(String businessId, String invoiceId,
            Map<String, dynamic> detail)? cacheInvoice,
  }) async {
    final rows = await _database.customSelect(
      """SELECT id,entity_id,payload_json FROM sync_outbox
      WHERE business_id=? AND entity_type='invoice_payment_received'
      AND state IN ('pending','inflight') ORDER BY id""",
      variables: [Variable<String>(businessId)],
    ).get();
    final blockedInvoices = <String>{};
    for (final row in rows) {
      final id = row.read<int>('id');
      final invoiceId = row.read<String>('entity_id');
      if (invoiceId.startsWith('local-')) continue;
      if (blockedInvoices.contains(invoiceId)) continue;
      final payload = Map<String,dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: id,
        );
        final amount = (payload['amount_cents'] as num) / 100;
        final methodId = payload['method_id'].toString();
        final operationId = payload['operation_id'].toString();
        // Record uncertainty before the network call: a lost response or
        // process interruption can happen after the server accepted payment.
        payload['replay_attempted'] = true;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [jsonEncode(payload), id],
        );
        final paymentId = await LocalJobQuarantine.guardReplay(
          _database,
          businessId,
          () => submitPayment != null
              ? submitPayment(
                  businessId, invoiceId, amount, methodId, operationId)
              : payload['payment_date'] != null
                  ? _api.addPendingInvoicePaymentOnceV2(
                      businessId, invoiceId,
                      amount: amount, methodId: methodId,
                      operationId: operationId,
                      paymentDate: payload['payment_date'].toString(),
                      localEditHistory: payload['local_edit_history'] is List
                          ? List<dynamic>.from(payload['local_edit_history'] as List)
                          : const [],
                    )
                  : _api.addPendingInvoicePaymentOnce(
                  businessId, invoiceId,
                  amount: amount, methodId: methodId, operationId: operationId,
                ),
          outboxId: id,
        );
        if (paymentId.trim().isEmpty || paymentId == 'null') {
          throw StateError('Server did not acknowledge the payment identity.');
        }
        // Persist acceptance before refreshing. Another screen may already see
        // this payment even when the refresh below fails or the app restarts.
        // Keeping the server ID lets projection deduplicate that accepted row.
        payload['server_payment_id'] = paymentId;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [jsonEncode(payload), id],
        );
        // A server acknowledgement is not sufficient to remove the local
        // receipt from the outbox. Preserve it until the refreshed server
        // invoice proves that the payment is represented in its aggregates.
        // A missing/failed refresh will safely retry with the same UUID.
        final detail = fetchInvoice != null
            ? await fetchInvoice(businessId, invoiceId)
            : await _api.documentDetail(businessId, invoiceId);
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: id,
        );
        final present = serverAcknowledgesPayment(detail, paymentId);
        if (!present) {
          // A finalized payment can permanently lose its pending ID. Retain
          // that receipt and stop later payments for this invoice, but do not
          // let its ambiguity starve unrelated invoices in the business queue.
          blockedInvoices.add(invoiceId);
          throw StateError(
            'Server accepted payment but invoice detail has not reconciled yet.',
          );
        }
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: id,
          );
          if (cacheInvoice != null) {
            await cacheInvoice(businessId, invoiceId, detail);
          } else {
            final cache = LocalDocumentDetailCache(database: _database);
            final cached = await cache.load(businessId, invoiceId);
            final refreshed = Map<String, dynamic>.from(detail);
            // Warranty detail has its own endpoint. A payment refresh must not
            // erase the separately cached warranty needed while disconnected.
            if (!refreshed.containsKey('offline_warranty_detail') &&
                cached != null && cached.containsKey('offline_warranty_detail')) {
              refreshed['offline_warranty_detail'] =
                  cached['offline_warranty_detail'];
            }
            await cache.save(businessId, invoiceId, refreshed);
          }
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id=?',
            [id],
          );
        });
      } catch (error) {
        await _database.customStatement(
          """UPDATE sync_outbox SET state='pending',
          attempt_count=attempt_count+1,last_error=? WHERE id=?""",
          [error.toString(),id],
        );
        if (blockedInvoices.contains(invoiceId)) continue;
        break;
      }
    }
  }

  /// Replay corrections to the same pending payment UUID; no new receipt.
  /// Never send a correction while that invoice's offline tax update remains
  /// unresolved. The payment amount could exceed the old server invoice total.
  ///
  /// A legacy cached receipt without row_version is editable locally, but
  /// may be submitted only if the server has a pristine matching version 1.
  /// Once a send has possibly occurred, later runs verify the answer by UUID,
  /// amount, method, date and version. They NEVER send a second request.
  Future<void> flushPendingServerEdits(String businessId) async {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    final rows = await _database.customSelect(
      """SELECT id,entity_id FROM sync_outbox
      WHERE business_id=? AND entity_type='invoice_pending_payment_edit'
      AND state IN ('pending','inflight') ORDER BY id""",
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      if (BriskersConnectionModeController.instance.forceOffline) return;
      final id = row.read<int>('id');
      final invoiceId = row.read<String>('entity_id');
      if (invoiceId.startsWith('local-')) continue;

      // Invoice tax must reach the server before its increased payment can.
      // Neither tax nor receipt is silently changed to unblock the other.
      final blocked = await _database.customSelect(
        """SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=?
           AND entity_type='invoice_tax_edit'
           AND state IN ('pending','inflight','conflict') LIMIT 1""",
        variables: [Variable<String>(businessId),Variable<String>(invoiceId)],
      ).get();
      if (blocked.isNotEmpty) continue;

      var mayHaveSent = false;
      try {
        await LocalJobQuarantine.assertReplayAllowed(
            _database, businessId, outboxId: id);
        final current = await _database.customSelect(
          """SELECT state,attempt_count,payload_json FROM sync_outbox
             WHERE id=? AND business_id=?""",
          variables: [Variable<int>(id),Variable<String>(businessId)],
        ).getSingleOrNull();
        if (current == null) continue;
        final payload = Map<String,dynamic>.from(
            jsonDecode(current.read<String>('payload_json')) as Map);
        final paymentId = payload['payment_id']?.toString() ?? '';
        final amountCents = (num.tryParse(
            payload['amount_cents']?.toString() ?? '') ?? -1).round();
        if (paymentId.isEmpty || amountCents <= 0) {
          throw StateError('Payment correction identity is incomplete.');
        }
        final desiredMethod = payload['method_id']?.toString() ?? '';
        final desiredDate = payload['payment_date']?.toString() ?? '';
        var expectedVersion = int.tryParse(
            payload['resolved_row_version']?.toString() ??
            payload['expected_row_version']?.toString() ?? '');
        final attempted = current.read<String>('state') == 'inflight' ||
            current.read<int>('attempt_count') > 0;

        final server = await _api.documentDetailV4(businessId,invoiceId);
        final payments = server['payments'] is List
            ? (server['payments'] as List).whereType<Map>().toList()
            : const <Map>[];
        final matches = payments.where((p) =>
            p['id']?.toString() == paymentId &&
            p['state']?.toString() == 'pending').toList();
        final serverPayment = matches.length == 1 ? matches.single : null;
        final serverVersion = int.tryParse(
            serverPayment?['row_version']?.toString() ?? '');
        final acknowledged = serverPayment != null &&
            expectedVersion != null &&
            serverVersion == expectedVersion + 1 &&
            (_number(serverPayment['amount']) * 100).round() == amountCents &&
            serverPayment['payment_method_id']?.toString() == desiredMethod &&
            serverPayment['payment_date']?.toString() == desiredDate;

        if (acknowledged) {
          // Authoritative read, local durable cache, then retirement by ID.
          await _database.transaction(() async {
            await LocalJobQuarantine.assertReplayAllowed(
                _database,businessId,outboxId:id);
            final cache = LocalDocumentDetailCache(database:_database);
            final oldDetail = await cache.load(businessId,invoiceId);
            final refreshed = Map<String,dynamic>.from(server);
            if (!refreshed.containsKey('offline_warranty_detail') &&
                oldDetail?['offline_warranty_detail'] != null) {
              refreshed['offline_warranty_detail'] =
                  oldDetail!['offline_warranty_detail'];
            }
            await cache.save(businessId,invoiceId,refreshed);
            await _database.customStatement(
              'DELETE FROM sync_outbox WHERE id=?',[id]);
          });
          continue;
        }

        if (attempted) {
          // Response loss or conflict: never issue this non-idempotent
          // correction a second time. Keep a visible review requirement.
          await _database.customStatement(
            """UPDATE sync_outbox SET state='conflict',last_error=?
               WHERE id=?""",
            ['Prior correction outcome not confirmed; owner review required.',id],
          );
          continue;
        }
        if (serverPayment == null || serverVersion == null) {
          await _database.customStatement(
            "UPDATE sync_outbox SET state='conflict',last_error=? WHERE id=?",
            ['Server receipt is no longer pending or version is unavailable.',id],
          );
          continue;
        }

        if (expectedVersion == null) {
          final originalCents = (num.tryParse(
              payload['original_amount_cents']?.toString() ?? '') ?? -1).round();
          final originalMethod = payload['original_method_id']?.toString();
          final originalEntered = payload['original_entered_at']?.toString();
          // Without a cached version, require a never-edited payment and
          // compare its immutable original business receipt snapshot.
          final pristine = serverVersion == 1 &&
              originalCents == (_number(serverPayment['amount']) * 100).round() &&
              originalMethod == serverPayment['payment_method_id']?.toString() &&
              _sameEnteredAt(originalEntered,
                  serverPayment['entered_at']?.toString()) &&
              (payload['original_payment_date'] == null ||
               payload['original_payment_date']?.toString() ==
                   serverPayment['payment_date']?.toString());
          if (!pristine) {
            await _database.customStatement(
              "UPDATE sync_outbox SET state='conflict',last_error=? WHERE id=?",
              ['Original payment has changed. Refresh and review.',id],
            );
            continue;
          }
          expectedVersion = serverVersion;
        } else if (serverVersion != expectedVersion) {
          await _database.customStatement(
            "UPDATE sync_outbox SET state='conflict',last_error=? WHERE id=?",
            ['Payment was revised on another device. Review required.',id],
          );
          continue;
        }
        if (BriskersConnectionModeController.instance.forceOffline) return;

        final versionToSend = expectedVersion;
        // Save which version we intended to change BEFORE contacting the
        // network, so a lost response can be verified on the next run.
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
              _database,businessId,outboxId:id);
          final updated = <String,dynamic>{
            ...payload,
            'resolved_row_version':versionToSend,
          };
          await _database.customStatement(
            """UPDATE sync_outbox SET payload_json=?,state='inflight',
               attempt_count=attempt_count+1,last_attempt_at=? WHERE id=?
               AND state='pending' AND attempt_count=0""",
            [jsonEncode(updated),
             DateTime.now().toUtc().millisecondsSinceEpoch~/1000,id],
          );
        });
        mayHaveSent = true;
        try {
          await LocalJobQuarantine.guardReplay(
            _database,businessId,() =>
              _api.updatePendingInvoicePaymentV2(
                businessId,paymentId,amount:amountCents/100,
                methodId:desiredMethod,paymentDate:desiredDate,
                expectedRowVersion:versionToSend,
              ),
            outboxId:id,
          );
        } catch (_) {
          // A reply may be lost after commit. Read server before deciding.
        }
        final after = await _api.documentDetailV4(businessId,invoiceId);
        final afterPayments = after['payments'] is List
            ? (after['payments'] as List).whereType<Map>().toList()
            : const <Map>[];
        final accepted = afterPayments.where((p) =>
          p['id']?.toString() == paymentId &&
          p['state']?.toString() == 'pending' &&
          int.tryParse(p['row_version']?.toString() ?? '') == versionToSend+1 &&
          (_number(p['amount'])*100).round()==amountCents &&
          p['payment_method_id']?.toString()==desiredMethod &&
          p['payment_date']?.toString()==desiredDate).toList();
        if (accepted.length != 1) {
          throw StateError('Payment edit outcome uncertain; no automatic retry.');
        }
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
              _database,businessId,outboxId:id);
          final cache = LocalDocumentDetailCache(database:_database);
          final oldDetail = await cache.load(businessId,invoiceId);
          final refreshed = Map<String,dynamic>.from(after);
          if (!refreshed.containsKey('offline_warranty_detail') &&
              oldDetail?['offline_warranty_detail'] != null) {
            refreshed['offline_warranty_detail'] =
                oldDetail!['offline_warranty_detail'];
          }
          await cache.save(businessId,invoiceId,refreshed);
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id=?',[id]);
        });
      } catch (error) {
        await _database.customStatement(
          """UPDATE sync_outbox SET
            state=CASE WHEN state='inflight' OR ?=1
              THEN 'inflight' ELSE state END,
            last_error=? WHERE id=?""",
          [mayHaveSent?1:0,error.toString(),id],
        );
        break;
      }
    }
  }

  Future<List<Map<String, dynamic>>> pendingForInvoice(
    String businessId,
    String invoiceId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT payload_json FROM sync_outbox
      WHERE business_id = ? AND entity_id = ?
        AND entity_type = 'invoice_payment_received'
        AND state IN ('pending', 'inflight')
      ORDER BY id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(invoiceId),
      ],
    ).get();
    return rows.map((row) {
      final decoded = jsonDecode(row.read<String>('payload_json')) as Map;
      return Map<String, dynamic>.from(decoded);
    }).toList();
  }
}


