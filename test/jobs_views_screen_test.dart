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
    JobListView view = JobListView.all,
    JobListSort sort = JobListSort.lastModified,
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
    JobListView view = JobListView.all,
  }) async => search == 'new' || status == 'paid_still_open' ? 1 : 65;

  @override
  Future<List<Map<String, dynamic>>> jobStatuses(String businessId) async => [
    {'code': 'open', 'name': 'Open', 'sort_order': 1},
    {'code': 'completed', 'name': 'Completed', 'sort_order': 2},
  ];

  @override
  Future<Map<String, int>> jobStatusCounts(
    String businessId, {
    JobListView view = JobListView.all,
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
    String roleCode = 'mechanic',
    void Function(_Visibility)? onVisibility,
    _Documents? documents,
  }) => JobsScreen(
    businessId: businessId,
    roleCode: roleCode,
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
    'Jobs uses latest activity with only the existing status filter',
    (tester) async {
      final repository = _Jobs();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: screen(repository))),
      );
      await tester.pumpAndSettle();
      expect(repository.calls.last.view, JobListView.all);
      expect(repository.calls.last.sort, JobListSort.lastModified);
      expect(repository.calls.last.user, 'owner');
      expect(find.byType(SegmentedButton<JobListView>), findsNothing);
      expect(find.byKey(const ValueKey('job-list-sort')), findsNothing);
      expect(find.text('Recent'), findsNothing);
      expect(find.text('Active'), findsNothing);
      expect(find.text('All statuses'), findsOneWidget);
      await tester.tap(find.byTooltip(tr('filterJobs')));
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsOneWidget);
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.status, 'completed');
      expect(repository.calls.last.view, JobListView.all);
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

  testWidgets('old view preferences cannot restore removed Jobs selectors', (
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
    bucket.writeState(
      tester.element(find.byType(JobsScreen)),
      const JobListPreferences(
        view: JobListView.active,
        sort: JobListSort.lastAccessed,
        allSort: JobListSort.jobDate,
        status: 'completed',
        search: 'new',
        visibleLimit: 60,
      ),
      identifier: 'jobs-view:shop:owner',
    );
    visible.value = false;
    await tester.pumpAndSettle();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(repository.calls.last.view, JobListView.all);
    expect(repository.calls.last.sort, JobListSort.lastModified);
    expect(repository.calls.last.status, 'completed');
    expect(repository.calls.last.search, 'new');
    expect(repository.calls.last.limit, 60);
    expect(find.byType(SegmentedButton<JobListView>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status and search restore after leaving and returning to Jobs', (
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
    await tester.tap(find.byTooltip(tr('filterJobs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'new');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(repository.calls.last.view, JobListView.all);
    expect(repository.calls.last.status, 'completed');
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
    'Spanish status and search fit a narrow phone without removed selectors',
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
      expect(find.text('Recientes'), findsNothing);
      expect(find.text('Activos'), findsNothing);
      expect(find.text('Todos los estados'), findsOneWidget);
      expect(find.text('Último acceso'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip(tr('filterJobs')));
      await tester.pumpAndSettle();
      expect(repository.calls.last.view, JobListView.all);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Jobs long-press exposes Add Payment for managers and dismisses safely',
    (tester) async {
      final repository = _Jobs();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: screen(repository, roleCode: 'owner')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(JobCompactCard).first);
      await tester.pumpAndSettle();
      // A repeated long-press callback cannot stack another action sheet.
      tester
          .widget<JobCompactCard>(find.byType(JobCompactCard).first)
          .onLongPress!();
      await tester.pumpAndSettle();
      expect(find.text('Add Payment'), findsOneWidget);
      expect(find.text('Add Invoice'), findsOneWidget);
      Navigator.of(tester.element(find.text('Add Payment'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Add Payment'), findsNothing);
      expect(find.byType(JobsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Jobs long-press does not expose payment to mechanics', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen(_Jobs()))));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(JobCompactCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Add Payment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  for (final language in ['en', 'es']) {
    testWidgets(
      'paid filter wraps at 200% text size in a narrow $language popup',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await BriskersLanguageController.instance.setLanguage(language);
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: screen(_Jobs()))),
        );
        await tester.pumpAndSettle();
        final button = tester.widget<PopupMenuButton<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is PopupMenuButton<String> &&
                widget.tooltip == tr('filterJobs'),
          ),
        );
        final entry = button
            .itemBuilder(tester.element(find.byType(JobsScreen)))
            .singleWhere(
              (entry) =>
                  entry is PopupMenuItem<String> &&
                  entry.value == 'paid_still_open',
            );
        // Exercise the real menu entry within a 256px-wide popup,
        // independently of unrelated cards and header accessibility layouts.
        await tester.pumpWidget(
          MaterialApp(
            // The popup lives in Navigator's overlay, so scaling must wrap
            // the Navigator rather than just the launch button's subtree.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: PopupMenuButton<String>(
                  key: const ValueKey('enlarged-paid-filter'),
                  constraints: const BoxConstraints.tightFor(width: 256),
                  itemBuilder: (_) => [entry],
                  icon: const Icon(Icons.filter_list),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('enlarged-paid-filter')));
        await tester.pumpAndSettle();
        final label = find.text(
          language == 'en' ? 'Paid, Still Open' : 'Pagado, aún abierto',
        );
        expect(label, findsOneWidget);
        expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), 20);
        expect(tester.getSize(label).height, greaterThan(24));
        expect(tester.getSize(label).width, lessThanOrEqualTo(222));
        expect(tester.takeException(), isNull);
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(label, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
