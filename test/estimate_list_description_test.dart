import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/estimate_list_description.dart';

void main() {
  test('prefers explicit description, never duplicates job title', () {
    expect(estimateListDescription({
      'title': 'Brake service',
      'estimate_description': 'Front rotor and pads',
    }), 'Front rotor and pads');
    expect(estimateListDescription({
      'title': 'Brake service',
      'description': 'Brake service',
    }), '');
  });

  test('uses existing first two detail line names for old estimates', () {
    expect(estimateListDescription({'job_title': 'Engine repair'}, detail: {
      'lines': [
        {'line_kind': 'discount', 'name': 'Coupon'},
        {'line_kind': 'labor', 'name': '  Replace   water pump  '},
        {'line_kind': 'part', 'name': 'Coolant'},
        {'line_kind': 'part', 'name': 'Hose'},
      ],
    }), 'Replace water pump • Coolant');
  });

  test('missing description remains blank, never invents repair', () {
    expect(estimateListDescription({'job_title': 'Check vehicle'}), '');
    expect(estimateListDescription({}, detail: {'lines': []}), '');
  });
}
