// Run using dart tools/test_staging_environment.dart.
import 'dart:io';

import '../lib/core/briskers_environment.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    var accepted = true;
    try {
      validateBriskersEnvironment();
    } on StateError {
      accepted = false;
    }
    if (accepted != (args.single == 'allow')) {
      throw StateError('Unexpected staging configuration validation result');
    }
    return;
  }

  const staging = {
    'BRISKERS_ENVIRONMENT': 'staging',
    'BRISKERS_STAGING_SUPABASE_URL': 'https://database.example',
    'BRISKERS_STAGING_RECEIPT_GATEWAY_URL': 'https://receipts.example/extract',
    'BRISKERS_STAGING_SUPABASE_PUBLISHABLE_KEY': 'synthetic-test-key',
  };
  final cases = <(Map<String, String>, String)>[
    ({}, 'allow'),
    (staging, 'allow'),
    ({'BRISKERS_ENVIRONMENT': 'invalid'}, 'deny'),
    ({'BRISKERS_ENVIRONMENT': 'staging'}, 'deny'),
    (
      {...staging, 'BRISKERS_STAGING_SUPABASE_URL': '$shopSupabaseUrl.'},
      'deny',
    ),
    (
      {...staging, 'BRISKERS_STAGING_RECEIPT_GATEWAY_URL': shopReceiptGateway},
      'deny',
    ),
    (
      {
        ...staging,
        'BRISKERS_STAGING_SUPABASE_PUBLISHABLE_KEY': shopPublishableKey,
      },
      'deny',
    ),
  ];
  for (final (settings, expected) in cases) {
    final result = await Process.run(Platform.resolvedExecutable, [
      for (final entry in settings.entries) '-D${entry.key}=${entry.value}',
      Platform.script.toFilePath(),
      expected,
    ]);
    if (result.exitCode != 0)
      throw StateError('Environment check failed: ${result.stderr}');
  }
  stdout.writeln('${cases.length} environment guard checks passed');
}
