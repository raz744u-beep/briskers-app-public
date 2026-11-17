import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mode = BriskersConnectionModeController.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await mode.initialize();
    addTearDown(() => mode.setMode(BriskersConnectionMode.auto));
  });

  test(
    'Force Offline rejects background requests and permits only the explicit read',
    () async {
      final requests = <Uri>[];
      final client = BriskersSupabaseHttpClient(
        MockClient((request) async {
          requests.add(request.url);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final queued = Uri.parse(
        '$supabaseUrl/rest/v1/rpc/briskers_recurring_recovery_v1',
      );
      final refresh = Uri.parse(
        '$supabaseUrl/auth/v1/token?grant_type=refresh_token',
      );
      final write = Uri.parse(
        '$supabaseUrl/rest/v1/rpc/briskers_create_manual_transaction',
      );
      await mode.setMode(BriskersConnectionMode.offline);
      for (final target in [queued, refresh, write]) {
        await expectLater(
          client.post(target),
          throwsA(isA<http.ClientException>()),
        );
      }
      await explicitSupabaseRead('briskers_recurring_recovery_v1', () async {
        await expectLater(
          client.post(refresh),
          throwsA(isA<http.ClientException>()),
        );
        await expectLater(
          client.post(write),
          throwsA(isA<http.ClientException>()),
        );
        await client.post(queued);
      });
      expect(requests, [queued]);
      await mode.setMode(BriskersConnectionMode.auto);
      await client.post(write);
      expect(requests, [queued, write]);
    },
  );

  test('only the explicit history read can refresh the session offline', () async {
    final sent = <Uri>[];
    final client = BriskersSupabaseHttpClient(MockClient((request) async {
      sent.add(request.url);
      return http.Response('{}', 200);
    }));
    addTearDown(client.close);
    await mode.setMode(BriskersConnectionMode.offline);

    const rpc = 'briskers_list_transactions_recurring_v1';
    final history = Uri.parse('$supabaseUrl/rest/v1/rpc/$rpc');
    final refresh = Uri.parse('$supabaseUrl/auth/v1/token?grant_type=refresh_token');
    final blocked = [
      Uri.parse('$supabaseUrl/auth/v1/token?grant_type=password'),
      Uri.parse('$supabaseUrl/auth/v1/token?grant_type=refresh_token&grant_type=password'),
      Uri.parse('$supabaseUrl/rest/v1/rpc/briskers_create_manual_transaction'),
      refresh.replace(scheme: 'http'),
    ];
    await explicitSupabaseRead(rpc, () async {
      for (final target in blocked) {
        await expectLater(client.post(target), throwsA(isA<http.ClientException>()));
      }
      await client.post(refresh);
      await client.post(history);
    });
    await expectLater(client.post(refresh), throwsA(isA<http.ClientException>()));
    expect(sent, [refresh, history]);
    expect(mode.forceOffline, isTrue);
  });

  test(
    'worker checks persisted changes even with a stale isolate mode',
    () async {
      var sent = 0;
      final client = BriskersSupabaseHttpClient(
        MockClient((request) async {
          sent++;
          return http.Response('{}', 200);
        }),
        readPersistedMode: true,
      );
      addTearDown(client.close);
      final target = Uri.parse(
        '$supabaseUrl/storage/v1/object/authenticated/example',
      );
      await client.get(target);
      SharedPreferences.setMockInitialValues({
        'briskers_connection_mode': 'offline',
      });
      expect(mode.forceOffline, isFalse);
      await expectLater(
        client.get(target),
        throwsA(isA<http.ClientException>()),
      );
      expect(sent, 1);
    },
  );
}
