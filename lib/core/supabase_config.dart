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

/// The SDK refreshes its auth session on its own schedule, outside calls
/// through networkSupabase. Preserve the saved session when the shop is offline.
class BriskersSupabaseHttpClient extends http.BaseClient {
  BriskersSupabaseHttpClient(this._client);
  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (BriskersConnectionModeController.instance.forceOffline &&
        request.url.path == '/auth/v1/token' &&
        request.url.queryParameters['grant_type'] == 'refresh_token') {
      throw http.ClientException('Session refresh is paused in Force Offline.');
    }
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
