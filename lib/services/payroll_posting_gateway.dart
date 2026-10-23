import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/payroll_payment_contract.dart';
import '../core/supabase_config.dart';
import 'local_payroll_outbox.dart';
import 'payroll_authoritative_sync.dart';

/// Prepared transport for the private reviewed v1 contract. Deliberately not
/// wired into the app. Deployment approval requires a separate reviewed source
/// change; a server response or user setting cannot enable this gate.
final class PayrollPostingGatewayV1
    implements
        PayrollPostingGateway,
        PayrollAuthoritativeGateway,
        PayrollPostingActivation {
  PayrollPostingGatewayV1({
    required this.businessId,
    required this.isContextCurrent,
    required this.readProofBytes,
  });
  final String businessId;
  final bool Function() isContextCurrent;
  final Future<Uint8List> Function(Map<String, dynamic>) readProofBytes;

  bool get _deploymentApproved => false;
  @override
  bool get canQueueOffline => _deploymentApproved && isContextCurrent();
  void _guard([Map<String, dynamic>? payload]) {
    if (!_deploymentApproved || !isContextCurrent()) {
      throw StateError(
        'Payroll backend deployment is not approved or session changed.',
      );
    }
    if (payload != null &&
        (payload['business_id'] != businessId ||
            !LocalPayrollOutbox.isUuid(
              payload['operation_id']?.toString() ?? '',
            ))) {
      throw StateError('Payroll scope mismatch.');
    }
  }

  @override
  Future<bool> supportsReviewedPayrollV1(String businessId) async {
    if (!_deploymentApproved ||
        !isContextCurrent() ||
        businessId != this.businessId) {
      return false;
    }
    final value = await networkSupabase.rpc(
      'briskers_payroll_capabilities_v1',
      params: {'b': businessId},
    );
    _guard();
    return value is Map &&
        value['protocol'] == 1 &&
        value['posting_enabled'] == true &&
        value['proof_verifier'] == 1;
  }

  @override
  Future<String> registerMethod(PayrollPaymentMethod method) async {
    _guard();
    if (method.businessId != businessId ||
        !LocalPayrollOutbox.isUuid(method.id)) {
      throw StateError('Durable local registration key required.');
    }
    final result = await networkSupabase.rpc(
      'briskers_register_payroll_method_v1',
      params: {
        'b': businessId,
        'client_id': method.id,
        'label': method.label,
        'kind': method.kind.name,
      },
    );
    _guard();
    if (result is! String || !LocalPayrollOutbox.isUuid(result)) {
      throw StateError('Invalid method registration receipt.');
    }
    return result;
  }

  @override
  Future<void> prepare(Map<String, dynamic> frozenPayload) async {
    _guard(frozenPayload);
    await networkSupabase.rpc(
      'briskers_prepare_payroll_v1',
      params: {'p': frozenPayload},
    );
    _guard(frozenPayload);
  }

  @override
  Future<void> uploadAndVerifyProof(Map<String, dynamic> frozenPayload) async {
    _guard(frozenPayload);
    final bytes = await readProofBytes(frozenPayload);
    _guard(frozenPayload);
    final digest = sha256.convert(bytes).toString();
    if (bytes.length != frozenPayload['proof_size'] ||
        digest != frozenPayload['proof_sha256']) {
      throw StateError('Check photo changed after submission.');
    }
    final mime = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50
        ? 'image/png'
        : bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8
        ? 'image/jpeg'
        : null;
    if (mime == null) {
      throw StateError('This backend requires a JPEG or PNG Check photo.');
    }
    final key = '$businessId/${frozenPayload['operation_id']}/$digest';
    try {
      await networkSupabase.storage
          .from('briskers-payroll-private')
          .uploadBinary(
            key,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } on StorageException catch (error) {
      // A retry can encounter an immutable existing object. Its actual bytes
      // must still pass the trusted verifier; duplicate status is not proof.
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
    }
    _guard(frozenPayload);
    final result = await networkSupabase.functions.invoke(
      'verify-payroll-proof-v1',
      body: {
        'business_id': businessId,
        'operation_id': frozenPayload['operation_id'],
      },
    );
    _guard(frozenPayload);
    if (result.status != 200 ||
        result.data is! Map ||
        result.data['verified'] != true) {
      throw StateError('Check photo is awaiting server verification.');
    }
  }

  @override
  Future<PayrollPostingReceipt> post(Map<String, dynamic> frozenPayload) async {
    _guard(frozenPayload);
    final result = await networkSupabase.rpc(
      'briskers_post_payroll_v1',
      params: {'p': frozenPayload},
    );
    _guard(frozenPayload);
    if (result is! Map ||
        result['amount_cents'] is! int ||
        !['posted', 'void'].contains(result['status'])) {
      throw StateError('Invalid authoritative payroll receipt.');
    }
    return PayrollPostingReceipt(
      businessId: result['business_id'] as String,
      operationId: result['operation_id'] as String,
      transactionId: result['transaction_id'] as String,
      amountCents: result['amount_cents'] as int,
      status: result['status'] as String,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchPayrollState(String businessId) async {
    _guard();
    if (businessId != this.businessId) {
      throw StateError('Payroll scope mismatch.');
    }
    final result = await networkSupabase.rpc(
      'briskers_payroll_state_v1',
      params: {'b': businessId},
    );
    _guard();
    if (result is! Map) throw StateError('Invalid payroll state.');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<void> applyCatalogMutation(
    String businessId,
    Map<String, dynamic> mutation,
  ) async {
    _guard();
    if (businessId != this.businessId) {
      throw StateError('Payroll scope mismatch.');
    }
    await networkSupabase.rpc(
      'briskers_mutate_payroll_catalog_v1',
      params: {'b': businessId, 'p': mutation},
    );
    _guard();
  }
}
