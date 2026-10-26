import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs uses only global mode/sync status, not a repeated page banner', () {
    final jobs = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final header =
        File('lib/widgets/connection_header_toggle.dart').readAsStringSync();

    // Both Force Offline and Auto network fallback keep their cached cards.
    expect(jobs, contains('await readSavedJobs(online: !refreshRemote && _onlineReady)'));
    expect(jobs, contains('_rows = visibleRows;'));
    expect(jobs, contains('if (_showingLocal || (_rows?.isNotEmpty ?? false))'));
    expect(jobs, contains('if (_error != null)'));

    // The Jobs list must not repeatedly consume vertical space for a warning
    // already represented in the global header.
    expect(jobs, isNot(contains('Offline · showing saved jobs')));
    expect(jobs, isNot(contains('Showing saved jobs · refresh needs attention')));
    expect(jobs, isNot(contains("if (_showingLocal &&\n")));

    // Real sync problems and pending uploads remain visible and navigable.
    expect(header, contains("key: const ValueKey('sync-header-attention')"));
    expect(header, contains('Sync needs attention'));
    expect(header, contains('Last sync:'));
    expect(header, contains("child: Text('Force Offline')"));
  });
}
