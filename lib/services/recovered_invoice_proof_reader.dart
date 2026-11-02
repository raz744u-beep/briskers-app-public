import '../core/connection_mode.dart';
import 'briskers_api.dart';
import 'offline_invoice_recovery_proof.dart';

/// Fetches live, authoritative proof before any local recovery mutation.
/// Never accepts a cached/projected receipt or silently falls back offline.
/// No invoice or payment write is performed by this reader.
class RecoveredInvoiceProofReader {
  const RecoveredInvoiceProofReader({BriskersApi api = const BriskersApi()})
      : _api = api;

  final BriskersApi _api;

  Future<Map<String, dynamic>> verifiedInvoice({
    required bool isOwner,
    required String businessId,
    required String invoiceId,
    required String invoiceOperationId,
    required String paymentOperationId,
    required String methodId,
    required String paymentDate,
    required int totalCents,
    required int paymentCents,
    required int lineCount,
  }) async {
    if (!isOwner) throw StateError('Owner permission required.');
    if (BriskersConnectionModeController.instance.forceOffline) {
      throw StateError('Cannot verify an invoice while Force Offline is enabled.');
    }
    final detail = await _api.documentDetail(businessId, invoiceId);
    final raw = detail['payments'];
    if (raw is! List) {
      throw StateError('Server receipt identities are unavailable.');
    }
    final receipts = raw.whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry)).toList();
    OfflineInvoiceRecoveryProof.verify(
      owner: isOwner,
      invoice: detail,
      payments: receipts,
      businessId: businessId,
      invoiceId: invoiceId,
      invoiceOperationId: invoiceOperationId,
      paymentOperationId: paymentOperationId,
      totalCents: totalCents,
      paymentCents: paymentCents,
      paymentMethodId: methodId,
      paymentDate: paymentDate,
      expectedLineCount: lineCount,
    );
    return detail;
  }
}
