import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Close Invoices does not promise cross-device sync while replay is paused',
      () async {
    final screen = await File('lib/screens/documents_screen.dart').readAsString();
    final closure =
        await File('lib/services/local_invoice_closure.dart').readAsString();
    final finalization =
        await File('lib/services/offline_invoice_finalization.dart')
            .readAsString();

    // The notice is displayed in the actual batch-close bottom sheet.
    expect(screen, contains('Future<void> _showCloseInvoices() async {'));
    expect(screen, contains(
      'Closing records Closed and finalizes any pending received payments '
      'into Income on this device.',
    ));
    expect(screen, contains(
      'Sync of these changes to other devices is not yet confirmed.',
    ));
    expect(screen, contains('Verify each device before relying on its totals.'));
    expect(screen, isNot(contains('synchronization runs in the background.')));
    expect(screen, isNot(contains('Payment records stay unchanged;')));

    // Until a reviewed, idempotent replay contract replaces these gates,
    // local success must never be presented as verified multi-device success.
    expect(closure, contains('bool enableLegacyReplay = false'));
    expect(closure, contains('if (!_enableLegacyReplay) return;'));
    expect(finalization, contains('static const remoteReplayEnabled = false;'));
  });
}
