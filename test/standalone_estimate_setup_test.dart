import 'dart:io';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/local_number_allocator.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/blank_invoice_setup_screen.dart';

void main() {
  testWidgets('New Estimate creates a quote without requesting a Job',
      (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      debugUseLocalDatabase(null);
      await db.close();
    });
    debugUseLocalDatabase(db);
    await tester.runAsync(() async {
      final allocator = LocalNumberAllocator(db);
      await allocator.allocate('shop', 'estimate', 'deleted', requested: 4681);
      await allocator.release('shop', 'estimate', 'deleted');
    });
    await tester.pumpWidget(const MaterialApp(home:BlankInvoiceSetupScreen(
      businessId:'shop',
      kind:'estimate',
      initialCustomerId:'customer',
      initialCustomerName:'Test Customer',
      initialVehicles: [
        {'id':'synthetic-vehicle','year':2018,'make':'BMW','model':'X3'},
      ],
    )));
    for (var attempt = 0; attempt < 50 && find.text('Next: E-4682').evaluate().isEmpty; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.text('Next: E-4682'), findsOneWidget);
    await tester.tap(find.text('Next: E-4682'));
    await tester.pumpAndSettle();
    expect(find.text('Reuse from pool: E-4681'), findsOneWidget);
    await tester.tap(find.text('Reuse from pool: E-4681'));
    await tester.pumpAndSettle();
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
