import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/blank_invoice_setup_screen.dart';

void main() {
  testWidgets('New Estimate creates a quote without requesting a Job',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home:BlankInvoiceSetupScreen(
      businessId:'shop',
      kind:'estimate',
      initialCustomerId:'customer',
      initialCustomerName:'Test Customer',
    )));
    expect(find.text('New Estimate'),findsOneWidget);
    expect(find.text('Create Estimate & Add Items'),findsOneWidget);
    expect(find.textContaining('does not create a Job until converted'),findsOneWidget);
    expect(find.text('Create Invoice & Add Items'),findsNothing);
  });

  test('Home and Customer new-estimate paths use standalone creation',() async {
    final home=await File('lib/screens/home_screen.dart').readAsString();
    final customer=await File('lib/screens/customers/customer_detail_screen.dart')
      .readAsString();
    expect(home,contains("businessId:widget.businessId,kind:'estimate'"));
    expect(customer,contains("kind:'estimate'"));
    expect(customer,contains("title: const Text('New Estimate (no Job)')"));
  });
}
