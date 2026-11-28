import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/repair_group_schema.dart';
import 'package:briskers_app/services/lan_customer_vehicle_copy.dart';
import 'package:briskers_app/services/lan_record_inventory.dart';
import 'package:briskers_app/services/local_number_allocator.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const shop = 'shop';

  Future<void> seedCursor(BriskersLocalDatabase db, int cursor) =>
      db.customStatement(
        "INSERT INTO local_sync_states (business_id, scope, last_server_cursor, bootstrapped) VALUES (?, 'customers_vehicles', ?, 1)",
        [shop, cursor],
      );

  String identity(String kind, String id) =>
      LanRecordInventory.recordIdentity(shop, kind, id);

  test('copies approved customer and vehicle together without overwriting or queuing a cloud write', () async {
    final sender = BriskersLocalDatabase(NativeDatabase.memory());
    final receiver = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(sender.close);
    addTearDown(receiver.close);
    await seedCursor(sender, 40);
    await seedCursor(receiver, 35);
    await sender.customStatement(
      "INSERT INTO local_customers (id, business_id, display_name, phone) VALUES "
      "('missing','shop','Alex Example','504-555-0100'),"
      "('same-id','shop','From Source',NULL),"
      "('dupe','shop','Another Customer','504-555-0123'),"
      "('protected','shop','Vehicle Key Customer',NULL)",
    );
    await sender.customStatement(
      "INSERT INTO local_vehicles (id, business_id, vin, key_password) VALUES "
      "('car','shop','1FAFP404X1F100001',NULL),"
      "('protected-car','shop','1FAFP404X1F100002','protected-key')",
    );
    await sender.customStatement(
      "INSERT INTO local_customer_vehicles (business_id,customer_id,vehicle_id) VALUES "
      "('shop','missing','car'),('shop','protected','protected-car')",
    );
    await receiver.customStatement(
      "INSERT INTO local_customers (id, business_id, display_name, phone) VALUES "
      "('same-id','shop','Receiver Has Edits',NULL),"
      "('duplicate-on-receiver','shop','Existing Customer','(504) 555-0123')",
    );
    final out = await LanCustomerVehicleCopy(sender).share(shop);
    final bundle = jsonDecode(jsonEncode(out)) as Map<String, dynamic>;
    expect(jsonEncode(bundle), isNot(contains('protected-key')));
    final approval = {
      identity('customer', 'missing'),
      identity('customer', 'same-id'),
      identity('customer', 'dupe'),
      identity('customer', 'protected'),
      identity('vehicle', 'car'),
      identity('vehicle', 'protected-car'),
    };
    final copy = LanCustomerVehicleCopy(receiver);
    final result = await copy.copyMissing(
      business: shop,
      bundle: bundle,
      approvedIdentities: approval,
    );
    expect(result, (customers: 1, vehicles: 1, jobs: 0, estimates: 0));
    final customers = {
      for (final row in await receiver.select(receiver.localCustomers).get())
        row.id: row.displayName,
    };
    expect(customers, {
      'same-id': 'Receiver Has Edits',
      'duplicate-on-receiver': 'Existing Customer',
      'missing': 'Alex Example',
    });
    final link = await receiver
        .select(receiver.localCustomerVehicles)
        .getSingle();
    expect((link.customerId, link.vehicleId), ('missing', 'car'));
    expect(await receiver.select(receiver.syncOutbox).get(), isEmpty);
    expect(
      (await receiver.select(receiver.localSyncStates).getSingle())
          .lastServerCursor,
      35,
    );
    expect(
      await copy.copyMissing(
        business: shop,
        bundle: bundle,
        approvedIdentities: approval,
      ),
      (customers: 0, vehicles: 0, jobs: 0, estimates: 0),
    );
  });

  test(
    'copies only approved standalone jobs with matching dependencies',
    () async {
      final sender = BriskersLocalDatabase(NativeDatabase.memory());
      final receiver = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(sender.close);
      addTearDown(receiver.close);
      for (final db in [sender, receiver]) {
        await seedCursor(db, 40);
        await db.customStatement(
          "INSERT INTO local_sync_states (business_id, scope, last_server_cursor, bootstrapped) VALUES ('shop', 'jobs', 40, 1)",
        );
        await db.customStatement(
          "INSERT INTO local_customers (id, business_id, display_name) VALUES ('customer','shop','Alex Example')",
        );
        await db.customStatement(
          "INSERT INTO local_vehicles (id, business_id, vin) VALUES ('car','shop','1FAFP404X1F100001')",
        );
        await db.customStatement(
          "INSERT INTO local_customer_vehicles (business_id,customer_id,vehicle_id) VALUES ('shop','customer','car')",
        );
      }

      Future<void> job(BriskersLocalDatabase db, String id, String number) =>
          db.customStatement(
            "INSERT INTO local_jobs (id,business_id,access_scope,job_number,title,status,customer_id,vehicle_id) "
            "VALUES (?,'shop','full',?,'Check brakes','open','customer','car')",
            [id, number],
          );

      await job(sender, 'eligible', 'J-81');
      await job(sender, 'attached', 'J-82');
      await job(sender, 'pending-visit', 'J-87');
      await job(sender, 'visit-conflict', 'J-88');
      await job(sender, 'with-finding', 'J-86');
      await job(sender, 'number-conflict', 'J-83');
      await job(sender, 'unapproved', 'J-84');
      await job(receiver, 'already-here', '0083');
      await job(sender, 'reserved-number', 'J-85');
      await LocalNumberAllocator(receiver).allocate(
        shop,
        'job',
        'pending-job',
        requested: 85,
      );
      await sender.customStatement(
        "INSERT INTO local_job_visits (id,business_id,job_id,visit_number,work_summary,sync_state) VALUES "
        "('visit','shop','attached',1,'Brake check','synced'),"
        "('local-visit-pending','shop','pending-visit',1,NULL,'pending'),"
        "('occupied-visit','shop','visit-conflict',1,NULL,'synced')",
      );
      await receiver.customStatement(
        "INSERT INTO local_job_visits (id,business_id,job_id,visit_number) "
        "VALUES ('occupied-visit','shop','already-here',1)",
      );
      await sender.customStatement(
        "INSERT INTO local_findings (id,business_id,found_job_id,body,status) "
        "VALUES ('finding','shop','with-finding','Brake wear','unresolved')",
      );
      final bundle = jsonDecode(
        jsonEncode(await LanCustomerVehicleCopy(sender).share(shop)),
      ) as Map<String, dynamic>;
      final copy = LanCustomerVehicleCopy(receiver);
      Future<({int customers, int vehicles, int jobs, int estimates})> apply() =>
          copy.copyMissing(
            business: shop,
            bundle: bundle,
            approvedIdentities: {
              identity('job', 'eligible'),
              identity('job', 'attached'),
              identity('job', 'pending-visit'),
              identity('job', 'visit-conflict'),
              identity('job', 'with-finding'),
              identity('job', 'number-conflict'),
              identity('job', 'reserved-number'),
            },
          );

      await receiver.customStatement(
        "UPDATE local_sync_states SET last_server_cursor=41 WHERE business_id='shop' AND scope='jobs'",
      );
      expect(await apply(), (customers: 0, vehicles: 0, jobs: 0, estimates: 0));
      await receiver.customStatement(
        "UPDATE local_sync_states SET last_server_cursor=40 WHERE business_id='shop' AND scope='jobs'",
      );
      final jobBundle = bundle['jobs'] as Map<String, dynamic>;
      expect((jobBundle['records'] as List).map((row) => row['id']),
          isNot(contains('attached')));
      final malformed = jsonDecode(jsonEncode(bundle)) as Map<String, dynamic>;
      malformed['jobs']['recordsWithVisits'][0]['visits'][0]['jobId'] = 'wrong-parent';
      await expectLater(
        copy.copyMissing(
          business: shop,
          bundle: malformed,
          approvedIdentities: {identity('job', 'attached')},
        ),
        throwsFormatException,
      );
      expect(await apply(), (customers: 0, vehicles: 0, jobs: 2, estimates: 0));
      expect(await apply(), (customers: 0, vehicles: 0, jobs: 0, estimates: 0));
      final saved = await receiver.select(receiver.localJobs).get();
      expect(
        saved.map((job) => job.id),
        unorderedEquals(['eligible', 'attached', 'already-here']),
      );
      final history = await receiver.customSelect(
        "SELECT job_id,work_summary FROM local_job_visits WHERE id='visit'",
      ).getSingle();
      expect(history.data, {'job_id': 'attached', 'work_summary': 'Brake check'});
      final sourceInventory = await LanRecordInventory(sender).read(shop);
      await receiver.customStatement(
        "UPDATE local_job_visits SET work_summary='Receiver edit' WHERE id='visit'",
      );
      final differences = LanRecordInventory.compare(
        sourceInventory, await LanRecordInventory(receiver).read(shop),
      );
      expect(
        differences.different.map((entry) => entry.identity),
        contains(identity('job', 'attached')),
      );
      expect(await receiver.select(receiver.syncOutbox).get(), isEmpty);
    },
  );

  test('copies estimate index, lines, and valid repair groups together', () async {
    final sender = BriskersLocalDatabase(NativeDatabase.memory());
    final receiver = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(sender.close);
    addTearDown(receiver.close);
    for (final db in [sender, receiver]) {
      await seedCursor(db, 40);
      await db.customStatement(
        "INSERT INTO local_sync_states (business_id, scope, last_server_cursor, bootstrapped) "
        "VALUES ('shop','documents',40,1)",
      );
      await db.customStatement(
        "INSERT INTO local_customers (id,business_id,display_name) "
        "VALUES ('customer','shop','Alex Example')",
      );
    }

    Future<void> seedEstimate(
      BriskersLocalDatabase db,
      String id,
      String number, {
      bool withDetail = true,
    }) async {
      await db.customStatement(
        "INSERT INTO local_documents (id,business_id,customer_id,kind,document_number,status,total,row_version) "
        "VALUES (?,'shop','customer','estimate',?,'draft',145,2)",
        [id, number],
      );
      if (withDetail) {
        await LocalDocumentSqlStore.write(
          db,
          LocalDocumentDetailCache.key(shop, id),
          jsonEncode({
            'id': id,
            'kind': 'estimate',
            'customer_id': 'customer',
            'document_number': number,
            'status': 'draft',
            'row_version': 2,
            'lines': [{'id': 'line-1', 'name': 'Transmission service'}],
          }),
        );
      }
    }

    await seedEstimate(sender, 'eligible', 'E-81');
    await seedEstimate(sender, 'number-conflict', 'E-82');
    await seedEstimate(sender, 'list-only', 'E-83', withDetail: false);
    await seedEstimate(sender, 'grouped', 'E-84');
    await seedEstimate(sender, 'orphaned-member', 'E-85');
    await seedEstimate(sender, 'receiver-has-groups', 'E-86');
    await RepairGroupSchema.ensure(sender);
    await sender.customStatement(
      "INSERT INTO repair_groups_v1 VALUES "
      "('shop','grouped','group','Repair','Transmission',2,'[]'),"
      "('shop','grouped','empty','Later','',1,'[]')",
    );
    await sender.customStatement(
      "INSERT INTO repair_group_members_v1 VALUES "
      "('shop','grouped','line-1','group'),"
      "('shop','orphaned-member','line-1','missing')",
    );
    await RepairGroupSchema.ensure(receiver);
    await receiver.customStatement(
      "INSERT INTO repair_groups_v1 VALUES "
      "('shop','receiver-has-groups','local','Receiver work','',1,'[]')",
    );
    await seedEstimate(receiver, 'existing', '00082');
    final bundle = jsonDecode(
      jsonEncode(await LanCustomerVehicleCopy(sender).share(shop)),
    ) as Map<String, dynamic>;
    final copy = LanCustomerVehicleCopy(receiver);
    Future<({int customers, int vehicles, int jobs, int estimates})> apply() =>
        copy.copyMissing(
          business: shop,
          bundle: bundle,
          approvedIdentities: {
            for (final id in [
              'eligible', 'number-conflict', 'list-only', 'grouped',
              'orphaned-member', 'receiver-has-groups',
            ])
              identity('estimate', id),
          },
        );

    final estimates = bundle['estimates'] as Map<String, dynamic>;
    expect(
      (estimates['records'] as List).map((row) => row['index']['id']),
      isNot(contains('grouped')),
    );
    final invalidBundle = jsonDecode(jsonEncode(bundle)) as Map<String, dynamic>;
    final grouped = (invalidBundle['estimates']['groupedRecords'] as List).single;
    grouped['repairGroups']['members'][0][1] = 'missing-group';
    await expectLater(
      copy.copyMissing(
        business: shop,
        bundle: invalidBundle,
        approvedIdentities: {identity('estimate', 'eligible'), identity('estimate', 'grouped')},
      ),
      throwsFormatException,
    );
    expect(
      (await receiver.select(receiver.localDocuments).get()).map((row) => row.id),
      ['existing'],
    );
    expect(await apply(), (customers: 0, vehicles: 0, jobs: 0, estimates: 2));
    expect(await apply(), (customers: 0, vehicles: 0, jobs: 0, estimates: 0));
    expect(
      (await receiver.select(receiver.localDocuments).get()).map((row) => row.id),
      unorderedEquals(['eligible', 'existing', 'grouped']),
    );
    final raw = await LocalDocumentSqlStore.read(
      receiver,
      LocalDocumentDetailCache.key(shop, 'eligible'),
    );
    expect(jsonDecode(raw!)['lines'].single['name'], 'Transmission service');
    final groups = await receiver.customSelect(
      "SELECT id,name,description,position FROM repair_groups_v1 "
      "WHERE business='shop' AND estimate='grouped' ORDER BY position",
    ).get();
    expect(groups.map((row) => row.data), [
      {'id': 'empty', 'name': 'Later', 'description': '', 'position': 1},
      {'id': 'group', 'name': 'Repair', 'description': 'Transmission', 'position': 2},
    ]);
    final member = await receiver.customSelect(
      "SELECT line,group_id FROM repair_group_members_v1 "
      "WHERE business='shop' AND estimate='grouped'",
    ).getSingle();
    expect(member.data, {'line': 'line-1', 'group_id': 'group'});
    final sourceInventory = await LanRecordInventory(sender).read(shop);
    await receiver.customStatement(
      "UPDATE repair_groups_v1 SET name='Changed on receiver' "
      "WHERE business='shop' AND estimate='grouped' AND id='group'",
    );
    final differences = LanRecordInventory.compare(
      sourceInventory, await LanRecordInventory(receiver).read(shop),
    );
    expect(differences.different.map((entry) => entry.identity),
        contains(identity('estimate', 'grouped')));
    expect(await receiver.select(receiver.syncOutbox).get(), isEmpty);
  });

  test(
    'refuses older source evidence and leaves the receiver untouched',
    () async {
      final receiver = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(receiver.close);
      await seedCursor(receiver, 41);
      final copy = LanCustomerVehicleCopy(receiver);
      await expectLater(
        copy.copyMissing(
          business: shop,
          bundle: {
            'version': 1,
            'cursor': 40,
            'customers': [],
            'vehicles': [],
            'links': [],
          },
          approvedIdentities: const {},
        ),
        throwsStateError,
      );
      expect(await receiver.select(receiver.localCustomers).get(), isEmpty);
    },
  );
}
