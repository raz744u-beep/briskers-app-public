import 'package:briskers_app/services/catalog_replacement_type_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy labor can select named service with authoritative labor type', () {
    expect(
      catalogReplacementTypeError(
        existingLineIsLabor: true,
        itemType: ' LABOR ',
        itemName: 'Engine replacement',
      ),
      isNull,
    );
    expect(catalogItemIsLabor('Labour'), isTrue);
  });

  test('part named Labor cannot replace paid or assigned labor', () {
    expect(
      catalogReplacementTypeError(
        existingLineIsLabor: true,
        itemType: 'part',
        itemName: 'Labor',
      ),
      isNotNull,
    );
  });

  test('a non-labor item cannot silently become an unassigned labor task', () {
    expect(
      catalogReplacementTypeError(
        existingLineIsLabor: false,
        itemType: 'labor',
        itemName: 'Labor',
      ),
      isNotNull,
    );
  });

  test('unknown types are not interchangeable, even when names look right', () {
    for (final type in [null, '', 'obsolete', 'unknown']) {
      expect(
        catalogReplacementTypeError(
          existingLineIsLabor: true,
          itemType: type,
          itemName: 'Labor',
        ),
        isNotNull,
      );
    }
  });

  test('non-labor catalog called Labor cannot receive legacy labor identity', () {
    expect(
      catalogReplacementTypeError(
        existingLineIsLabor: false,
        itemType: 'part',
        itemName: 'Labour',
      ),
      isNotNull,
    );
  });

  test('same-kind part replacement keeps non-labor identity', () {
    for (final type in ['part', 'non_inventory', 'service', 'fee', 'other']) {
      expect(
        catalogReplacementTypeError(
          existingLineIsLabor: false,
          itemType: type,
          itemName: 'Oil filter',
        ),
        isNull,
      );
    }
  });
}
