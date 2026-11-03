import 'dart:async';

import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/local_sync_status_repository.dart';
import 'package:briskers_app/widgets/connection_header_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StatusRepository extends LocalSyncStatusRepository {
  LocalSyncStatusSnapshot value = const LocalSyncStatusSnapshot();
  Future<LocalSyncStatusSnapshot> Function(String)? loader;
  final businesses = <String>[];

  @override
  Future<LocalSyncStatusSnapshot> load(String businessId) async {
    businesses.add(businessId);
    return loader == null ? value : await loader!(businessId);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(_StatusRepository repository, {String business = 'shop'}) =>
      MaterialApp(home: Scaffold(appBar: AppBar(
        toolbarHeight: 78,
        title: ConnectionHeaderToggle(businessId: business, statusRepository: repository),
      )));

  testWidgets('successful refresh events update a retained header and preserve partial warning', (tester) async {
    final repository = _StatusRepository()
      ..value = LocalSyncStatusSnapshot(lastSuccessfulPull: DateTime.now().subtract(const Duration(minutes: 22)));
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Last sync: 22m ago'), findsOneWidget);
    repository.value = LocalSyncStatusSnapshot(
      lastSuccessfulPull: DateTime.now(),
      issues: const ['documents: last attempt failed'],
    );
    JobSyncService.notifyCleanup('other-shop');
    await tester.pumpAndSettle();
    expect(find.text('Last sync: 22m ago'), findsOneWidget);
    JobSyncService.notifyCleanup('shop');
    await tester.pumpAndSettle();
    expect(find.text('Last sync: just now'), findsOneWidget);
    expect(find.text('Sync needs attention'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning from Settings and resuming reread actual downloads', (tester) async {
    final repository = _StatusRepository()
      ..value = LocalSyncStatusSnapshot(lastSuccessfulPull: DateTime.now().subtract(const Duration(minutes: 22)));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(appBar: AppBar(toolbarHeight: 78, title:
        ConnectionHeaderToggle(businessId: 'shop', statusRepository: repository))),
    ));
    await tester.pumpAndSettle();
    unawaited(navigator.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Settings')),
    )));
    await tester.pumpAndSettle();
    repository.value = LocalSyncStatusSnapshot(lastSuccessfulPull: DateTime.now());
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Last sync: just now'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.value = const LocalSyncStatusSnapshot(issues: ['jobs: last attempt failed']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Not yet synced'), findsOneWidget);
    expect(find.text('Sync needs attention'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('navigation rebuild and periodic refresh replace stale timestamps', (tester) async {
    final repository = _StatusRepository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Not yet synced'), findsOneWidget);
    repository.value = LocalSyncStatusSnapshot(lastSuccessfulPull: DateTime.now());
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Last sync: just now'), findsOneWidget);
    repository.value = LocalSyncStatusSnapshot(lastSuccessfulPull: DateTime.now(), pendingUploads: 2);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('2 pending upload(s)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slow response from the previous business cannot overwrite current status', (tester) async {
    final old = Completer<LocalSyncStatusSnapshot>();
    final repository = _StatusRepository()
      ..loader = (business) => business == 'old' ? old.future : Future.value(
        LocalSyncStatusSnapshot(lastSuccessfulPull: DateTime.now()),
      );
    await tester.pumpWidget(app(repository, business: 'old'));
    await tester.pump();
    expect(find.text('Checking sync…'), findsOneWidget);
    await tester.pumpWidget(app(repository, business: 'new'));
    await tester.pumpAndSettle();
    old.complete(const LocalSyncStatusSnapshot(issues: ['Old business failure']));
    await tester.pumpAndSettle();
    expect(find.text('Last sync: just now'), findsOneWidget);
    expect(find.text('Sync needs attention'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('database read failure is unavailable, never success or never-synced', (tester) async {
    final repository = _StatusRepository()
      ..loader = (_) => Future.error(StateError('Synthetic read failure'));
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Sync status unavailable'), findsOneWidget);
    expect(find.text('Not yet synced'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
