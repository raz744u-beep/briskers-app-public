import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

/// Durable *local* payment capture. This class never posts income or invokes
/// a server payment RPC; replay requires a separate idempotent server endpoint.
///
/// Outbox payloads are the source of truth until the server acknowledges them.
/// Use [pendingForInvoice] after restart to rebuild the invoice's local display.
class OfflineInvoicePaymentLedger {
  OfflineInvoicePaymentLedger({BriskersLocalDatabase? database, BriskersApi api = const BriskersApi()})
      : _database = database ?? localDatabase, _api = api;

  final BriskersLocalDatabase _database;
  final BriskersApi _api;
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

  /// Record a payment already received or approved through its real channel.
  /// Briskers records the received payment only; it never processes cards.
  Future<String> recordReceivedPayment(
    String businessId,
    String invoiceId, {
    required num amount,
    required int remainingBeforePaymentCents,
    required String methodId,
    required String methodName,
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
  Future<void> flush(String businessId) async {
    final rows = await _database.customSelect(
      """SELECT id,entity_id,payload_json FROM sync_outbox
      WHERE business_id=? AND entity_type='invoice_payment_received'
      AND state IN ('pending','inflight') ORDER BY id""",
      variables: [Variable<String>(businessId)],
    ).get();
    for (final row in rows) {
      final id = row.read<int>('id');
      final invoiceId = row.read<String>('entity_id');
      if (invoiceId.startsWith('local-')) continue;
      final payload = Map<String,dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      try {
        final paymentId = await _api.addPendingInvoicePaymentOnce(
          businessId,
          invoiceId,
          amount: (payload['amount_cents'] as num) / 100,
          methodId: payload['method_id'].toString(),
          operationId: payload['operation_id'].toString(),
        );
        // A server acknowledgement is not sufficient to remove the local
        // receipt from the outbox. Preserve it until the refreshed server
        // invoice proves that the payment is represented in its aggregates.
        // A missing/failed refresh will safely retry with the same UUID.
        final detail = await _api.documentDetail(businessId, invoiceId);
        final payments = (detail['payments'] as List?) ?? const [];
        final present = payments.whereType<Map>().any(
          (p) => p['id']?.toString() == paymentId,
        );
        if (!present) {
          throw StateError(
            'Server accepted payment but invoice detail has not reconciled yet.',
          );
        }
        await _database.customStatement(
          'DELETE FROM sync_outbox WHERE id=?',
          [id],
        );
      } catch (error) {
        await _database.customStatement(
          """UPDATE sync_outbox SET state='pending',
          attempt_count=attempt_count+1,last_error=? WHERE id=?""",
          [error.toString(),id],
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
