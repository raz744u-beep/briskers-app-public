import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/historical_invoice_labor_review.dart';

void main() {
  test('saved invoice labor displays without inferred payroll allocation', () {
    final invoice = <String,dynamic>{
      'id':'saved-invoice', 'document_number':'6359',
      'job_number':'J-40','document_date':'2026-11-06',
    };
    final detail = <String,dynamic>{
      'id':'saved-invoice', 'kind':'invoice', 'lines':[
        {'id':'labor1','name':'Labor','line_kind':'item',
         'description':'Replace front air struts','quantity':3.6},
        {'id':'part1','name':'Strut','line_kind':'part','quantity':2},
      ],
    };
    final before=Map<String,dynamic>.from(invoice);
    final labor=HistoricalInvoiceLaborReview.invoiceLaborLines(invoice,detail);
    expect(labor.length,1);
    expect(labor.single['description'],'Replace front air struts');
    expect(labor.single['hours'],3.6);
    expect(labor.single.containsKey('employee_id'),isFalse);
    expect(labor.single.containsKey('paid'),isFalse);
    expect(invoice,before);
  });

  test('estimate lines never appear as payroll invoice work', () {
    expect(HistoricalInvoiceLaborReview.invoiceLaborLines(
      {'id':'estimate'}, {'kind':'estimate','lines':[
        {'name':'Labor','line_kind':'item','quantity':9},
      ]}),isEmpty);
  });
}
