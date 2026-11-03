import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/standard_note_rules.dart';

void main() {
  test(
    'standard note categories preserve historical notes and General footer',
    () {
      expect(standardNoteCategory({'name': 'Service A'}), 'service');
      expect(standardNoteCategory({'name': 'Standard Warranty'}), 'warranty');
      expect(standardNoteCategory({'name': 'Thank You'}), 'general');
      expect(
        standardNoteCategory({
          'name': 'Future Followup',
          'category_key': 'inspection',
        }),
        'inspection',
      );
      final ordered = orderStandardNotes([
        {'name': 'Thank You', 'category_key': 'general', 'sort_order': 0},
        {'name': 'Service A', 'category_key': 'service', 'sort_order': 10},
      ]);
      expect(ordered.map((note) => note['name']), ['Service A', 'Thank You']);
      expect(standardNoteCategoryKeys.last, 'general');
    },
  );

  test('General sorts last for old caches, server ranks and mixed casing', () {
    final notes = [
      {'id': 'g', 'name': ' GENERAL ', 'sort_order': -100},
      {'id': 'b', 'name': 'Second', 'sort_order': 20},
      {'id': 'a', 'name': 'First', 'sort_order': 10},
    ];
    expect(orderStandardNotes(notes).map((note) => note['id']), [
      'a',
      'b',
      'g',
    ]);
    expect(notes.first['id'], 'g');
  });
  test('equal ranks preserve stable input order', () {
    expect(
      orderStandardNotes([
        {'name': 'Z'},
        {'name': 'A'},
        {'name': 'General'},
      ]).map((note) => note['name']),
      ['Z', 'A', 'General'],
    );
  });
  test('missing and malformed colors use a readable palette default', () {
    for (final color in [null, '', '#123', '#GGGGGG', 'red', 1234]) {
      expect(standardNoteColorHex(color), standardNoteDefaultColor);
    }
    expect(standardNoteColorHex(' #c62828 '), '#C62828');
  });
  test(
    'empty category order is complete, deduplicated and General remains last',
    () {
      expect(
        orderStandardNoteCategories([
          'general',
          'advisory',
          'advisory',
          'invalid',
        ]),
        ['advisory', 'service', 'warranty', 'inspection', 'general'],
      );
      expect(
        standardNoteCategory({
          'name': 'General Note',
          'category_key': 'service',
        }),
        'general',
      );
      expect(
        standardNoteCategory({'name': 'Thank You', 'category_key': 'service'}),
        'general',
      );
    },
  );
}
