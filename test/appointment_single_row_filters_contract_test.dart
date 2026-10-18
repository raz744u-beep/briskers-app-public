import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Schedule shows exactly four equal-width chips on a single row', () {
    final source = File('lib/screens/appointments_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('// Four equal-width filters always remain on one row.');
    final end = source.indexOf('const SizedBox(height: 10)', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final filters = source.substring(start, end);

    expect(filters, contains('Row('));
    expect(filters, isNot(contains('Wrap(')));
    expect(filters, contains('Expanded('));
    expect(filters, contains('FittedBox('));
    expect(filters, contains('BoxFit.scaleDown'));
    expect(filters, contains("ChoiceChip("));
    for (final filter in ["'today'", "'upcoming'", "'past'", "'all'"]) {
      expect(filters, contains(filter));
    }
    expect(filters, isNot(contains("'confirmed_today'")));
    expect(filters, isNot(contains("'All today'")));
    expect(source, contains("String _filter = 'today';"));
    expect(source, contains("_filter = 'today';"));
  });

  test('Today returns all statuses; previous confirmed-only query stays available internally',
      () {
    final repo = File('lib/services/local_appointment_repository.dart')
        .readAsStringSync();
    expect(repo, contains("if (filter == 'today' || filter == 'confirmed_today')"));
    expect(repo, contains('if (filter == \'confirmed_today\') where.add("a.status = \'confirmed\'");'));
    final screen = File('lib/screens/appointments_screen.dart')
        .readAsStringSync();
    expect(screen, contains("String _filter = 'today';"));
    expect(screen, isNot(contains("String _filter = 'confirmed_today';")));
  });
}
