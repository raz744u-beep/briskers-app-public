import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Appointment screen exposes four compact filters on one row', () {
    final source = File('lib/screens/appointments_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('BriskersControlledTabs(');
    final end = source.indexOf('const SizedBox(height: 10)', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final filters = source.substring(start, end);
    final shared = File('lib/widgets/briskers_curved_tabs.dart').readAsStringSync();
    expect(shared, contains('TabBar('));
    expect(shared, contains('FittedBox('));
    expect(shared, isNot(contains('isScrollable: true')));
    for (final option in <String>["'today'", "'upcoming'", "'past'", "'all'"]) {
      expect(filters, contains(option));
    }
    expect(filters, isNot(contains("'confirmed_today'")));
    expect(filters, isNot(contains("'All today'")));
    expect(source, contains("String _filter = 'today';"));
    // Switching tabs continues using only the local query and doesn't start
    // a new online sync operation.
    expect(filters, contains('_loadLocal(reportError: true)'));
    expect(filters, isNot(contains('_load();')));
  });

  test('Today includes all appointment statuses; confirmed-only is retained internally', () {
    final repository = File('lib/services/local_appointment_repository.dart')
        .readAsStringSync();
    expect(repository, contains("filter == 'today'"));
    expect(repository, contains("filter == 'confirmed_today'"));
    final screen = File('lib/screens/appointments_screen.dart')
        .readAsStringSync();
    expect(screen, isNot(contains("String _filter = 'confirmed_today';")));
  });
}
