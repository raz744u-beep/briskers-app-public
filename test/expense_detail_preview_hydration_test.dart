import 'dart:async';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/navigation_content_timing.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/screens/expenses/expense_detail_screen.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/warranty_receipt_reporting.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _business = 'synthetic-preview-business';
const _transaction = 'synthetic-preview-expense';

Map<String, dynamic> _summary({String id = _transaction}) => {
  'id': id,
  'direction': 'expense',
  'counterparty': 'Synthetic preview supplier',
  'amount': 12.34,
  'transaction_date': '2026-10-20',
  'remarks': 'Immediate list summary',
  // Even incorrect/stale permission hints in a list row must not enable actions.
  'editable': true,
  'deletable': true,
};

Map<String, dynamic> _detail(String label, {String id = _transaction}) => {
  ..._summary(id: id),
  'amount': 45.67,
  'remarks': label,
  'job_id': 'synthetic-linked-job',
  // No storage key means these fixtures cannot download a real receipt.
  'attachments': [
    {'attachment_id': 'synthetic-receipt-$id'},
  ],
};

class _Read<T> {
  _Read(this.businessId, this.transactionId);
  final String businessId;
  final String transactionId;
  final result = Completer<T>();
}

class _Api extends BriskersApi {
  final details = <_Read<Map<String, dynamic>>>[];
  final permissions = <_Read<List<String>>>[];
  final deletes = <(String, String, String)>[];
  late final deleteGate = Completer<void>();

  @override
  Future<Map<String, dynamic>> transactionDetail(
    String businessId,
    String transactionId,
  ) {
    final read = _Read<Map<String, dynamic>>(businessId, transactionId);
    details.add(read);
    return read.result.future;
  }

  @override
  Future<List<String>> myPermissions(String businessId) {
    final read = _Read<List<String>>(businessId, '');
    permissions.add(read);
    return read.result.future;
  }

  @override
  Future<void> deleteExpensePhoto(
    String businessId,
    String transactionId,
    String attachmentId, {
    required String bucket,
    required String key,
  }) {
    deletes.add((businessId, transactionId, attachmentId));
    return deleteGate.future;
  }
}

class _Cache extends LocalFinancialCache {
  _Cache(BriskersLocalDatabase database) : super(database: database);
  final reads = <_Read<Map<String, dynamic>?>>[];
  final writes = <(String, String, Map<String, dynamic>)>[];
  late final writeGate = Completer<void>();

  @override
  Future<Map<String, dynamic>?> loadTransactionDetail(
    String businessId,
    String transactionId,
  ) {
    final read = _Read<Map<String, dynamic>?>(businessId, transactionId);
    reads.add(read);
    return read.result.future;
  }

  @override
  Future<void> saveTransactionDetail(
    String businessId,
    String transactionId,
    Map<String, dynamic> detail,
  ) {
    writes.add((businessId, transactionId, Map.of(detail)));
    return writeGate.future;
  }
}

class _Photos extends ExpenseIqLocalPhotoSync {
  _Photos(BriskersLocalDatabase database) : super(database: database);
  final reads = <_Read<Map<String, dynamic>?>>[];

  @override
  Future<Map<String, dynamic>?> localForExpense(
    String businessId,
    String transactionId,
  ) {
    final read = _Read<Map<String, dynamic>?>(businessId, transactionId);
    reads.add(read);
    return read.result.future;
  }
}

class _Reporting extends WarrantyReceiptReporting {
  final rows = <Map<String, dynamic>>[];
  final results = <Completer<List<Map<String, dynamic>>>>[];

  @override
  Future<List<Map<String, dynamic>>> enrich(
    String businessId,
    List<Map<String, dynamic>> transactions, {
    bool refresh = true,
  }) {
    expect(refresh, isFalse);
    rows.add(Map.of(transactions.single));
    final result = Completer<List<Map<String, dynamic>>>();
    results.add(result);
    return result.future;
  }

  void complete(int index, [Map<String, dynamic> changes = const {}]) {
    results[index].complete([
      {...rows[index], 'reporting_status': 'verified', ...changes},
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase database;
  late _Api api;
  late _Cache cache;
  late _Photos photos;
  late _Reporting reporting;

  setUp(() async {
    database = BriskersLocalDatabase(NativeDatabase.memory());
    api = _Api();
    cache = _Cache(database);
    photos = _Photos(database);
    reporting = _Reporting();
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });

  tearDown(() async {
    await database.close();
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });

  Future<void> open(
    WidgetTester tester, {
    String businessId = _business,
    String transactionId = _transaction,
    Map<String, dynamic>? summary,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseDetailScreen(
          key: const ValueKey('reused-detail-state'),
          businessId: businessId,
          transactionId: transactionId,
          cachedDetail: summary ?? _summary(id: transactionId),
          canDeleteTransaction: true,
          api: api,
          financialCache: cache,
          localPhotoSync: photos,
          receiptReporting: reporting,
        ),
      ),
    );
  }

  Future<void> flushFrame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  void expectReadOnly() {
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Make recurring'), findsNothing);
    expect(find.byTooltip('Replace receipt photo'), findsNothing);
    expect(find.byTooltip('Delete receipt photo'), findsNothing);
  }

  testWidgets('first frame shows summary while disk and network stay blocked', (
    tester,
  ) async {
    final samples = <(String, String)>[];
    NavigationContentTiming.onSample = (module, source, elapsed) {
      samples.add((module, source));
    };
    addTearDown(() => NavigationContentTiming.onSample = null);
    NavigationContentTiming.start('expense_detail');
    final summary = _summary();
    await open(tester, summary: summary);
    expect(samples, [('expense_detail', 'preview')]);
    expect(find.text('Immediate list summary'), findsOneWidget);
    expect(find.text('-\$12.34'), findsOneWidget);
    expect(find.text('2026-10-20'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectReadOnly();
    expect(api.details, hasLength(1));
    expect(api.permissions, isEmpty);
    expect(cache.reads, hasLength(1));
    expect(photos.reads, hasLength(1));
    expect(reporting.results, isEmpty);
    expect(summary['editable'], isTrue);
    expect(summary.containsKey('date'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disk full detail keeps receipts read-only after remote failure', (
    tester,
  ) async {
    await open(tester);
    cache.reads.single.result.complete(_detail('Cached full detail'));
    await flushFrame(tester);
    expect(find.text('Cached full detail'), findsOneWidget);
    expect(find.byTooltip('View receipt'), findsOneWidget);
    expectReadOnly();
    // Reporting and remote detail remain blocked; neither delays local detail.
    expect(reporting.results, hasLength(1));
    api.details.single.result.completeError(
      StateError('Synthetic remote failure'),
    );
    await flushFrame(tester);
    expect(find.text('Cached full detail'), findsOneWidget);
    expect(find.textContaining('Synthetic remote failure'), findsOneWidget);
    expectReadOnly();
    expect(cache.writes, isEmpty);
    expect(api.permissions, isEmpty);
  });

  testWidgets(
    'late disk fallback preserves a remote failure and stays read-only',
    (tester) async {
      await open(tester);
      api.details.single.result.completeError(
        StateError('Synthetic remote failure'),
      );
      await flushFrame(tester);
      expect(find.text('Immediate list summary'), findsOneWidget);
      cache.reads.single.result.complete(_detail('Late cached full detail'));
      await flushFrame(tester);
      expect(find.text('Late cached full detail'), findsOneWidget);
      expect(find.textContaining('Synthetic remote failure'), findsOneWidget);
      expect(find.byTooltip('View receipt'), findsOneWidget);
      expectReadOnly();
      expect(api.permissions, isEmpty);
    },
  );

  testWidgets('both failed reads preserve the immediate read-only summary', (
    tester,
  ) async {
    await open(tester);
    cache.reads.single.result.completeError(
      StateError('Synthetic disk failure'),
    );
    api.details.single.result.completeError(
      StateError('Synthetic network failure'),
    );
    await flushFrame(tester);
    expect(find.text('Immediate list summary'), findsOneWidget);
    expect(find.text('-\$12.34'), findsOneWidget);
    expect(find.textContaining('Synthetic network failure'), findsOneWidget);
    expectReadOnly();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'server detail wins late disk and does not await background work',
    (tester) async {
      await open(tester);
      final server = _detail('Authoritative server detail');
      api.details.single.result.complete(server);
      await flushFrame(tester);
      expect(find.text('Authoritative server detail'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      expect(find.byTooltip('View receipt'), findsOneWidget);
      expect(find.byTooltip('Delete receipt photo'), findsNothing);
      expect(reporting.results, hasLength(1));
      expect(api.permissions, hasLength(1));
      expect(cache.writes.single.$3, server);
      // All three background tasks are blocked here.
      cache.reads.single.result.complete(_detail('Stale disk detail'));
      await flushFrame(tester);
      expect(find.text('Stale disk detail'), findsNothing);
      expect(find.text('Authoritative server detail'), findsOneWidget);
      api.permissions.single.result.complete([]);
      await flushFrame(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Edit transaction'), findsOneWidget);
      expect(find.text('Delete transaction'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed permission read leaves deletion disabled', (
    tester,
  ) async {
    await open(tester);
    api.details.single.result.complete(_detail('Server full detail'));
    await flushFrame(tester);
    api.permissions.single.result.completeError(
      StateError('Synthetic permission failure'),
    );
    await flushFrame(tester);
    expect(find.byTooltip('Delete receipt photo'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.text('Delete transaction'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late local reporting cannot overwrite server values or rights', (
    tester,
  ) async {
    await open(tester);
    cache.reads.single.result.complete(_detail('Cached detail'));
    await flushFrame(tester);
    api.details.single.result.complete({
      ..._detail('Read-only authoritative detail'),
      'amount': 88.99,
      'editable': false,
      'deletable': false,
      'attachments': <dynamic>[],
    });
    await flushFrame(tester);
    reporting.complete(0, {'editable': true, 'deletable': true});
    api.permissions.single.result.complete(['records.delete']);
    await flushFrame(tester);
    expect(find.text('Read-only authoritative detail'), findsOneWidget);
    expect(find.text('-\$88.99'), findsOneWidget);
    expect(find.byTooltip('View receipt'), findsNothing);
    expectReadOnly();
    // Even the current reporter may update projection fields only.
    reporting.complete(1, {
      'editable': true,
      'deletable': true,
      'remarks': 'Unexpected reporting replacement',
      'attachments': _detail('')['attachments'],
    });
    await flushFrame(tester);
    expect(find.text('Read-only authoritative detail'), findsOneWidget);
    expect(find.text('Unexpected reporting replacement'), findsNothing);
    expectReadOnly();
  });

  testWidgets(
    'old record permission and photo cannot enable or pollute new record',
    (tester) async {
      await open(tester);
      api.details[0].result.complete(_detail('First record'));
      await flushFrame(tester);
      await open(
        tester,
        businessId: 'synthetic-other-business',
        transactionId: 'other',
      );
      expect(find.text('First record'), findsNothing);
      expectReadOnly();
      api.details[1].result.complete(_detail('Second record', id: 'other'));
      await flushFrame(tester);
      expect(api.permissions[1].businessId, 'synthetic-other-business');
      api.permissions[1].result.complete([]);
      api.permissions[0].result.complete(['records.delete']);
      cache.reads[0].result.complete(_detail('Stale first disk detail'));
      photos.reads[0].result.complete({
        'filename': 'Stale first photo',
        'source_uri': '',
      });
      reporting.complete(0);
      await flushFrame(tester);
      expect(find.text('Second record'), findsOneWidget);
      expect(find.text('Stale first disk detail'), findsNothing);
      expect(find.text('Stale first photo'), findsNothing);
      expect(find.byTooltip('Delete receipt photo'), findsNothing);
      expect(cache.writes.map((entry) => (entry.$1, entry.$2)), [
        (_business, _transaction),
        ('synthetic-other-business', 'other'),
      ]);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Delete transaction'), findsNothing);
    },
  );

  testWidgets('older A response is ignored after an A to B to A navigation', (
    tester,
  ) async {
    await open(tester);
    await open(tester, transactionId: 'other');
    await open(tester);
    api.details[2].result.complete(_detail('Newest A detail'));
    await flushFrame(tester);
    api.details[0].result.complete(_detail('Stale original A detail'));
    api.details[1].result.completeError(StateError('Stale B failure'));
    cache.reads[0].result.complete(_detail('Stale original A cache'));
    await flushFrame(tester);
    expect(find.text('Newest A detail'), findsOneWidget);
    expect(find.text('Stale original A detail'), findsNothing);
    expect(find.text('Stale original A cache'), findsNothing);
    expect(find.textContaining('Stale B failure'), findsNothing);
    expect(api.permissions, hasLength(1));
    expect(cache.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a receipt action invalidates older reporting and refreshes detail',
    (tester) async {
      await open(tester);
      api.details.single.result.complete(_detail('Before deletion'));
      await flushFrame(tester);
      api.permissions.single.result.complete(['records.delete']);
      await flushFrame(tester);
      expect(find.byTooltip('Delete receipt photo'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete receipt photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await flushFrame(tester);
      expect(api.deletes, [
        (_business, _transaction, 'synthetic-receipt-$_transaction'),
      ]);
      reporting.complete(0, {'remarks': 'Stale after action'});
      await flushFrame(tester);
      expect(find.text('Stale after action'), findsNothing);
      api.deleteGate.complete();
      await flushFrame(tester);
      api.details[1].result.complete({
        ..._detail('After deletion'),
        'attachments': <dynamic>[],
      });
      await flushFrame(tester);
      expect(find.text('After deletion'), findsOneWidget);
      expect(find.byTooltip('View receipt'), findsNothing);
      expect(find.text('No receipt photos attached.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an old receipt confirmation cannot delete from the next record',
    (tester) async {
      await open(tester);
      api.details[0].result.complete(_detail('First record'));
      await flushFrame(tester);
      api.permissions[0].result.complete(['records.delete']);
      await flushFrame(tester);
      await tester.tap(find.byTooltip('Delete receipt photo'));
      await tester.pumpAndSettle();
      expect(find.text('Delete receipt photo?'), findsOneWidget);
      await open(tester, transactionId: 'other');
      api.details[1].result.complete(_detail('Second record', id: 'other'));
      await flushFrame(tester);
      api.permissions[1].result.complete(['records.delete']);
      await flushFrame(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.deletes, isEmpty);
      expect(find.text('Second record'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Force Offline paints summary before disk without API reads', (
    tester,
  ) async {
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    await open(tester);
    expect(find.text('Immediate list summary'), findsOneWidget);
    expectReadOnly();
    expect(api.details, isEmpty);
    cache.reads.single.result.complete(_detail('Offline full detail'));
    await flushFrame(tester);
    expect(find.text('Offline full detail'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.byTooltip('View receipt'), findsOneWidget);
    expect(find.byTooltip('Delete receipt photo'), findsNothing);
    expect(reporting.results, hasLength(1));
    expect(api.details, isEmpty);
    expect(api.permissions, isEmpty);
    expect(cache.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local photo bytes are read once per URI and reset for a new record',
    (tester) async {
      const channel = MethodChannel('com.ivehement.plugins/saf/v2');
      final bytes = Completer<Uint8List>();
      var reads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) {
        expect(call.method, 'readFileBytes');
        reads++;
        return bytes.future;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await open(tester);
      photos.reads[0].result.complete({
        'filename': 'Synthetic local photo',
        'source_uri': 'content://synthetic/photo',
      });
      await flushFrame(tester);
      expect(reads, 1);
      api.details[0].result.complete(_detail('Server detail'));
      await flushFrame(tester);
      api.permissions[0].result.complete(['records.delete']);
      reporting.complete(0);
      await flushFrame(tester);
      expect(reads, 1);
      await open(tester, transactionId: 'other');
      photos.reads[1].result.complete({
        'filename': 'Second local photo',
        'source_uri': 'content://synthetic/photo',
      });
      await flushFrame(tester);
      expect(reads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposed screen ignores all pending responses', (tester) async {
    await open(tester);
    api.details.single.result.complete(_detail('Visible full detail'));
    await flushFrame(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    api.permissions.single.result.complete(['records.delete']);
    cache.reads.single.result.complete(_detail('Disposed local detail'));
    photos.reads.single.result.complete({'filename': 'Disposed photo'});
    reporting.complete(0);
    cache.writeGate.complete();
    await flushFrame(tester);
    expect(tester.takeException(), isNull);
  });
}
