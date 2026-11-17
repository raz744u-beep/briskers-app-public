import 'dart:async';

import 'package:http/http.dart' as http;

import 'connection_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://coensavcnuwuqaeszohb.supabase.co';
const supabasePublishableKey = 'sb_publishable_tY4v9OoY0nkbeFl-5cnGbA_FoWzD9aP';

SupabaseClient get supabase => Supabase.instance.client;

SupabaseClient get networkSupabase {
  BriskersConnectionModeController.instance.ensureNetworkAllowed();
  return Supabase.instance.client;
}

final _explicitRead = Object();

/// This scope permits only the read the Owner explicitly initiated.
Future<T> explicitSupabaseRead<T>(String rpc, Future<T> Function() read) {
  if (!const {
    'briskers_recurring_recovery_v1',
    'briskers_read_recurring_expense_occurrence',
    'briskers_owner_recovery_lookup_v1',
    'briskers_list_transactions_recurring_v1',
    'briskers_list_documents_v4',
  }.contains(rpc)) {
    throw ArgumentError('This read requires an online connection.');
  }
  return runZoned(read, zoneValues: {_explicitRead: '/rest/v1/rpc/$rpc'});
}

class BriskersSupabaseHttpClient extends http.BaseClient {
  BriskersSupabaseHttpClient(this._client, {this.readPersistedMode = false});
  final http.Client _client;
  final bool readPersistedMode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final mode = BriskersConnectionModeController.instance;
    if (readPersistedMode
        ? await mode.offlineForBackgroundRequest()
        : mode.forceOffline) {
      if (readPersistedMode ||
          request.method != 'POST' ||
          request.url.host != Uri.parse(supabaseUrl).host ||
          request.url.path != Zone.current[_explicitRead]) {
        throw http.ClientException(
          'Supabase access is paused in Force Offline.',
        );
      }
    }
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
