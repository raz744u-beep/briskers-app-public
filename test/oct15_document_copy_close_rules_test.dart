import 'package:briskers_app/services/document_copy_plan.dart';
import 'package:briskers_app/services/invoice_finalization_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice copy requires fresh job and drops financial identity', () {
    final original = {
      'kind': 'invoice', 'id': 'old', 'job_id': 'j-old',
      'customer_id': 'old-customer', 'vehicle_id': 'old-car',
      'document_number': '6346', 'status': 'closed', 'paid_amount': 100,
      'memo': 'Replace water pump',
      'lines': [{'id':'old-line','line_kind':'labor','name':'Service',
        'description':'Replace water pump','quantity':2,'unit_price':100,
        'tax_rate':0}],
    };
    final copy = DocumentCopyPlan.prepare(original,
        customerId:'new-customer',vehicleId:'new-car');
    expect(copy['requires_new_job'],isTrue);
    expect(copy['job_id'],isNull);
    expect(copy['document_number'],isNull);
    expect(copy['paid_amount'],0);
    expect(copy['customer_id'],'new-customer');
    expect((copy['lines'] as List).first.containsKey('id'),isFalse);
    expect(original['job_id'],'j-old');
  });

  test('converted estimate always copies as standalone editable draft', () {
    final copy = DocumentCopyPlan.prepare({
      'kind':'estimate','job_id':'old-job','converted':true,
      'lines':<Map<String,dynamic>>[],
    },customerId:'same-customer',vehicleId:null);
    expect(copy['job_id'],isNull);
    expect(copy['requires_new_job'],isFalse);
    expect(copy['converted'],isFalse);
    expect(copy['status'],'draft');
  });

  test('auto close requires owner completed job, posted full balance', () {
    bool eligible({bool owner=true,bool done=true,
      num finalized=125,num pending=0,bool reopened=false}) =>
      InvoiceFinalizationGuard.canAutoClose(
        isOwner:owner,jobCompleted:done,invoiceTotal:125,
        finalizedPayments:finalized,pendingPayments:pending,
        reopenedForCorrection:reopened);
    expect(eligible(),isTrue);
    expect(eligible(owner:false),isFalse);
    expect(eligible(done:false),isFalse);
    expect(eligible(finalized:0,pending:125),isFalse);
    expect(eligible(finalized:120),isFalse);
    expect(eligible(finalized:130),isFalse);
    expect(eligible(reopened:true),isFalse);
  });
}
