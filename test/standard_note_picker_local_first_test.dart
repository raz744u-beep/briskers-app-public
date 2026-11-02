import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/screens/jobs/standard_note_picker_sheet.dart';

void main() {
  testWidgets('cached standard notes appear before Auto server refresh finishes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final refresh = Completer<List<Map<String, dynamic>>>();
    var refreshCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StandardNotePickerSheet(
          templates: const [
            {
              'id': 'cached-1',
              'name': 'Cached brake note',
              'body': 'Inspect the brakes',
              'category_key': 'service',
            },
          ],
          canManage: false,
          onRefresh: () {
            refreshCalls++;
            return refresh.future;
          },
          onEdit: (note) async => [],
          onReorder: (ids, categories) async => [],
        ),
      ),
    ));

    await tester.pump();
    expect(refreshCalls, 1);
    expect(find.text('Cached brake note'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    refresh.complete([
      {
        'id': 'server-1',
        'name': 'Server engine note',
        'body': 'Check engine',
        'category_key': 'service',
      },
      {
        'id': 'cached-1',
        'name': 'Cached brake note',
        'body': 'Inspect the brakes',
        'category_key': 'service',
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Server engine note'), findsOneWidget);
    expect(find.text('Cached brake note'), findsOneWidget);
  });

  testWidgets('Force Offline picker has no remote refresh or spinner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StandardNotePickerSheet(
          templates: const [
            {
              'id': 'local-1',
              'name': 'Offline note',
              'body': 'Repair completed',
              'category_key': 'general',
            },
          ],
          canManage: false,
          onEdit: (note) async => [],
          onReorder: (ids, categories) async => [],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Offline note'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
