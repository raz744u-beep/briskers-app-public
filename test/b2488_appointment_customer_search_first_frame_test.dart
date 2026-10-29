import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/appointments/appointment_manage_screen.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_customer_repository.dart';

class _Customers extends LocalCustomerRepository {
  _Customers(BriskersLocalDatabase db) : super(database: db);
  final all = <Map<String, dynamic>>[
    {'id': 'a-1', 'display_name': 'Aaron Barbes'},
    {'id': 'a-2', 'display_name': 'Aaron Rivera'},
    {'id': 'b-1', 'display_name': 'Bertha Customer'},
  ];
  final searches = <String>[];

  @override
  Future<List<Map<String, dynamic>>> customers(
    String businessId, {String? search, int? limit}) async {
    searches.add(search ?? '<all>');
    final query = (search ?? '').toLowerCase();
    return all.where((row) => row['display_name']
        .toString().toLowerCase().contains(query)).take(limit ?? 40).toList();
  }

  @override
  Future<Map<String, dynamic>?> customerDetail(
    String businessId, String customerId) async => {
      'id': customerId,
      'vehicles': [
        {'id': 'vehicle-1', 'year': 2015, 'make': 'BMW', 'model': '528i'},
      ],
    };

  @override
  Future<bool> hasBootstrap(String businessId) async => true;
}

class _Employees extends BriskersApi {
  _Employees(this.pending);
  final Completer<List<Map<String, dynamic>>> pending;

  @override
  Future<List<Map<String, dynamic>>> assignableEmployees(
      String businessId) => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Appointment opens without waiting for employee RPC or 2,799 customers',
      (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final customers = _Customers(db);
    final employeeRequest = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(MaterialApp(
      home: AppointmentManageScreen(
        businessId: 'synthetic-shop', localCustomers: customers,
        api: _Employees(employeeRequest)),
    ));
    await tester.pump();

    expect(find.text('Add appointment'), findsOneWidget);
    expect(find.byKey(const ValueKey('appointment-customer-search')),
        findsOneWidget);
    expect(find.text('Search name, phone, or email'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(customers.searches, isEmpty,
      reason: 'Opening the form never scans the whole customer table.');
    expect(find.text('Aaron Barbes'), findsNothing);

    employeeRequest.complete([]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Appointment customer search filters locally, selects and clears',
      (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final customers = _Customers(db);
    await tester.pumpWidget(MaterialApp(
      home: AppointmentManageScreen(
        businessId: 'synthetic-shop', localCustomers: customers,
        api: _Employees(Completer<List<Map<String, dynamic>>>()..complete([]))),
    ));
    await tester.enterText(
      find.byKey(const ValueKey('appointment-customer-search')), 'Aaron');
    await tester.pump(const Duration(milliseconds: 75));
    await tester.pumpAndSettle();

    expect(customers.searches, ['Aaron']);
    expect(find.text('Aaron Barbes'), findsOneWidget);
    expect(find.text('Aaron Rivera'), findsOneWidget);
    expect(find.text('Bertha Customer'), findsNothing);
    await tester.tap(find.text('Aaron Rivera'));
    await tester.pumpAndSettle();
    expect(find.text('No matching saved customers.'), findsNothing);
    expect(find.text('2015 BMW 528i'), findsOneWidget);

    final clear = find.byKey(const ValueKey('appointment-customer-clear'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.text('2015 BMW 528i'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('Appointment editor cannot show unfiltered customer dropdown or initial spinner',
      () {
    final s = File('lib/screens/appointments/appointment_manage_screen.dart')
      .readAsStringSync();
    expect(s, contains("key: const ValueKey('appointment-customer-search')"));
    expect(s, contains("key: const ValueKey('appointment-customer-clear')"));
    expect(s, contains("search: query, limit: 40"));
    expect(s, contains("const Duration(milliseconds: 60)"));
    expect(s, contains("void _load() {"));
    expect(s, contains('unawaited(_loadEmployeesInBackground())'));
    expect(s, isNot(contains('await _localCustomers.customers(widget.businessId)')));
    expect(s, isNot(contains("if (_loading) {")));
    expect(s, contains('await _sync.queueCreate(widget.businessId,'));
  });
}
