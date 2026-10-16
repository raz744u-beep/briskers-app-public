import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/invoice_labor_work_summary.dart';

void main() {
  group('Invoice labor from actual Briskers item encoding', () {
    final invoice = <String, dynamic>{
      'kind': 'invoice',
      'lines': <Map<String, dynamic>>[
        {'line_kind': 'item', 'name': 'Air Spring', 'description': 'Rear'},
        {'line_kind': 'item', 'name': 'Labor', 'description':
          'Replace rear air springs. Calibrate air suspension'},
        {'line_kind': 'item', 'name': 'Shop Supplies', 'description': null},
        {'line_kind': 'item', 'name': 'Suspension Valve'},
        {'line_kind': 'item', 'name': 'Air Compressor'},
        {'line_kind': 'item', 'name': 'Labor', 'description':
          'Replace airmatic compressor, valve block and filter'},
      ],
    };
    test('copies only explicitly Labor-named generic items', () {
      expect(invoiceLaborWorkSummary(invoice),
        'Replace rear air springs. Calibrate air suspension\n'
        'Replace airmatic compressor, valve block and filter');
    });
    test('does not overwrite manually typed notes', () {
      expect(appendInvoiceLaborWorkSummary(
        'Inspection completed',
        invoiceLaborWorkSummary(invoice)),
        startsWith('Inspection completed\n'));
    });
    test('does not duplicate a labor description already recorded', () {
      final work = 'Replace rear air springs. Calibrate air suspension';
      expect(appendInvoiceLaborWorkSummary(work, invoiceLaborWorkSummary(invoice)),
        '$work\nReplace airmatic compressor, valve block and filter');
    });
    test('copies normalized explicit labor rows from cached items', () {
      expect(invoiceLaborWorkSummary({
        'kind': 'invoice',
        'items': [
          {'line_kind': 'labor', 'name': 'Labor', 'description': 'Replace pump'},
          {'line_kind': 'item', 'name': 'Pump', 'description': 'Water pump'},
        ],
      }), 'Replace pump');
    });
    test('does not infer labor from ordinary text', () {
      expect(invoiceLaborWorkSummary({
        'kind': 'invoice',
        'lines': [
          {'line_kind': 'item', 'name': 'Oil pan',
            'description': 'Labor to replace oil pan'},
        ],
      }), isEmpty);
    });
  });
}
