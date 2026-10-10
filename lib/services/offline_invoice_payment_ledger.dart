import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Durable *local* payment capture. This class never posts income or invokes
/// a server payment RPC; replay requires a separate idempotent server endpoint.
///
/// Outbox payloads are the source of truth until the server acknowledges them.
/// Use [pendingForInvoice] after restart to rebuild the invoice's local display.
class OfflineInvoicePaymentLedger {
  OfflineInvoicePaymentLedger({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;
  final Random _random = Random.secure();

  static int cents(num value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'amount', 'Must be positive and finite');
    }
    return (value * 100).round();
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

  String _operationId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Only actually received cash may be captured here. Credit/debit card
  /// transactions require external processor approval; checks need their own
  /// validation policy. Finalization stays owner-only and online.
  Future<String> recordReceivedCash(
    String businessId,
    String invoiceId, {
    required num amount,
    required int remainingBeforePaymentCents,
    required String methodId,
  }) async {
    if (businessId.isEmpty || invoiceId.isEmpty || methodId.isEmpty) {
      throw ArgumentError('Business, invoice and cash method are required.');
    }
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
      'method_name': 'Cash',
      'amount_cents': amountCents,
      'received_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _database.transaction(() async {
      // Never submit this through the legacy add-payment RPC, which has no
      // operation-id idempotency argument. A dedicated server RPC is required.
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation, payload_json,
          base_row_version, state, attempt_count, created_at,
          last_attempt_at, last_error
        ) VALUES (?, 'invoice_payment_received', ?, 'record_cash', ?,
                  NULL, 'pending', 0, ?, NULL, NULL)
        ''',
        [businessId, invoiceId, jsonEncode(payload), now],
      );
    });
    return operationId;
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
