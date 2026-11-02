import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';

void main() {
  test('corrected server-pending receipt changes display, not identity', () {
    final original = [
      <String,dynamic>{
        'receipt_id':'pending-id','invoice_id':'invoice',
        'receipt_state':'pending',
        'amount':175.60,'invoice_total':175.60,
        'payment_method':'Debit Card','transaction_date':'2026-10-17',
        'received_at':'2026-10-17T12:00:00Z','coverage':'paid'
      },
    ];
    final updated=InvoicePaymentFeed.overlayPendingPaymentEdits(original,[
      {'invoice_id':'invoice','payment_id':'pending-id',
       'amount_cents':15025,'method_name':'Cash','payment_date':'2026-10-16'}
    ]);
    expect(updated,hasLength(1));
    expect(updated.single['receipt_id'],'pending-id');
    expect(updated.single['transaction_date'],'2026-10-16');
    expect(updated.single['payment_method'],'Cash');
    expect(updated.single['amount'],150.25);
    expect(updated.single['coverage'],'partial');
    expect(original.single['amount'],175.60);
  });

  test('unknown payment identity cannot create or change a receipt', () {
    final original=[<String,dynamic>{
      'receipt_id':'posted-id','invoice_id':'invoice',
      'receipt_state':'posted','amount':300,'invoice_total':300,
    }];
    final updated=InvoicePaymentFeed.overlayPendingPaymentEdits(original,[
      {'invoice_id':'invoice','payment_id':'posted-id',
       'amount_cents':100,'method_name':'Cash','payment_date':'2026-10-16'},
      {'invoice_id':'invoice','payment_id':'missing',
       'amount_cents':25,'method_name':'Cash','payment_date':'2026-10-16'},
    ]);
    expect(updated,hasLength(1));
    expect(updated.single['amount'],300);
    expect(updated.single['receipt_state'],'posted');
  });
}
