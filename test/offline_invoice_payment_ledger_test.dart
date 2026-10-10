import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

void main() {
  group('Offline received-cash accounting', () {
    test('stores exact cents rather than floating payment totals', () {
      expect(OfflineInvoicePaymentLedger.cents(500), 50000);
      expect(OfflineInvoicePaymentLedger.cents(0.10 + 0.20), 30);
    });

    test('shows zero balance immediately for a locally received cash payment', () {
      expect(
        OfflineInvoicePaymentLedger.remainingCents(
          total: 500,
          finalized: 0,
          pendingOnServer: 0,
          queuedLocally: const [500],
        ),
        0,
      );
    });

    test('does not double count server payment and separate local payments', () {
      expect(
        OfflineInvoicePaymentLedger.remainingCents(
          total: 500,
          finalized: 100,
          pendingOnServer: 150,
          queuedLocally: const [100],
        ),
        15000,
      );
    });

    test('rejects zero, negative, and nonfinite amounts', () {
      expect(() => OfflineInvoicePaymentLedger.cents(0), throwsArgumentError);
      expect(() => OfflineInvoicePaymentLedger.cents(-5), throwsArgumentError);
      expect(
        () => OfflineInvoicePaymentLedger.cents(double.infinity),
        throwsArgumentError,
      );
    });
  });
}
