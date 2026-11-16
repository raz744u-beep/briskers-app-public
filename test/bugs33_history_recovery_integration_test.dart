import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/financial_history_recovery.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        String segment(Object data) => base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
        final claims = {'sub': 'test-owner', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600};
        final token = "${segment({'alg': 'HS256', 'typ': 'JWT'})}.${segment(claims)}.Zml4dHVyZQ";
        response = {'access_token': token, 'refresh_token': 'test-refresh',
          'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': 'test-owner', 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'}};
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
}
