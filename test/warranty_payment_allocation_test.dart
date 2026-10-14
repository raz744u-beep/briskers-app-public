import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/core/warranty_payment_amounts.dart';
import 'package:briskers_app/screens/jobs/invoice_warranty_panel.dart';
import 'package:briskers_app/services/document_pdf_service.dart';
import 'package:briskers_app/services/warranty_receipt_reporting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _plan = <String, dynamic>{
  'extended_warranty': true,
  'warranty_company_name': 'Synthetic Warranty Co',
  'authorization_number': 'QA-ALLOCATION',
  'approved_amount': 103,
  'terminal_amount': 100,
  'net_applied': 100,
  'processor_fee': 3,
  'customer_responsibility': 900,
  'surcharge_rate': 0.03,
};

Map<String, dynamic> _receipt(String state, {bool local = false}) => {
  'id': 'synthetic-warranty-receipt',
  'amount': 103,
  'state': state,
  'payment_method_name': 'Credit card',
  if (local) 'pending_sync': true,
};

Widget _panel({required List<Map<String, dynamic>> payments,
    Map<String, dynamic> detail = _plan, num total = 1000,
    Future<void> Function(Map<String, dynamic>)? save}) {
  final receipt = WarrantyPaymentAmounts.receipt(detail, payments);
  final pending = receipt?['state'] == 'pending';
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: InvoiceWarrantyPanel(
      businessId: 'synthetic-shop', documentId: 'synthetic-invoice',
      expectedVersion: 1, invoiceTotal: total, detail: detail,
      payments: payments, paymentProcessed: receipt != null && !pending,
      paymentPendingLabel: pending ? 'Pending sync' : null,
      readOnly: save == null, onChanged: () async {},
      onLocalWarrantyChanged: save ?? (_) async {},
    ),
  )));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
  });

  test('customer fee allocation stays separate from actual gross invoice credit', () {
    final allocation = WarrantyPaymentAllocation.fromWarranty(
      invoiceTotal: 1000, warranty: _plan);
    expect(allocation.customerBase, 897);
    expect(allocation.processorFee, 3);
    expect(allocation.customerTotal, 900);
    expect(allocation.requiresReview, isFalse);
    for (final state in ['pending', 'posted', 'finalized']) {
      final payment = _receipt(state, local: state == 'pending');
      final invoice = <String, dynamic>{
        'total_amount': 1000,
        'paid_amount': state == 'pending' ? 0 : 103,
        'pending_payment': state == 'pending' ? 103 : 0,
        'payments': [payment],
      };
      expect(WarrantyPaymentAmounts.receipt(_plan, [payment]), payment);
      expect(DocumentPdfService.invoicePaymentAmounts(invoice)['remaining'], 897);
      expect(WarrantyPaymentAllocation.fromWarranty(
        invoiceTotal: invoice['total_amount'], warranty: _plan).customerTotal, 900);
      final report = WarrantyReceiptReporting.project(
        {...payment, 'direction': 'income', 'signed_amount': 103}, invoice, _plan);
      expect(report['amount'], 103);
      expect(report['signed_amount'], 103);
      if (state == 'pending') {
        expect(report['reporting_status'], 'unverified');
      } else {
        expect(report['reporting_amount'], 100);
        expect(report['reporting_processor_fee'], 3);
        expect(WarrantyReceiptReporting.project(report, invoice, _plan), report);
      }
      expect(invoice['total_amount'], 1000);
      expect(invoice['payments'], [payment]);
    }
  });

  test('zero-rate check allocation and retained receipt have no fee', () {
    final warranty = {..._plan, 'terminal_amount': 103, 'net_applied': 103,
      'processor_fee': 0, 'surcharge_rate': 0, 'customer_responsibility': 897};
    final payment = {..._receipt('posted'), 'payment_method_name': 'Check'};
    final allocation = WarrantyPaymentAllocation.fromWarranty(
      invoiceTotal: 1000, warranty: warranty);
    expect(allocation.customerBase, 897);
    expect(allocation.customerTotal, 897);
    expect(allocation.processorFee, 0);
    expect(allocation.requiresReview, isFalse);
    final report = WarrantyReceiptReporting.project(
      {...payment, 'direction': 'income'}, {'payments': [payment]}, warranty);
    expect(report['reporting_amount'], 103);
    expect(report['reporting_processor_fee'], 0);
  });

  test('missing saved allocation uses approval and fee, never an actual receipt', () {
    final warranty = {..._plan}..remove('customer_responsibility');
    final allocation = WarrantyPaymentAllocation.fromWarranty(
      invoiceTotal: 1000, warranty: warranty);
    expect(allocation.customerTotal, 900);
    expect(allocation.customerBase, 897);
  });

  test('check with stale nonzero card fee requires review and keeps raw income', () {
    final warranty = {..._plan, 'surcharge_rate': 0};
    final payment = {..._receipt('posted'), 'payment_method_name': 'Check'};
    final allocation = WarrantyPaymentAllocation.fromWarranty(
      invoiceTotal: 1000, warranty: warranty);
    expect(allocation.requiresReview, isTrue);
    final report = WarrantyReceiptReporting.project(
      {...payment, 'direction': 'income'}, {'payments': [payment]}, warranty);
    expect(report['reporting_status'], 'unverified');
    expect(report.containsKey('reporting_processor_fee'), isFalse);
    expect(WarrantyReceiptReporting.amount(report), 103);
  });

  test('inconsistent or malformed saved splits require review without rewriting them', () {
    for (final saved in [0, 1, 2.99]) {
      final warranty = {..._plan, 'customer_responsibility': saved};
      final allocation = WarrantyPaymentAllocation.fromWarranty(
        invoiceTotal: 1000, warranty: warranty);
      expect(allocation.customerTotal, saved);
      expect(allocation.requiresReview, isTrue);
      expect(warranty['customer_responsibility'], saved);
    }
    for (final approval in [null, -1, double.nan, double.infinity, 1001]) {
      expect(WarrantyPaymentAllocation.fromWarranty(invoiceTotal: 1000,
        warranty: {..._plan, 'approved_amount': approval}).requiresReview, isTrue);
    }
    for (final fee in [null, -1, double.nan, 104]) {
      expect(WarrantyPaymentAllocation.fromWarranty(invoiceTotal: 1000,
        warranty: {..._plan, 'processor_fee': fee}).requiresReview, isTrue);
    }
    expect(WarrantyPaymentAllocation.fromWarranty(invoiceTotal: 1000,
      warranty: {..._plan, 'customer_responsibility': -1}).requiresReview, isTrue);
  });

  test('changing approval does not permit recapture or attribute ambiguous fees', () {
    final payment = _receipt('posted');
    final edited = {..._plan, 'approved_amount': 104};
    expect(WarrantyPaymentAmounts.hasCandidateReceipt(edited, [payment]), isTrue);
    expect(WarrantyPaymentAmounts.receipt(edited, [payment]), isNull);
    final changedToCheck = {..._plan, 'surcharge_rate': 0, 'processor_fee': 0};
    expect(WarrantyPaymentAmounts.hasCandidateReceipt(changedToCheck, [payment]), isTrue);
    expect(WarrantyPaymentAmounts.receipt(changedToCheck, [payment]), isNull);
    expect(WarrantyPaymentAmounts.hasCandidateReceipt(_plan,
      [{...payment, 'payment_method_name': 'Check'}]), isTrue);
    for (final receipts in [
      [{...payment, 'amount': 50}],
      [payment, {...payment, 'id': 'another-card'}],
    ]) {
      expect(WarrantyPaymentAmounts.hasCandidateReceipt(_plan, receipts), isTrue);
      final result = WarrantyReceiptReporting.project(
        {...payment, 'direction': 'income'}, {'payments': receipts}, _plan);
      expect(result['reporting_status'], 'unverified');
      expect(result.containsKey('reporting_processor_fee'), isFalse);
    }
  });

  test('cash-only and reversed receipts do not block a new warranty shortcut', () {
    final payment = _receipt('posted');
    expect(WarrantyPaymentAmounts.hasCandidateReceipt(_plan,
      [{...payment, 'payment_method_name': 'Cash'}]), isFalse);
    for (final state in ['reversed', 'voided', 'cancelled', 'deleted']) {
      for (final method in ['Credit card', 'Check']) {
        final inactive = {...payment, 'state': state, 'payment_method_name': method};
        expect(WarrantyPaymentAmounts.hasCandidateReceipt(_plan, [inactive]), isFalse);
        expect(WarrantyPaymentAmounts.receipt(_plan, [inactive]), isNull);
      }
    }
  });

  testWidgets('saved customer allocation remains 900 before and after receipt lifecycle', (tester) async {
    await tester.pumpWidget(_panel(payments: []));
    expect(find.text('Approved \$103.00 • Customer allocation \$900.00'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Customer responsibility allocation'), findsOneWidget);
    expect(find.text('\$900.00'), findsOneWidget);
    for (final payment in [
      _receipt('pending', local: true),
      _receipt('pending'),
      _receipt('posted'),
      _receipt('finalized'),
    ]) {
      await tester.pumpWidget(_panel(payments: [payment]));
      await tester.pumpAndSettle();
      expect(find.text('Approved \$103.00 • Customer allocation \$900.00'), findsOneWidget);
      expect(find.text('\$900.00'), findsOneWidget);
      expect(find.text('Actual gross received'), findsOneWidget);
      expect(find.text('\$103.00'), findsNWidgets(3));
      expect(find.text('\$100.00'), findsOneWidget);
      expect(find.textContaining('see invoice balance for amount due'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('fully paid historical-shaped receipt never creates an amount due', (tester) async {
    final warranty = {..._plan, 'approved_amount': 684.97,
      'terminal_amount': 684.97, 'net_applied': 665.02, 'processor_fee': 19.95,
      'customer_responsibility': 3307.95};
    final payments = <Map<String, dynamic>>[
      {..._receipt('finalized'), 'amount': 684.97},
      {'id': 'synthetic-cash', 'state': 'finalized', 'amount': 3288,
        'payment_method_name': 'Cash'},
    ];
    final invoice = {'total_amount': 3972.97, 'paid_amount': 3972.97,
      'pending_payment': 0, 'payments': payments};
    expect(DocumentPdfService.invoicePaymentAmounts(invoice)['remaining'], 0);
    await tester.pumpWidget(_panel(payments: payments, detail: warranty, total: 3972.97));
    expect(find.textContaining('Customer allocation \$3,307.95'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Customer responsibility allocation'), findsOneWidget);
    expect(find.textContaining('see invoice balance for amount due'), findsOneWidget);
    expect(find.textContaining('Balance Due'), findsNothing);
    expect(find.text('\$19.95'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(invoice['paid_amount'], 3972.97);
  });

  testWidgets('inconsistent saved allocation is marked for review on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_panel(payments: [],
      detail: {..._plan, 'customer_responsibility': 0}));
    expect(find.textContaining('Customer allocation Review required'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Review required'), findsNWidgets(2));
    expect(find.text('The saved allocation needs review before use.'), findsOneWidget);
    expect(find.text('\$0.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final check in [false, true]) {
    testWidgets('local ${check ? "check" : "card"} edit saves cent-exact allocation without recapturing receipts', (tester) async {
      Map<String, dynamic>? saved;
      final payment = _receipt('posted');
      await tester.pumpWidget(_panel(payments: [payment],
        save: (values) async { saved = values; }));
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final approval = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.decoration?.labelText == 'Approved warranty amount');
      final theme = Theme.of(tester.element(approval));
      expect(theme.colorScheme.primary, BriskersColors.invoices);
      expect(theme.colorScheme.surface, Colors.white);
      await tester.enterText(approval, '103.01');
      if (check) {
        await tester.tap(find.byType(DropdownButtonFormField<num>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('0% — Check').last);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Save warranty information'));
      await tester.tap(find.text('Save warranty information'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['surcharge_rate'], check ? 0 : 0.03);
      expect(saved!['terminal_amount'], check ? 103.01 : 100.01);
      expect(saved!['net_applied'], check ? 103.01 : 100.01);
      expect(saved!['processor_fee'], check ? 0 : 3);
      expect(WarrantyPaymentAmounts.cents(saved!['customer_responsibility']),
        check ? 89699 : 89999);
      expect(payment['amount'], 103);
      expect(payment['state'], 'posted');
      expect(saved!.containsKey('payments'), isFalse);
      expect(WarrantyPaymentAmounts.hasCandidateReceipt(saved!, [payment]), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
