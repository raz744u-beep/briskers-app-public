const shopSupabaseUrl = 'https://coensavcnuwuqaeszohb.supabase.co';
const shopPublishableKey = 'sb_publishable_tY4v9OoY0nkbeFl-5cnGbA_FoWzD9aP';

const shopReceiptGateway =
    'https://briskers-receipt-ai.raz744u.workers.dev/extract';
const _environment = String.fromEnvironment(
  'BRISKERS_ENVIRONMENT',
  defaultValue: 'production',
);
const isStaging = _environment == 'staging';
const supabaseUrl = isStaging
    ? String.fromEnvironment('BRISKERS_STAGING_SUPABASE_URL')
    : shopSupabaseUrl;
const supabasePublishableKey = isStaging
    ? String.fromEnvironment('BRISKERS_STAGING_SUPABASE_PUBLISHABLE_KEY')
    : shopPublishableKey;
const receiptGatewayUrl = isStaging
    ? String.fromEnvironment('BRISKERS_STAGING_RECEIPT_GATEWAY_URL')
    : String.fromEnvironment(
        'BRISKERS_RECEIPT_AI_GATEWAY_URL',
        defaultValue: shopReceiptGateway,
      );

/// Validate before foreground or background clients can open a connection.
void validateBriskersEnvironment() {
  if (_environment == 'production') return;
  if (!isStaging) throw StateError('Unknown Briskers environment.');
  final backend = Uri.tryParse(supabaseUrl);
  final gateway = Uri.tryParse(receiptGatewayUrl);
  final shopHosts = {
    Uri.parse(shopSupabaseUrl).host,
    Uri.parse(shopReceiptGateway).host,
  };
  for (final endpoint in [backend, gateway]) {
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        shopHosts.contains(
          endpoint.host.toLowerCase().replaceFirst(RegExp(r'\.$'), ''),
        )) {
      throw StateError('An isolated HTTPS staging endpoint is required.');
    }
  }
  if (supabasePublishableKey.isEmpty ||
      supabasePublishableKey == shopPublishableKey) {
    throw StateError('A separate staging publishable key is required.');
  }
}
