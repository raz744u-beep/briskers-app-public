import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/settings/test_data_cleanup_screen.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';
import 'package:briskers_app/services/test_job_cleanup_service.dart';
import 'test_job_cleanup_policy_test.dart' show cleanupPreview;

class _Gateway extends TestJobCleanupGateway {
  int ownerChecks = 0;
  int executions = 0;
  bool owner = true;
  bool wrongReceipt = false;
  Completer<void>? wait;
  @override
  Future<void> verifyOwner(String businessId) async {
    ownerChecks++;
    if (!owner) throw StateError('Owner access required.');
  }
  @override
  Future<Map<String, dynamic>> preview(String businessId, String jobId) async =>
      cleanupPreview()..['documents'] = [{
        'id': 'doc', 'kind': 'estimate', 'number': null,
        'status': 'draft', 'total': 137.19,
      }];
  @override
  Future<Map<String, dynamic>> execute(String businessId, String jobId,
      {required String fingerprint, required String confirmation}) async {
    executions++;
    if (wait != null) await wait!.future;
    return {'schema_version': 1, 'business_id': wrongReceipt ? 'other' : businessId,
      'job_id': jobId, 'deleted_job_id': jobId,
      'deleted_document_ids': ['doc'], 'audit_id': 'audit-1'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late _Gateway gateway;
  late TestJobCleanupService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    gateway = _Gateway();
    service = TestJobCleanupService(database: db, gateway: gateway);
    await db.customStatement("INSERT INTO local_jobs "
      "(id,business_id,access_scope,job_number,title,status) "
      "VALUES ('job','shop','full','J-8','Test','open')");
    await db.customStatement("INSERT INTO local_documents "
      "(id,business_id,job_id,kind,total) VALUES ('doc','shop','job','estimate',137.19)");
    await db.customStatement("INSERT INTO local_customers "
      "(id,business_id,display_name) VALUES ('customer','shop','Keep customer')");
    await db.customStatement("INSERT INTO local_vehicles "
      "(id,business_id) VALUES ('vehicle','shop')");
  });
  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');
  Future<void> queue({String state = 'pending'}) async {
    await db.customStatement("INSERT INTO sync_outbox "
      "(business_id,entity_type,entity_id,operation,payload_json,state) "
      "VALUES ('shop','invoice_payment_received','doc','create','{}',?)", [state]);
  }

  test('non-owner cannot read or execute cleanup even with forged UI route', () async {
    await expectLater(service.preview('shop', 'job', roleCode: 'office'), throwsStateError);
    expect(gateway.ownerChecks, 0);
    gateway.owner = false;
    await expectLater(service.preview('shop', 'job', roleCode: 'owner'), throwsStateError);
    expect(gateway.executions, 0);
  });

  test('atomic acknowledged cleanup removes only scoped jobs and docs', () async {
    final plan = await service.preview('shop', 'job', roleCode: 'owner');
    expect(plan.canDelete, isTrue);
    final receipt = await service.execute(plan,
      roleCode: 'owner', confirmation: plan.confirmationText);
    expect(receipt.auditId, 'audit-1');
    expect(await count('local_jobs'), 0);
    expect(await count('local_documents'), 0);
    expect(await count('local_customers'), 1);
    expect(await count('local_vehicles'), 1);
  });

  test('every outbox state blocks cleanup without consuming payment', () async {
    for (final state in ['pending', 'conflict', 'sending', 'unknown']) {
      await queue(state: state);
      final plan = await service.preview('shop', 'job', roleCode: 'owner');
      expect(plan.canDelete, isFalse);
      await expectLater(service.execute(plan,
        roleCode: 'owner', confirmation: plan.confirmationText), throwsStateError);
      expect(await count('sync_outbox'), 1);
      await db.customStatement('DELETE FROM sync_outbox');
    }
    expect(gateway.executions, 0);
  });

  test('queue inserted after preview is checked again immediately before server call', () async {
    final plan = await service.preview('shop', 'job', roleCode: 'owner');
    await queue();
    await expectLater(service.execute(plan,
      roleCode: 'owner', confirmation: plan.confirmationText), throwsStateError);
    expect(gateway.executions, 0);
    expect(await count('local_documents'), 1);
  });

  test('local paid or uncertain snapshot blocks even with clean outbox', () async {
    await const LocalDocumentDetailCache().save('shop', 'doc', {'paid_amount': 5});
    final plan = await service.preview('shop', 'job', roleCode: 'owner');
    expect(plan.canDelete, isFalse);
    expect(plan.blockedReasons.join(), contains('payment'));
  });

  test('mismatched acknowledgement never purges local data', () async {
    gateway.wrongReceipt = true;
    final plan = await service.preview('shop', 'job', roleCode: 'owner');
    await expectLater(service.execute(plan,
      roleCode: 'owner', confirmation: plan.confirmationText), throwsStateError);
    expect(await count('local_jobs'), 1);
    expect(await count('local_documents'), 1);
  });

  test('repeated clicks cannot issue duplicate deletion', () async {
    gateway.wait = Completer<void>();
    final plan = await service.preview('shop', 'job', roleCode: 'owner');
    final first = service.execute(plan, roleCode: 'owner', confirmation: plan.confirmationText);
    await expectLater(service.execute(plan,
      roleCode: 'owner', confirmation: plan.confirmationText), throwsStateError);
    gateway.wait!.complete();
    await first;
    expect(gateway.executions, 1);
  });

  testWidgets('offline Owner can inspect pending records with deletion disabled', (tester) async {
    gateway.owner = false; // Represents unavailable current Owner verification.
    await db.customStatement("UPDATE local_documents SET sync_state='pending'");
    await tester.pumpWidget(MaterialApp(home: TestDataCleanupScreen(
      businessId: 'shop', roleCode: 'owner', cleanupService: service)));
    await tester.pumpAndSettle();
    expect(find.text('Pending local documents · read-only preview'), findsOneWidget);
    expect(find.textContaining('137.19'), findsOneWidget);
    final cancel = tester.widget<IconButton>(find.byTooltip('Cancel local document after safety checks'));
    expect(cancel.onPressed, isNull);
    expect(gateway.executions, 0);
  });

  testWidgets('screen itself blocks non-owner without querying local or server data', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TestDataCleanupScreen(
      businessId: 'shop', roleCode: 'office', cleanupService: service)));
    expect(find.text('Owner access required.'), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
    expect(gateway.ownerChecks, 0);
  });
}
