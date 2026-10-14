import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/screens/documents_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> invoice({num paid = 0, num pending = 0}) => {
    'kind': 'invoice',
    'status': 'draft',
    'total_amount': 100,
    'paid_amount': paid,
    'pending_payment': pending,
  };
  String stage(Map<String, dynamic> row) =>
      documentListStage(row, estimate: false);

  test(
    'known partial balance overrides stale paid and pending-close hints',
    () {
      for (final hint in ['paid', 'pending_close']) {
        final row = invoice(paid: 20, pending: 30)
          ..['display_status_code'] = hint
          ..['display_status'] = 'Paid';
        expect(stage(row), 'Open');
        expect(DocumentPresentation(row).balanceDueCents, 5000);
      }
    },
  );

  test('reconciliation-required receipts are never classified fully paid', () {
    final row = invoice(paid: 100)
      ..['display_status_code'] = 'paid'
      ..['_payment_reconciliation_required'] = true;
    expect(stage(row), 'Open');
    row.remove('paid_amount');
    row.remove('pending_payment');
    expect(stage(row), 'Open');
  });

  test('historical closed status and close evidence remain Closed', () {
    expect(stage(invoice()..['status'] = 'closed'), 'Closed');
    expect(stage(invoice()..['closed_at'] = '2026-10-14T12:00:00Z'), 'Closed');
    // The synced index carries derived close evidence even without full detail.
    expect(stage(invoice()..['display_status_code'] = 'closed'), 'Closed');
  });

  test('void remains a separate filter and never falls into Open or paid', () {
    final row = invoice(paid: 100)..['status'] = 'void';
    expect(stage(row), 'Void');
    expect(invoiceListStatusFilters, contains('Void'));
    expect(invoiceListStatusFilters, isNot(contains('Paid')));
  });

  test(
    'full finalized, pending, and mixed coverage share one stable stage',
    () {
      for (final row in [
        invoice(paid: 100),
        invoice(pending: 100),
        invoice(paid: 25, pending: 75),
      ]) {
        expect(stage(row), 'Paid · Pending Close');
      }
      expect(stage(invoice()), 'Open');
    },
  );

  test(
    'filter counts and cards use the same mutually exclusive stable stages',
    () {
      final rows = [
        invoice(),
        invoice(paid: 100),
        invoice()..['status'] = 'closed',
        invoice()..['status'] = 'void',
        invoice(paid: 10)..['display_status_code'] = 'paid',
      ];
      final counts = {
        for (final filter in invoiceListStatusFilters)
          filter: rows.where((row) => stage(row) == filter).length,
      };
      expect(counts, {
        'Open': 2,
        'Paid · Pending Close': 1,
        'Closed': 1,
        'Void': 1,
      });
      expect(counts.values.reduce((a, b) => a + b), rows.length);
    },
  );

  test('local index placeholders stay unknown while real API partial amounts stay known', () {
    final local = invoice()
      ..['_local_snapshot'] = true
      ..['display_status_code'] = 'paid';
    final prepared = documentListIndexPresentation(local);
    expect(prepared.containsKey('paid_amount'), false);
    expect(prepared.containsKey('pending_payment'), false);
    expect(DocumentPresentation(prepared).balanceDueCents, isNull);
    expect(stage(prepared), 'Paid · Pending Close');
    expect(
      local['paid_amount'],
      0,
    ); // Presentation never mutates repository data.
    final online = invoice(paid: 20)..['display_status_code'] = 'paid';
    expect(stage(documentListIndexPresentation(online)), 'Open');
  });

  test('estimate workflow labels are retained independently', () {
    for (final status in estimateListStatusFilters) {
      expect(
        documentListStage({
          'kind': 'estimate',
          'display_status': status,
          'display_status_code': 'paid',
          'paid_amount': 100,
        }, estimate: true),
        status,
      );
    }
    expect(
      documentListStage({'display_status': 'Converted'}, estimate: true),
      'Converted',
    );
  });

  test('filter values remain stable across Spanish language changes', () async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('es');
    expect(stage(invoice(paid: 100)), 'Paid · Pending Close');
    expect(
      DocumentPresentation(invoice(paid: 100)).statusLabel,
      'Pagada · Pendiente de cierre',
    );
    await BriskersLanguageController.instance.setLanguage('en');
  });
}
