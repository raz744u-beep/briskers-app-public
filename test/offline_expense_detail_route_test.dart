import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/screens/expenses/expense_detail_screen.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _business = 'synthetic-expense-shop';
const _transaction = 'synthetic-expense-1';

Map<String, dynamic> _summary() => {
  'id': _transaction,
  'job_id': 'synthetic-job-1',
  'direction': 'expense',
  'counterparty': 'Synthetic parts supplier',
  'amount': 12.34,
  'transaction_date': '2026-01-02',
  'remarks': 'Summary-only description',
};

Map<String, dynamic> _fullDetail() => {
  ..._summary(),
  'amount': 45.67,
  'date': '2026-01-03',
  'remarks': 'Saved full detail',
  'editable': true,
  'deletable': true,
  // A synthetic attachment without a storage key never downloads a real file.
  'attachments': [
    {'attachment_id': 'synthetic-receipt-1'},
  ],
};

class _Api extends BriskersApi {
  _Api({this.onlineDetail});
  final Map<String, dynamic>? onlineDetail;
  int detailCalls = 0;
  int permissionCalls = 0;

  @override
  Future<Map<String, dynamic>> transactionDetail(
    String businessId,
    String transactionId,
  ) async {
    detailCalls++;
    expect((businessId, transactionId), (_business, _transaction));
    if (onlineDetail == null) throw StateError('Unexpected network request');
    return Map<String, dynamic>.from(onlineDetail!);
  }

  @override
  Future<List<String>> myPermissions(String businessId) async {
    permissionCalls++;
    expect(businessId, _business);
    if (onlineDetail == null) throw StateError('Unexpected network request');
    return ['records.delete'];
  }
}

class _Cache extends LocalFinancialCache {
  _Cache(BriskersLocalDatabase database, {this.detail})
    : super(database: database);

  Map<String, dynamic>? detail;
  Map<String, dynamic>? persisted;
  int reads = 0;

  @override
  Future<Map<String, dynamic>?> loadTransactionDetail(
    String businessId,
    String transactionId,
  ) async {
    reads++;
    expect((businessId, transactionId), (_business, _transaction));
    return detail;
  }

  @override
  Future<void> saveTransactionDetail(
    String businessId,
    String transactionId,
    Map<String, dynamic> value, {
    int? visibilityGeneration,
  }) async {
    expect((businessId, transactionId), (_business, _transaction));
    persisted = Map<String, dynamic>.from(value);
  }
}

class _Photos extends ExpenseIqLocalPhotoSync {
  _Photos(BriskersLocalDatabase database) : super(database: database);

  @override
  Future<Map<String, dynamic>?> localForExpense(
    String businessId,
    String transactionId,
  ) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase database;

  setUp(() async {
    // The only database available to these doubles is a fresh in-memory DB.
    database = BriskersLocalDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
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
    required _Api api,
    required _Cache cache,
    Map<String, dynamic>? summary,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseDetailScreen(
          businessId: _business,
          transactionId: _transaction,
          canDeleteTransaction: true,
          cachedDetail: summary,
          api: api,
          financialCache: cache,
          localPhotoSync: _Photos(database),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('offline detail opens from disk without a route summary', (
    tester,
  ) async {
    final api = _Api();
    final cache = _Cache(database, detail: _fullDetail());
    await open(tester, api: api, cache: cache);
    expect(find.text('Saved full detail'), findsOneWidget);
    expect(find.text('-\$45.67'), findsOneWidget);
    expect(find.byTooltip('View receipt'), findsOneWidget);
    expect(cache.reads, 1);
    expect(api.detailCalls + api.permissionCalls, 0);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.text('Delete transaction'), findsNothing);
  });

  testWidgets('offline linked summary opens read-only without cached detail', (
    tester,
  ) async {
    final api = _Api();
    final cache = _Cache(database);
    final summary = _summary();
    await open(tester, api: api, cache: cache, summary: summary);
    expect(find.text('Synthetic parts supplier'), findsOneWidget);
    expect(find.text('Summary-only description'), findsOneWidget);
    expect(find.text('-\$12.34'), findsOneWidget);
    expect(find.text('2026-01-02'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('No receipt photos attached.'), findsOneWidget);
    expect(summary.containsKey('editable'), isFalse);
    expect(cache.persisted, isNull);
    expect(api.detailCalls + api.permissionCalls, 0);
  });

  testWidgets('offline saved full detail takes priority over route summary', (
    tester,
  ) async {
    final api = _Api();
    await open(
      tester,
      api: api,
      cache: _Cache(database, detail: _fullDetail()),
      summary: _summary(),
    );
    expect(find.text('Saved full detail'), findsOneWidget);
    expect(find.text('Summary-only description'), findsNothing);
    expect(find.text('2026-01-03'), findsOneWidget);
    expect(find.byTooltip('View receipt'), findsOneWidget);
    expect(api.detailCalls + api.permissionCalls, 0);
  });

  testWidgets('missing offline expense gives a usable explanation', (
    tester,
  ) async {
    final api = _Api();
    await open(tester, api: api, cache: _Cache(database));
    expect(
      find.textContaining('This expense has not been cached on this device.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(api.detailCalls + api.permissionCalls, 0);
  });

  testWidgets('online route refreshes authoritative detail and permissions', (
    tester,
  ) async {
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.online,
    );
    final server = {
      ..._fullDetail(),
      'remarks': 'Authoritative online description',
      'amount': 78.90,
    };
    final api = _Api(onlineDetail: server);
    final cache = _Cache(database, detail: _fullDetail());
    // Online Job routes must omit their list summary. The source-level route
    // guard below protects this contract; this test exercises its actual load.
    await open(tester, api: api, cache: cache);
    expect(api.detailCalls, 1);
    expect(api.permissionCalls, 1);
    expect(cache.reads, 0);
    expect(cache.persisted, server);
    expect(find.text('Authoritative online description'), findsOneWidget);
    expect(find.text('Saved full detail'), findsNothing);
    expect(find.text('-\$78.90'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction'), findsOneWidget);
  });

  test(
    'Job and invoice routes preserve the online/offline summary contract',
    () async {
      final job = await File('lib/screens/jobs/job_detail_screen.dart')
          .readAsString();
      final route = job.substring(
        job.indexOf('Future<void> _openExpense('),
        job.indexOf('Future<void> _editJobExpense('),
      );
      expect(route, contains('cachedDetail: _showingLocal ? cached : null'));
      for (final path in [
        'lib/screens/jobs/job_document_screen.dart',
        'lib/screens/documents_screen.dart',
      ]) {
        final invoice = await File(path).readAsString();
        expect(
          invoice,
          matches(
            r'cachedDetail:\s*offline\s*\?\s*'
            r'Map<String, dynamic>\.from\(expense\)\s*:\s*null',
          ),
          reason: '$path must pass its offline linked expense summary',
        );
      }
    },
  );
}
