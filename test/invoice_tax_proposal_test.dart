import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/invoice_tax_proposal.dart';

void main() {
  test('Barbara invoice: current-rate preview corrects old default tax', () {
    final result = InvoiceTaxProposal.preview(rate: 0.0975, lines: [
      {'line_kind': 'item', 'tax_mode': 'default',
       'quantity': 1, 'unit_price': 160, 'tax_rate': 0.0925},
    ]);
    expect(result['old_tax'], 14.80);
    expect(result['new_tax'], 15.60);
    expect(result['new_total'], 175.60);
    expect(result['changed_count'], 1);
  });
  test('exempt and custom lines are untouched, default updates', () {
    final result = InvoiceTaxProposal.preview(rate: 0.0975, lines: [
      {'line_kind':'item','tax_mode':'default','quantity':1,
       'unit_price':100,'tax_rate':0.0925},
      {'line_kind':'item','tax_mode':'exempt','quantity':1,
       'unit_price':50,'tax_rate':0},
      {'line_kind':'item','tax_mode':'custom','quantity':1,
       'unit_price':20,'tax_rate':0.05},
    ]);
    expect(result['changed_count'], 1);
    expect(result['new_tax'], 10.75);
    expect(result['new_total'], 180.75);
  });
  test('unknown historical exemptions are not silently overwritten', () {
    expect(() => InvoiceTaxProposal.preview(rate:0.0975, lines:[
      {'line_kind':'item', 'quantity':1,'unit_price':160,'tax_rate':0.0925},
    ]), throwsStateError);
  });
  test('discount ordering requires server verification', () {
    expect(() => InvoiceTaxProposal.preview(rate:0.0975, lines:[
      {'line_kind':'discount','tax_mode':'default',
       'quantity':1,'unit_price':-10,'tax_rate':0},
    ]), throwsStateError);
  });
}
