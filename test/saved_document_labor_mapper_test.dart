import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/saved_document_labor_mapper.dart';

void main() {
  test('J12 saved invoice labor maps to linked task candidates', () {
    final result = SavedDocumentLaborMapper.candidates(
      jobId: 'J-12', lines: [
        {'id':'part-1','name':'Oil pan','line_kind':'item','quantity':1},
        {'id':'labor-1','name':'Labor','description':'Replace oil pan','line_kind':'item','quantity':2},
        {'id':'labor-2','name':'Labor','description':'Replace control arms','line_kind':'labor','quantity':5.2},
      ],
    );
    expect(result.map((e) => e.lineId).toList(), ['labor-1', 'labor-2']);
    expect(result.first.jobId, 'J-12');
    expect(result.last.quantity, 5.2);
  });

  test('catalog Service B creates labor candidate without separate labor line', () {
    final result = SavedDocumentLaborMapper.candidates(
      jobId: 'job-1',
      lines: [{'id':'line-2','item_id':'service-b','name':'Service B','line_kind':'item','quantity':1}],
      serviceHoursByCatalogItem: {'service-b':3},
    );
    expect(result.single.defaultPayrollHours, 3);
  });

  test('unsaved lines and malformed quantities never create tasks', () {
    final result = SavedDocumentLaborMapper.candidates(
      jobId:'job-1',
      lines: [
        {'name':'Labor','line_kind':'labor','quantity':2},
        {'id':'line-x','name':'Labor','line_kind':'labor','quantity':'bad'},
      ],
    );
    expect(result, isEmpty);
  });
}
