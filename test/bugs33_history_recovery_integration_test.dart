import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/supabase_config.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/financial_history_recovery.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _authResponse({bool expired = false}) {
  String segment(Object data) => base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  final claims = {'sub': 'test-owner', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -60 : 3600)};
  final token = "${segment({'alg': 'HS256', 'typ': 'JWT'})}.${segment(claims)}.Zml4dHVyZQ";
  return {'access_token': token, 'refresh_token': 'test-refresh',
    'token_type': 'bearer', 'expires_in': 3600,
    'user': {'id': 'test-owner', 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'}};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read-only recovery merges 26 original IDs alongside three saved payments and survives interruption', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = LocalFinancialCache(database: db);
    Map<String, dynamic> payment(int index) => {
      'business_id': 'shop', 'id': 'payment-$index', 'direction': 'expense',
      'category': 'Payroll', 'transaction_date': '2026-10-23', 'amount': 350,
    };
    final local = [for (var i = 26; i < 29; i++)
      {...payment(i), 'transaction_date': '2026-11-06', 'sync_state': 'pending'}];
    await cache.saveTransactions('shop', local);
    var interrupt = false;
    final offsets = <int>[];
    final transport = MockClient((request) async {
      Object response;
      if (request.url.path == '/auth/v1/token') {
        response = _authResponse();
      } else {
        expect(request.url.path, '/rest/v1/rpc/briskers_list_transactions_recurring_v1');
        final args = jsonDecode(request.body) as Map;
        expect(args['p_business_id'], 'shop');
        expect(args['p_start_date'], isNull);
        final offset = args['p_offset'] as int;
        offsets.add(offset);
        if (interrupt && offset != 0) {
          return http.Response('{"message":"download interrupted"}', 400,
            request: request, headers: {'content-type': 'application/json'});
        }
        response = [for (var i = 0; i < (interrupt ? FinancialHistoryRecovery.pageSize : 26); i++) payment(i)];
      }
      return http.Response(jsonEncode(response), 200, request: request, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture', httpClient: transport);
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(email: 'owner@example.invalid', password: 'fixture');
    final service = FinancialHistoryRecovery(cache: cache, client: client);
    Future<int> recover() => service.download(businessId: 'shop', start: null,
      end: DateTime(2026, 11, 9), onPage: (_) {});
    expect(await recover(), 26);
    expect(await recover(), 26);
    final saved = await cache.loadTransactions('shop');
    expect(saved.map((r) => r['id']).toSet().length, 29);
    expect(saved.length, 29);
    for (final row in local) {
      expect(saved.singleWhere((r) => r['id'] == row['id']), row);
    }
    interrupt = true;
    await expectLater(recover(), throwsA(isA<PostgrestException>()));
    expect(await cache.loadTransactions('shop'), saved);
    expect(offsets, [0, 0, 0, FinancialHistoryRecovery.pageSize]);
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM sync_outbox').getSingle()).data['n'], 0);
  });

  test('Force Offline renews an expired session and retains 1,000+ rows after restart', () async {
    SharedPreferences.setMockInitialValues({});
    final mode = BriskersConnectionModeController.instance;
    await mode.setMode(BriskersConnectionMode.auto);
    addTearDown(() => mode.setMode(BriskersConnectionMode.auto));
    final dir = await Directory.systemTemp.createTemp('financial-history-');
    final file = File('${dir.path}/ledger.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    final posted = [
      for (var i = 0; i < 1240; i++) {
        'id': 'expense-$i',
        'business_id': 'shop',
        'transaction_date': i < 1000 ? '2026-08-15' : '2025-02-12',
        'direction': 'expense',
        'amount': i < 1000 ? 10 : 12.5,
      },
    ];
    final invoices = [
      for (var i = 0; i < 1100; i++) {
        'id': 'invoice-$i',
        'kind': 'invoice',
        'status': 'closed',
        'document_date': i < 1000 ? '2026-09-01' : '2025-02-12',
        'total_amount': 100,
      },
    ];
    final requested = <String>[];
    final grantTypes = <String?>[];
    final client = SupabaseClient(supabaseUrl, 'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: BriskersSupabaseHttpClient(MockClient((request) async {
        requested.add(request.url.path);
        final args = jsonDecode(request.body) as Map;
        final grantType = request.url.queryParameters['grant_type'];
        if (request.url.path == '/auth/v1/token') grantTypes.add(grantType);
        final Object result = switch (request.url.path) {
          '/auth/v1/token' => _authResponse(expired: grantType == 'password'),
          '/rest/v1/rpc/briskers_list_documents_v4' => invoices,
          '/rest/v1/rpc/briskers_list_transactions_recurring_v1' =>
            posted.skip(args['p_offset'] as int).take(args['p_limit'] as int).toList(),
          _ => fail('Unexpected network request ${request.url.path}'),
        };
        return http.Response(jsonEncode(result), 200, request: request,
          headers: {'content-type': 'application/json'});
      })),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(email: 'owner@example.invalid', password: 'fixture');
    expect(client.auth.currentSession?.isExpired, isTrue);
    await mode.setMode(BriskersConnectionMode.offline);
    final cache = LocalFinancialCache(database: db);
    await cache.saveTransactions('shop', posted.take(1000).toList());
    final recovery = FinancialHistoryRecovery(client: client, cache: cache,
      documents: LocalDocumentRepository(database: db));
    expect(await recovery.download(businessId: 'shop', start: null,
      end: DateTime(2026, 11, 17), onPage: (_) {}), 1240);
    expect(await recovery.downloadInvoices('shop'), 1100);
    expect(mode.forceOffline, isTrue);
    expect(grantTypes, ['password', 'refresh_token']);
    expect(requested[1], '/auth/v1/token');
    expect(requested.where((path) => path.contains('list_transactions')), hasLength(7));
    final requestsAfterDownload = requested.length;
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    final saved = LocalFinancialCache(database: db);
    final coverage = await saved.postedHistoryCoverage('shop');
    expect(coverage, (start: null, end: DateTime(2026, 11, 17)));
    final priorYear = await saved.loadTransactions('shop', startDate: DateTime(2025),
      endDate: DateTime(2025, 12, 31));
    final totals = await ExpensesPeriodTotals.calculate(readPage: (offset, limit) async =>
      priorYear.skip(offset).take(limit).toList());
    expect(totals.transactions, 240);
    expect(totals.expenses, 3000);
    expect(await saved.loadTransactions('shop'), hasLength(1240));
    final documents = LocalDocumentRepository(database: db);
    final savedInvoices = await documents.listByKind('shop', kind: 'invoice');
    expect(savedInvoices, hasLength(1100));
    expect(savedInvoices.where((row) => row['document_date'] == '2025-02-12')
      .fold<num>(0, (sum, row) => sum + (row['total_amount'] as num)), 10000);
    expect(await documents.invoiceHistoryCheckedAt('shop'), isNotNull);
    expect(requested, hasLength(requestsAfterDownload));
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });

}
