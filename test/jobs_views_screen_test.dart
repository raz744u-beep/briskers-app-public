import 'dart:async';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/job_list_options.dart';
import 'package:briskers_app/screens/jobs_screen.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/job_summary_visibility.dart';
import 'package:briskers_app/widgets/job_compact_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Jobs extends LocalJobRepository {
  final calls =
      <
        ({
          JobListView view,
          JobListSort sort,
          String? user,
          String? search,
          String? status,
          int limit,
        })
      >[];
  Completer<List<Map<String, dynamic>>>? delayed;

  @override
  Future<List<Map<String, dynamic>>> listJobs(
    String businessId, {
    String? status,
    String? search,
    JobListView view = JobListView.recent,
    JobListSort sort = JobListSort.lastAccessed,
    String? userId,
    int limit = 50,
    int offset = 0,
  }) async {
    calls.add((
      view: view,
      sort: sort,
      user: userId,
      search: search,
      status: status,
      limit: limit,
    ));
    if (search == 'old' && delayed != null) return delayed!.future;
    final count = search == 'new' || status == 'paid_still_open' ? 1 : 65;
    return List.generate(
      count,
      (i) => <String, dynamic>{
        'id': 'job-$i',
        'job_number': 'J-$i',
        'title': 'Repair $i',
        'customer_name': 'Customer $i',
        'status': 'open',
        'status_name': 'Open',
        'status_color': '#2563EB',
        'payment_state': 'paid',
      },
    ).skip(offset).take(limit).toList();
  }

  @override
  Future<int> jobCount(
    String businessId, {
    String? status,
    String? search,
    JobListView view = JobListView.recent,
  }) async => search == 'new' || status == 'paid_still_open' ? 1 : 65;

  @override
  Future<List<Map<String, dynamic>>> jobStatuses(String businessId) async => [
    {'code': 'open', 'name': 'Open', 'sort_order': 1},
    {'code': 'completed', 'name': 'Completed', 'sort_order': 2},
  ];

  @override
  Future<Map<String, int>> jobStatusCounts(
    String businessId, {
    JobListView view = JobListView.recent,
  }) async => {'open': 65};
}

class _Visibility extends JobSummaryVisibility {
  _Visibility(String businessId, this.onQuarantine)
    : super(businessId: businessId, onQuarantine: onQuarantine);

  final ValueChanged<Set<String>> onQuarantine;
  final blocked = <String>{};
  bool isDisposed = false;

  void revoke(Set<String> jobIds) {
    if (isDisposed) return;
    blocked.addAll(jobIds);
    beginLoad();
    onQuarantine(jobIds);
  }

  @override
  Future<Set<String>> blockedJobIds() async => blocked;

  @override
  Future<List<Map<String, dynamic>>> filter(
    Iterable<Map<String, dynamic>> rows, {
    String jobIdKey = 'id',
    bool cached = false,
  }) async =>
      JobSummaryVisibility.withoutJobs(rows, blocked, jobIdKey: jobIdKey);

  @override
  void dispose() {
    isDisposed = true;
    super.dispose();
  }
}

class _Documents extends LocalDocumentRepository {
  _Documents({this.rows = const []});
  final List<Map<String, dynamic>> rows;
  @override
  Future<List<Map<String, dynamic>>> search(
    String businessId,
    String query, {
    int limit = 30,
  }) async => rows;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    await BriskersLanguageController.instance.setLanguage('en');
  });
  tearDown(() async {
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
    await BriskersLanguageController.instance.setLanguage('en');
  });

  Widget screen(
    _Jobs repository, {
    String businessId = 'shop',
    void Function(_Visibility)? onVisibility,
    _Documents? documents,
  }) => JobsScreen(
    businessId: businessId,
    roleCode: 'mechanic',
    userId: 'owner',
    repository: repository,
    documentRepository: documents ?? _Documents(),
    visibilityFactory: (business, onQuarantine) {
      final visibility = _Visibility(business, onQuarantine);
      onVisibility?.call(visibility);
      return visibility;
    },
  );

  testWidgets(
    'defaults to Recent/accessed and switches Modified, Active, All offline',
    (tester) async {
      final repository = _Jobs();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: screen(repository))),
      );
      await tester.pumpAndSettle();
      expect(repository.calls.last.view, JobListView.recent);
      expect(repository.calls.last.sort, JobListSort.lastAccessed);
      expect(repository.calls.last.user, 'owner');
      await tester.tap(find.byKey(const ValueKey('job-list-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last modified').last);
      await tester.pumpAndSettle();
      expect(repository.calls.last.sort, JobListSort.lastModified);
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.view, JobListView.active);
      expect(find.text('By status · newest created first'), findsOneWidget);
      await tester.tap(find.text('All').first);
      await tester.pumpAndSettle();
      expect(repository.calls.last.view, JobListView.all);
      expect(find.text('Complete history · last modified'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('load more expands the ordered prefix and keeps selected view', (
    tester,
  ) async {
    final repository = _Jobs();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: screen(repository))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('load-more-jobs')),
      600,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 50,
    );
    await tester.tap(find.byKey(const ValueKey('load-more-jobs')));
    await tester.pumpAndSettle();
    expect(repository.calls.last.limit, 60);
    expect(repository.calls.last.view, JobListView.all);
  });

  testWidgets('view and search restore after leaving and returning to Jobs', (
    tester,
  ) async {
    final repository = _Jobs();
    final visible = ValueNotifier(true);
    final bucket = PageStorageBucket();
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) =>
                  show ? screen(repository) : const Text('Other tab'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active'));
    await tester.enterText(find.byType(TextField).first, 'new');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(repository.calls.last.view, JobListView.active);
    expect(repository.calls.last.search, 'new');
    expect(find.text('new'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paid-still-open rows are not discarded by a second status filter',
    (tester) async {
      final repository = _Jobs();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: screen(repository))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tr('filterJobs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paid, Still Open').last);
      await tester.pumpAndSettle();
      expect(repository.calls.last.status, 'paid_still_open');
      expect(find.byType(JobCompactCard), findsOneWidget);
    },
  );

  testWidgets('older delayed search cannot overwrite newer results', (
    tester,
  ) async {
    final repository = _Jobs()
      ..delayed = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: screen(repository))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'old');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField).first, 'new');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    repository.delayed!.complete([]);
    await tester.pumpAndSettle();
    expect(repository.calls.last.search, 'new');
    expect(find.byType(JobCompactCard), findsOneWidget);
  });

  testWidgets(
    'Spanish controls fit a narrow phone and retain all three views',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await BriskersLanguageController.instance.setLanguage('es');
      final repository = _Jobs();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: screen(repository))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recientes'), findsOneWidget);
      expect(find.text('Activos'), findsOneWidget);
      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Último acceso'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Activos'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.view, JobListView.active);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quarantine prunes retained Jobs and prevents a late load restoring them',
    (tester) async {
      final repository = _Jobs()
        ..delayed = Completer<List<Map<String, dynamic>>>();
      late _Visibility visibility;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: screen(
              repository,
              onVisibility: (value) => visibility = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<JobCompactCard>(find.byType(JobCompactCard))
            .map((card) => card.job['id']),
        contains('job-0'),
      );
      await tester.enterText(find.byType(TextField).first, 'old');
      await tester.pump(const Duration(milliseconds: 350));
      visibility.revoke({'job-0'});
      await tester.pumpAndSettle();
      repository.delayed!.complete([
        {
          'id': 'job-0',
          'job_number': 'J-0',
          'title': 'Revoked late result',
          'status': 'open',
        },
      ]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<JobCompactCard>(find.byType(JobCompactCard))
            .map((card) => card.job['id']),
        isNot(contains('job-0')),
      );
      expect(find.text('Revoked late result'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fresh reads filter durable blocked rows before first paint', (
    tester,
  ) async {
    final repository = _Jobs();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: screen(
            repository,
            onVisibility: (value) => value.blocked.add('job-0'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<JobCompactCard>(find.byType(JobCompactCard))
          .map((card) => card.job['id']),
      isNot(contains('job-0')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'business changes and screen disposal release visibility listeners',
    (tester) async {
      final repository = _Jobs();
      final business = ValueNotifier('shop');
      final observers = <_Visibility>[];
      addTearDown(business.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: business,
              builder: (_, value, _) => screen(
                repository,
                businessId: value,
                onVisibility: observers.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      business.value = 'other-shop';
      await tester.pumpAndSettle();
      expect(observers, hasLength(2));
      expect(observers.first.isDisposed, isTrue);
      expect(observers.last.isDisposed, isFalse);
      observers.first.revoke({'job-0'});
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<JobCompactCard>(find.byType(JobCompactCard))
            .map((card) => card.job['id']),
        contains('job-0'),
      );
      await tester.pumpWidget(const SizedBox());
      expect(observers.last.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quarantine strips linked Job labels while keeping readable invoices',
    (tester) async {
      final repository = _Jobs();
      late _Visibility visibility;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: screen(
              repository,
              onVisibility: (value) => visibility = value,
              documents: _Documents(
                rows: [
                  {
                    'id': 'invoice',
                    'kind': 'invoice',
                    'document_number': '99',
                    'job_id': 'job-0',
                    'job_number': 'J-0',
                    'job_title': 'Private Job',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'new');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Job #J-0'), findsOneWidget);
      visibility.revoke({'job-0'});
      await tester.pumpAndSettle();
      expect(find.text('Job #J-0'), findsNothing);
      expect(find.text('Invoice #99'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
