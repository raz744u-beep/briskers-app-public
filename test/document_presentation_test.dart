import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/document_presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
  });

  Map<String, dynamic> invoice({
    num total = 875.25,
    num paid = 0,
    num pending = 0,
  }) => {
    'kind': 'invoice',
    'status': 'draft',
    'document_number': 'TEST-INV-OPEN',
    'total_amount': total,
    'paid_amount': paid,
    'pending_payment': pending,
  };

  test('Synthetic open invoice displays Open without mutating imported draft', () {
    final data = invoice();
    final view = DocumentPresentation(data);
    expect(view.statusLabel, 'Open');
    expect(view.balanceDueCents, 87525);
    expect(data['status'], 'draft');
  });

  test('Synthetic pending invoice fully pending is covered but still awaiting close', () {
    final data = invoice(total: 200, pending: 200)
      ..['document_number'] = 'TEST-INV-PENDING';
    final view = DocumentPresentation(data);
    expect(view.statusLabel, 'Pending Close');
    expect(view.balanceDueCents, 0);
    expect(view.finalizedCents, 0);
    expect(view.pendingCents, 20000);
    expect(view.isClosed, false);
  });

  test(
    'only full coverage changes Open; finalized and pending combine exactly',
    () {
      expect(
        DocumentPresentation(invoice(paid: 100, pending: 50)).statusLabel,
        'Open',
      );
      expect(
        DocumentPresentation(invoice(paid: 100, pending: 50)).balanceDueCents,
        72525,
      );
      expect(
        DocumentPresentation(invoice(paid: 875.25)).statusLabel,
        'Pending Close',
      );
      expect(
        DocumentPresentation(invoice(paid: 400, pending: 475.25))
            .balanceDueCents,
        0,
      );
      expect(
        DocumentPresentation(invoice(total: 0.3, pending: 0.1 + 0.2))
            .fullyCovered,
        true,
      );
      expect(DocumentPresentation(invoice(total: 0)).statusLabel, 'Open');
    },
  );

  test('actual close wins even on a legacy draft; raw paid is not payment evidence', () {
    final data = invoice()..['closed_at'] = '2026-10-14T13:00:00Z';
    expect(DocumentPresentation(data).statusLabel, 'Closed');
    expect(
      DocumentPresentation({
        'kind': 'invoice',
        'status': 'paid',
        'total_amount': 20,
      }).statusLabel,
      'Open',
    );
    expect(
      DocumentPresentation({
        'kind': 'invoice',
        'status': 'draft',
        'display_status_code': 'paid',
      }).statusLabel,
      'Pending Close',
    );
  });

  test(
    'unknown, stale, and ambiguous payment information never invents zero due',
    () {
      final missing = DocumentPresentation({
        'kind': 'invoice',
        'total_amount': 100,
        'paid_amount': 0,
      });
      expect(missing.balanceDueCents, isNull);
      final ambiguous = DocumentPresentation(
        invoice(pending: 875.25)..['_payment_reconciliation_required'] = true,
      );
      expect(ambiguous.statusLabel, 'Open');
      expect(ambiguous.balanceDueCents, isNull);
      expect(
        DocumentPresentation(invoice(paid: double.nan)).balanceDueCents,
        isNull,
      );
      expect(
        DocumentPresentation(invoice(paid: double.infinity)).balanceDueCents,
        isNull,
      );
    },
  );

  test(
    'estimates keep their own statuses and never contribute invoice balances',
    () {
      for (final status in [
        'draft',
        'issued',
        'accepted',
        'declined',
        'expired',
      ]) {
        final view = DocumentPresentation(
          invoice(paid: 875.25)
            ..['kind'] = 'estimate'
            ..['status'] = status,
        );
        expect(view.statusLabel.toLowerCase(), status);
        expect(view.balanceDueCents, isNull);
      }
      expect(
        DocumentPresentation({'kind': 'estimate', 'converted': true})
            .statusLabel,
        'Converted',
      );
      expect(
        DocumentPresentation(invoice()..['status'] = 'void').statusLabel,
        'Void',
      );
    },
  );

  test(
    'three invoice stages and estimate statuses are translated in Spanish',
    () async {
      await BriskersLanguageController.instance.setLanguage('es');
      expect(DocumentPresentation(invoice()).statusLabel, 'Abierta');
      expect(
        DocumentPresentation(invoice(pending: 875.25)).statusLabel,
        'Pendiente de cierre',
      );
      expect(
        DocumentPresentation(invoice()..['closed_at'] = 123).statusLabel,
        'Cerrada',
      );
      expect(
        DocumentPresentation({'kind': 'estimate', 'status': 'draft'})
            .statusLabel,
        'Borrador',
      );
    },
  );
}
