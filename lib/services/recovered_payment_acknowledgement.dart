import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

/// Retire a quarantined receipt only after an independent, fresh server read.
/// Never use local cached/projected invoice data or amount-only matching.
class RecoveredPaymentAcknowledgement {
  RecoveredPaymentAcknowledgement({
    BriskersLocalDatabase? database,
    BriskersApi api = const BriskersApi(),
  }) : _db = database ?? localDatabase, _api = api;

  final BriskersLocalDatabase _db;
  final BriskersApi _api;

  Future<void> acknowledge({
    required bool isOwner,
    required String businessId,
    required String invoiceId,
    required String paymentOperationId,
    required String paymentId,
    required int amountCents,
    required String methodId,
    required String paymentDate,
  }) async {
    if (!isOwner) throw StateError('Owner permission required.');
    if (businessId.isEmpty || invoiceId.isEmpty ||
        paymentOperationId.isEmpty || paymentId.isEmpty ||
        amountCents <= 0 || methodId.isEmpty || paymentDate.isEmpty ||
        invoiceId.startsWith('local-')) {
      throw StateError('Recovery receipt identity incomplete.');
    }
    // Call the API here, not in UI code. An outage fails without queue edits.
    final server = await _api.documentDetail(businessId, invoiceId);
    if (server['id']?.toString() != invoiceId ||
        server['status']?.toString() != 'issued') {
      throw StateError('Authoritative invoice does not match.');
    }
    final raw = server['payments'];
    if (raw is! List) {
      throw StateError('Server payment identities unavailable.');
    }
    final matches = raw.whereType<Map>().where((payment) {
      final value = payment['amount'];
      final amount = value is num ? value
          : num.tryParse(value?.toString() ?? '');
      return payment['id']?.toString() == paymentId &&
          (payment['operation_id']?.toString() == paymentOperationId ||
           payment['client_operation_id']?.toString() == paymentOperationId) &&
          payment['payment_date']?.toString() == paymentDate &&
          (payment['payment_method_id']?.toString() == methodId ||
           payment['method_id']?.toString() == methodId) &&
          payment['pending_sync'] != true &&
          payment['_local_pending_payment'] != true &&
          amount != null && amount.isFinite &&
          (amount * 100).round() == amountCents;
    }).toList();
    if (matches.length != 1 || raw.length != 1) {
      throw StateError('Verified server payment identity not available.');
    }
    await _db.transaction(() async {
      final rows = await _db.customSelect(
        '''SELECT id,state,payload_json FROM sync_outbox
           WHERE business_id=? AND entity_type='invoice_payment_received'
             AND entity_id=?''',
        variables:[Variable<String>(businessId),Variable<String>(invoiceId)],
      ).get();
      if (rows.length != 1 || rows.single.read<String>('state') != 'conflict') {
        throw StateError('Original quarantined receipt not found.');
      }
      final payload = jsonDecode(rows.single.read<String>('payload_json'));
      if (payload is! Map ||
          payload['operation_id'] != paymentOperationId ||
          payload['invoice_id'] != invoiceId ||
          payload['amount_cents'] != amountCents ||
          payload['method_id'] != methodId ||
          payload['payment_date'] != paymentDate) {
        throw StateError('Local payment changed after server verification.');
      }
      await _db.customStatement(
        '''DELETE FROM sync_outbox
           WHERE id=? AND business_id=? AND state='conflict'
             AND entity_type='invoice_payment_received' ''',
        [rows.single.read<int>('id'),businessId],
      );
    });
  }
}
