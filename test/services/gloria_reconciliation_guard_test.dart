import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/gloria_reconciliation_guard.dart';

void main() {
  Map<String, dynamic> local() => {
    'id': GloriaReconciliationGuard.localInvoiceId,
    'customer_id': GloriaReconciliationGuard.localCustomerId,
    'job_id': GloriaReconciliationGuard.localJobId,
    'total': 7882.113299999999,
  };
  Map<String, dynamic> server() => {
    'id': GloriaReconciliationGuard.invoiceId,
    'job_id': GloriaReconciliationGuard.jobId,
    'business_id': GloriaReconciliationGuard.businessId,
    'document_number': '6359',
    'status': 'issued',
    'net_amount': 7181.88,
    'tax_amount': 700.23,
    'total_amount': 7882.11,
    'line_count': 18,
    'offline_operation_id': GloriaReconciliationGuard.operationId,
  };
  Map<String, dynamic> receipt() => {
    'operation_id': GloriaReconciliationGuard.paymentOperationId,
    'invoice_id': GloriaReconciliationGuard.localInvoiceId,
    'amount_cents': 300000,
    'method_id': '67018807-21a1-4a60-87dd-a5b90b662b05',
    'payment_date': '2026-10-19',
  };
  Map<String, dynamic> serverReceipt() => {
    'operation_id': GloriaReconciliationGuard.paymentOperationId,
    'invoice_id': GloriaReconciliationGuard.invoiceId,
    'amount': 3000.00,
    'method_id': '67018807-21a1-4a60-87dd-a5b90b662b05',
    'payment_date': '2026-10-19',
  };
  void run({bool owner = true, Map<String, dynamic>? l,
    Map<String, dynamic>? s, Map<String, dynamic>? p,
    List<Map<String, dynamic>>? payments}) {
    GloriaReconciliationGuard.validate(
      isOwner: owner,
      requestedBusinessId: GloriaReconciliationGuard.businessId,
      localInvoice: l ?? local(),
      authoritativeInvoice: s ?? server(),
      localPaymentOutbox: p ?? receipt(),
      authoritativePayments: payments ?? [serverReceipt()],
    );
  }
  test('accepts verified issued invoice and original payment', () => run());
  test('rejects non-owner', () => expect(() => run(owner: false), throwsStateError));
  test('rejects wrong status', () => expect(() => run(s: server()..['status']='draft'), throwsStateError));
  test('rejects wrong total', () => expect(() => run(s: server()..['tax_amount']=700.22), throwsStateError));
  test('rejects missing receipt', () => expect(() => run(payments: []), throwsStateError));
  test('rejects duplicate receipt', () => expect(() => run(payments: [serverReceipt(), serverReceipt()]), throwsStateError));
  test('rejects different payment operation', () => expect(() => run(p: receipt()..['operation_id']='other'), throwsStateError));
  test('rejects unverified local projection', () => expect(() => run(payments: [serverReceipt()..['pending_sync']=true]), throwsStateError));
}
