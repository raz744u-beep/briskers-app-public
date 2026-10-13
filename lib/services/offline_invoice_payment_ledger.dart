import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_job_quarantine.dart';
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
        'entered_at': receipt['received_at'],
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
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final payload = <String, dynamic>{
      'operation_id': operationId,
      'invoice_id': invoiceId,
      'method_id': methodId,
      'method_name': method,
      'amount_cents': amountCents,
      'received_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _database.transaction(() async {
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
            const cache = LocalDocumentDetailCache();
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
