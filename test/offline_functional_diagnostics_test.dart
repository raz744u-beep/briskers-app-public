import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/offline_estimate_invoice_service.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';

Future<void> _seedCustomerVehicleJob(
  BriskersLocalDatabase database, {
  String businessId = 'business-1',
}) async {
  await database.customStatement(
    '''
    INSERT INTO local_customers (
      id, business_id, display_name, sync_state
    ) VALUES ('customer-1', ?, 'Richard Goff', 'synced')
    ''',
    [businessId],
  );
  await database.customStatement(
    '''
    INSERT INTO local_vehicles (
      id, business_id, year, make, model, sync_state
    ) VALUES ('vehicle-1', ?, 2012, 'Hyundai', 'Equus', 'synced')
    ''',
    [businessId],
  );
  await database.customStatement(
    '''
    INSERT INTO local_customer_vehicles (
      business_id, customer_id, vehicle_id, is_primary
    ) VALUES (?, 'customer-1', 'vehicle-1', 1)
    ''',
    [businessId],
  );
  await database.customStatement(
    '''
    INSERT INTO local_jobs (
      id, business_id, access_scope, job_number, title, requested_work,
      status, status_name, customer_id, customer_name,
      vehicle_id, vehicle_label, planned_hours, is_unassigned, sync_state
    ) VALUES (
      'job-1', ?, 'all', 'J-5', 'Oil leak', 'Oil leak',
      'in_progress', 'In progress', 'customer-1', 'Richard Goff',
      'vehicle-1', '2012 Hyundai Equus', 1.0, 1, 'synced'
    )
    ''',
    [businessId],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline estimate draft can be created and edited locally', () async {
    SharedPreferences.setMockInitialValues({});
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCustomerVehicleJob(database);

    const cache = LocalDocumentDetailCache();
    final service = OfflineDocumentDraftService(
      database: database,
      cache: cache,
    );

    final estimateId = await service.createEstimate('business-1', 'job-1');
    expect(estimateId, startsWith('local-estimate-'));

    await service.addLine(
      'business-1',
      estimateId,
      name: 'Transmission Fluid',
      quantity: 2,
      unitPrice: 50,
      taxRate: 0.10,
      lineKind: 'item',
    );
    await service.saveMemo(
      'business-1',
      estimateId,
      'Offline diagnostic estimate',
    );

    final detail = await cache.load('business-1', estimateId);
    expect(detail, isNotNull);
    expect((detail!['net_amount'] as num).toDouble(), closeTo(100, 0.001));
    expect((detail['tax_amount'] as num).toDouble(), closeTo(10, 0.001));
    expect((detail['total_amount'] as num).toDouble(), closeTo(110, 0.001));
    expect(detail['memo'], 'Offline diagnostic estimate');

    final queued = await database.customSelect(
      '''
      SELECT entity_type, operation, state
      FROM sync_outbox
      WHERE business_id = ? AND entity_id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        Variable<String>(estimateId),
      ],
    ).getSingle();
    expect(queued.read<String>('entity_type'), 'document_draft_create');
    expect(queued.read<String>('operation'), 'create_estimate');
    expect(queued.read<String>('state'), 'pending');

    final document = await database.customSelect(
      '''
      SELECT total, sync_state
      FROM local_documents
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        Variable<String>(estimateId),
      ],
    ).getSingle();
    expect(document.read<double>('total'), closeTo(110, 0.001));
    expect(document.read<String>('sync_state'), 'pending');

    await database.close();
  });

  test('offline estimate merge identifies same job and updates invoice once',
      () async {
    SharedPreferences.setMockInitialValues({});
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCustomerVehicleJob(database);

    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, job_id, customer_id, kind, status,
        display_status_code, converted, total, sync_state
      ) VALUES (
        'estimate-1', 'business-1', 'job-1', 'customer-1',
        'estimate', 'draft', 'draft', 0, 110, 'synced'
      )
      ''',
    );
    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, job_id, customer_id, kind, document_number,
        status, display_status_code, converted, total, sync_state
      ) VALUES (
        'invoice-1', 'business-1', 'job-1', 'customer-1',
        'invoice', '4', 'issued', 'open', 0, 220, 'synced'
      )
      ''',
    );

    const cache = LocalDocumentDetailCache();
    await cache.save('business-1', 'estimate-1', {
      'id': 'estimate-1',
      'kind': 'estimate',
      'status': 'draft',
      'customer_id': 'customer-1',
      'customer_name': 'Richard Goff',
      'job_id': 'job-1',
      'job_number': 'J-5',
      'job_title': 'Oil leak',
      'vehicle_id': null,
      'vehicle': '2012 Hyundai Equus',
      'net_amount': 100,
      'tax_amount': 10,
      'total_amount': 110,
      'converted': false,
      'lines': [
        {
          'id': 'estimate-line-1',
          'name': 'Transmission Fluid',
          'quantity': 2,
          'unit_price': 50,
          'net_amount': 100,
          'tax_amount': 10,
          'position': 1,
        },
      ],
    });
    await cache.save('business-1', 'invoice-1', {
      'id': 'invoice-1',
      'kind': 'invoice',
      'document_number': '4',
      'status': 'issued',
      'customer_id': 'customer-1',
      'customer_name': 'Richard Goff',
      'job_id': 'job-1',
      'job_number': 'J-5',
      'job_title': 'Oil leak',
      'vehicle_id': 'vehicle-1',
      'vehicle': '2012 Hyundai Equus',
      'net_amount': 200,
      'tax_amount': 20,
      'total_amount': 220,
      'lines': [
        {
          'id': 'invoice-line-1',
          'name': 'Existing work',
          'net_amount': 200,
          'tax_amount': 20,
          'position': 1,
        },
      ],
    });

    final service = OfflineEstimateInvoiceService(
      database: database,
      cache: cache,
    );

    final estimate = await cache.load('business-1', 'estimate-1');
    final eligible = await service.eligibleLocalInvoices(
      'business-1',
      estimate!,
    );
    expect(eligible, hasLength(1));
    expect(eligible.single['same_job'], isTrue);
    expect(eligible.single['same_vehicle'], isTrue);
    expect(eligible.single['customer_name'], 'Richard Goff');

    await service.mergeLocal(
      'business-1',
      estimateId: 'estimate-1',
      invoiceId: 'invoice-1',
    );

    final mergedEstimate = await cache.load('business-1', 'estimate-1');
    final mergedInvoice = await cache.load('business-1', 'invoice-1');
    expect(mergedEstimate!['converted'], isTrue);
    expect(
      (mergedInvoice!['total_amount'] as num).toDouble(),
      closeTo(330, 0.001),
    );
    expect(List<dynamic>.from(mergedInvoice['lines'] as List), hasLength(2));

    final outbox = await database.customSelect(
      '''
      SELECT entity_type, state
      FROM sync_outbox
      WHERE business_id = 'business-1'
      ''',
    ).get();
    expect(outbox, hasLength(1));
    expect(
      outbox.single.read<String>('entity_type'),
      'estimate_add_to_invoice',
    );
    expect(outbox.single.read<String>('state'), 'pending');

    await database.close();
  });

  test('customer profile, flag and vehicle changes queue offline', () async {
    SharedPreferences.setMockInitialValues({});
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCustomerVehicleJob(database);

    final service = OfflineCustomerVehicleAdminService(
      database: database,
    );

    await service.queueCustomerProfile(
      'business-1',
      'customer-1',
      name: 'Richard Goff Updated',
      phone: '5045551212',
      email: 'richard@example.com',
      billingAddress: const {'city': 'Gretna'},
    );
    await service.queueProblemFlag(
      'business-1',
      'customer-1',
      flagged: true,
      note: 'Diagnostic flag',
    );
    final vehicleId = await service.queueVehicle(
      'business-1',
      'customer-1',
      make: 'BMW',
      model: 'X5',
      year: 2020,
    );

    expect(vehicleId, startsWith('local-vehicle-'));

    final customer = await database.customSelect(
      '''
      SELECT display_name, problem_flag, sync_state
      FROM local_customers
      WHERE business_id = 'business-1' AND id = 'customer-1'
      ''',
    ).getSingle();
    expect(customer.read<String>('display_name'), 'Richard Goff Updated');
    expect(customer.read<int>('problem_flag'), 1);
    expect(customer.read<String>('sync_state'), 'pending');

    final vehicle = await database.customSelect(
      '''
      SELECT make, model, sync_state
      FROM local_vehicles
      WHERE business_id = 'business-1' AND id LIKE 'local-vehicle-%'
      ''',
    ).getSingle();
    expect(vehicle.read<String>('make'), 'BMW');
    expect(vehicle.read<String>('model'), 'X5');
    expect(vehicle.read<String>('sync_state'), 'pending');

    final outbox = await database.customSelect(
      '''
      SELECT entity_type
      FROM sync_outbox
      WHERE business_id = 'business-1'
      ORDER BY id
      ''',
    ).get();
    expect(
      outbox.map((row) => row.read<String>('entity_type')).toSet(),
      containsAll(<String>{
        'customer_profile',
        'customer_flag',
        'vehicle_create',
      }),
    );

    await database.close();
  });

  test('job admin edits, status and assignment merge into one outbox item',
      () async {
    SharedPreferences.setMockInitialValues({});
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    await _seedCustomerVehicleJob(database);

    final service = OfflineJobAdminService(database: database);
    await service.queueCore(
      'business-1',
      'job-1',
      title: 'Transmission service',
      plannedHours: 2.5,
    );
    await service.queueStatus(
      'business-1',
      'job-1',
      code: 'waiting_parts',
      name: 'Waiting parts',
      colorHex: '#E58A00',
    );
    await service.queueAssignment(
      'business-1',
      'job-1',
      employeeId: 'employee-1',
      employeeName: 'Mechanic One',
      position: 'Mechanic',
    );

    final job = await database.customSelect(
      '''
      SELECT title, planned_hours, status, assigned_employee_id,
             is_unassigned, sync_state
      FROM local_jobs
      WHERE business_id = 'business-1' AND id = 'job-1'
      ''',
    ).getSingle();
    expect(job.read<String>('title'), 'Transmission service');
    expect(job.read<double>('planned_hours'), closeTo(2.5, 0.001));
    expect(job.read<String>('status'), 'waiting_parts');
    expect(job.read<String>('assigned_employee_id'), 'employee-1');
    expect(job.read<int>('is_unassigned'), 0);
    expect(job.read<String>('sync_state'), 'pending');

    final assignment = await database.customSelect(
      '''
      SELECT employee_id, employee_name
      FROM local_job_assignments
      WHERE business_id = 'business-1' AND job_id = 'job-1'
      ''',
    ).getSingle();
    expect(assignment.read<String>('employee_id'), 'employee-1');
    expect(assignment.read<String>('employee_name'), 'Mechanic One');

    final outbox = await database.customSelect(
      '''
      SELECT payload_json
      FROM sync_outbox
      WHERE business_id = 'business-1'
        AND entity_type = 'job_admin'
      ''',
    ).get();
    expect(outbox, hasLength(1));
    final payload = Map<String, dynamic>.from(
      jsonDecode(outbox.single.read<String>('payload_json')) as Map,
    );
    expect(payload['core_changed'], isTrue);
    expect(payload['status_changed'], isTrue);
    expect(payload['assignment_changed'], isTrue);

    await database.close();
  });

  test('expense creation and edit stay local and update pending create',
      () async {
    SharedPreferences.setMockInitialValues({});
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalFinancialCache(database: database);
    final service = OfflineFinancialWriteService(
      database: database,
      cache: cache,
    );

    final created = await service.createLocalTransaction(
      'business-1',
      direction: 'expense',
      accountId: 'account-1',
      accountName: 'Checking',
      categoryId: 'category-1',
      categoryName: 'Supplies',
      amount: 100,
      date: DateTime(2026, 10, 6),
      counterpartyName: 'Parts Vendor',
      remarks: 'Offline diagnostic expense',
      receipts: const [],
    );
    final id = created['id']!.toString();
    expect(id, startsWith('local-transaction-'));

    final updated = await service.updateLocalTransaction(
      'business-1',
      id,
      direction: 'expense',
      accountId: 'account-1',
      accountName: 'Checking',
      categoryId: 'category-1',
      categoryName: 'Supplies',
      amount: 125,
      date: DateTime(2026, 10, 6),
      counterpartyName: 'Parts Vendor',
      remarks: 'Updated offline',
    );
    expect((updated['amount'] as num).toDouble(), closeTo(125, 0.001));

    final rows = await cache.loadTransactions('business-1');
    expect(rows, hasLength(1));
    expect((rows.single['amount'] as num).toDouble(), closeTo(125, 0.001));

    final outbox = await database.customSelect(
      '''
      SELECT entity_type, payload_json
      FROM sync_outbox
      WHERE business_id = 'business-1'
      ''',
    ).get();
    expect(outbox, hasLength(1));
    expect(outbox.single.read<String>('entity_type'), 'financial_create');
    expect(
      outbox.single.read<String>('payload_json'),
      contains('"amount":125'),
    );

    await database.close();
  });
}
