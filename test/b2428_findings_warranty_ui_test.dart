import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/screens/jobs/invoice_warranty_panel.dart';
import 'package:briskers_app/services/customer_finding_overview_service.dart';
import 'package:briskers_app/widgets/customer_findings_overview_row.dart';

class _SlowFindingCounts extends CustomerFindingOverviewService {
  final remote = Completer<CustomerFindingCounts>();
  var localReads = 0;
  var remoteReads = 0;

  @override
  Future<CustomerFindingCounts> load({
    required String businessId,
    required String customerId,
    required List<dynamic> vehicles,
    bool localOnly = false,
  }) {
    if (localOnly) {
      localReads++;
      return Future.value(const CustomerFindingCounts(
          open: 2, inJob: 1, resolved: 0));
    }
    remoteReads++;
    return remote.future;
  }
}

void main() {
  testWidgets('Customer Findings counts paint locally before a stuck server',
      (tester) async {
    final service = _SlowFindingCounts();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomerFindingsOverviewRow(
          businessId: 'test-business',
          customerId: 'test-customer',
          vehicles: const <Map<String, dynamic>>[{'id': 'car-one'}],
          service: service,
          onOpen: () async {},
        ),
      ),
    ));
    await tester.pump();
    expect(service.localReads, 1);
    expect(service.remoteReads, 1);
    expect(find.text('Open 2 • In Job 1 • Resolved 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-findings-total')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'A pending network call must not show a spinner.');

    service.remote.complete(
        const CustomerFindingCounts(open: 2, inJob: 1, resolved: 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('Open 2 • In Job 1 • Resolved 1'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('regular invoice warranty controls stay compact', (tester) async {
    Widget panel(Map<String, dynamic> detail) => MaterialApp(
      home: Scaffold(
        body: InvoiceWarrantyPanel(
          businessId: 'fixture',
          documentId: 'fixture-invoice',
          expectedVersion: 1,
          invoiceTotal: 500,
          detail: detail,
          paymentProcessed: false,
          readOnly: true,
          onLocalWarrantyChanged: (_) async {},
          onChanged: () async {},
        ),
      ),
    );
    await tester.pumpWidget(panel({'extended_warranty': false}));
    expect(find.text('Warranty Job'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byKey(
        const ValueKey('warranty-job-checkbox'))).value, false);
    expect(find.byKey(const ValueKey('warranty-job-expand')), findsNothing);

    await tester.pumpWidget(panel({
      'extended_warranty': true,
      'warranty_company_name': 'Fixture Warranty',
      'authorization_number': 'TEST123',
      'approved_amount': 320.0,
      'surcharge_rate': 0.03,
    }));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byKey(
        const ValueKey('warranty-job-checkbox'))).value, true);
    expect(find.text('Fixture Warranty'), findsOneWidget);
    expect(find.byKey(const ValueKey('warranty-job-expand')), findsOneWidget);
    // A previously saved warranty invoice is collapsed until requested.
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    await tester.tap(find.byKey(const ValueKey('warranty-job-expand')));
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('warranty-job-expand')));
    await tester.pump();
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    expect(tester.widget<Checkbox>(find.byKey(
        const ValueKey('warranty-job-checkbox'))).value, true);
  });
}
