import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Standard Note actions honor system navigation and keyboard insets', () {
    final source =
        File('lib/screens/jobs/standard_note_editor_sheet.dart').readAsStringSync();
    expect(source, contains('MediaQuery.viewInsetsOf(context).bottom'));
    expect(source, contains('maintainBottomViewPadding: true'));
    expect(source, contains('minimum: const EdgeInsets.only(bottom: 8)'));
    final footer = source.indexOf('standard-note-submit');
    expect(source.lastIndexOf('SafeArea(', footer), greaterThan(0));
  });

  test('Jobs quick edits publish local data before a network flush', () {
    final source = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final mechanic = source.substring(
      source.indexOf('Future<void> _quickEditMechanic('),
      source.indexOf('Future<void> _quickEditPlannedTime('),
    );
    expect(
      mechanic.indexOf('cachedEmployees(widget.businessId)'),
      lessThan(mechanic.indexOf('refreshEmployees(widget.businessId)')),
    );
    final hours = source.substring(
      source.indexOf('Future<void> _quickEditPlannedTime('),
      source.indexOf('Future<void> _changeStatus('),
    );
    for (final code in [mechanic, hours]) {
      expect(code, contains('await _load(refreshRemote: false)'));
      expect(code, contains('_scheduleQuickEditSync();'));
      expect(code, isNot(contains('await _offlineJobAdmin.flush(')));
    }
    expect(source, contains('bool _quickEditSyncRunning = false'));
    expect(source, contains('bool _quickEditSyncRequested = false'));
  });

  test('Primary creation actions use pill FABs and avoid duplicate search +', () {
    const paths = <String>[
      'lib/screens/jobs_screen.dart',
      'lib/screens/customers/customers_screen.dart',
      'lib/screens/appointments_screen.dart',
      'lib/screens/documents_screen.dart',
      'lib/screens/expenses_screen.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('FloatingActionButton.extended('), reason: path);
      expect(source, contains("label: const Text('New'"), reason: path);
      expect(source, contains('MediaQuery.viewInsetsOf(context).bottom == 0'),
          reason: path);
    }
  });
}
