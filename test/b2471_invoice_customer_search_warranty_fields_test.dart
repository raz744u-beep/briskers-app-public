import 'dart:async';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/jobs/blank_invoice_setup_screen.dart';
import 'package:briskers_app/screens/jobs/invoice_header_warranty_fields.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_customer_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocalCustomers extends LocalCustomerRepository {
  _LocalCustomers(BriskersLocalDatabase db) : super(database: db);

  bool complete = true;
  int queries = 0;

  @override
  Future<bool> hasBootstrap(String businessId) async => complete;

  @override
  Future<List<Map<String, dynamic>>> customers(
      String businessId, {String? search, int? limit}) async {
    queries++;
    if (search?.toLowerCase().contains('travis') == true) {
      return [
        {
          'id': 'synthetic-travis-id',
          'display_name': 'Travis Sylvester',
          '_local_snapshot': true,
        },
      ];
    }
    return [];
  }
}

class _SlowRemote extends BriskersApi {
  final Completer<List<Map<String, dynamic>>> response = Completer();
  int requests = 0;

  @override
  Future<List<Map<String, dynamic>>> customers(String businessId, {
    int limit = 500,
    String? search,
  }) {
    requests++;
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'New Invoice finds locally stored customer without waiting on Auto sync',
    (tester) async {
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.auto,
      );
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final local = _LocalCustomers(db);
      final server = _SlowRemote();
      await tester.pumpWidget(MaterialApp(
        home: BlankInvoiceSetupScreen(
          businessId: 'synthetic-shop',
          localCustomers: local,
          api: server,
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'Travis');
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump();
      expect(find.text('Travis Sylvester'), findsOneWidget);
      expect(local.queries, 1);
      expect(server.requests, 0,
          reason: 'A local search match never needs an HTTP request');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Missing local bootstrap shows a truthful incomplete-cache message '
    'without waiting for a slow HTTP response',
    (tester) async {
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.auto,
      );
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final local = _LocalCustomers(db)..complete = false;
      final server = _SlowRemote();
      await tester.pumpWidget(MaterialApp(
        home: BlankInvoiceSetupScreen(
          businessId: 'synthetic-shop',
          localCustomers: local,
          api: server,
        ),
      ));
      await tester.enterText(find.byType(TextField).first, 'Unknown');
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump();
      expect(server.requests, 1);
      expect(find.text('Checking customers not yet downloaded…'),
          findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      server.response.complete([
        {'id': 'remote-id', 'display_name': 'Unknown Customer'},
      ]);
      await tester.pump();
      expect(find.text('Unknown Customer'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Invoice header warranty fields are hidden by default, expandable, '
    'and retain entered values when collapsed',
    (tester) async {
      final claim = TextEditingController();
      final approval = TextEditingController();
      addTearDown(claim.dispose);
      addTearDown(approval.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InvoiceHeaderWarrantyFields(
            claimController: claim,
            authorizationController: approval,
          ),
        ),
      ));
      final checkbox =
          find.byKey(const ValueKey('invoice-header-warranty-checkbox'));
      expect(checkbox, findsOneWidget);
      expect(find.text('Warranty information'), findsOneWidget);
      expect(find.byKey(const ValueKey('invoice-header-warranty-claim')),
          findsNothing);
      expect(find.byKey(
          const ValueKey('invoice-header-warranty-authorization')),
          findsNothing);

      await tester.tap(checkbox);
      await tester.pump();
      final claimInput = find.byKey(
          const ValueKey('invoice-header-warranty-claim'));
      final approvalInput = find.byKey(
          const ValueKey('invoice-header-warranty-authorization'));
      expect(claimInput, findsOneWidget);
      expect(approvalInput, findsOneWidget);

      await tester.enterText(claimInput, 'CLAIM-123');
      await tester.enterText(approvalInput, 'AUTH-456');
      await tester.tap(checkbox);
      await tester.pump();
      expect(claimInput, findsNothing);
      expect(approvalInput, findsNothing);
      expect(claim.text, 'CLAIM-123');
      expect(approval.text, 'AUTH-456');
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<TextField>(claimInput).controller!.text, 'CLAIM-123');
      expect(tester.widget<TextField>(approvalInput).controller!.text, 'AUTH-456');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Existing warranty claim reference opens automatically',
      (tester) async {
    final claim = TextEditingController(text: 'SAVED-CLAIM');
    final approval = TextEditingController();
    addTearDown(claim.dispose);
    addTearDown(approval.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvoiceHeaderWarrantyFields(
          claimController: claim,
          authorizationController: approval,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('invoice-header-warranty-claim')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
