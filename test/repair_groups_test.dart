import 'dart:convert';
import 'dart:io';
import 'package:briskers_app/core/repair_group.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_repair_groups.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalDocumentDetailCache cache;
  late OfflineDocumentDraftService drafts;
  late LocalRepairGroups groups;
  late String estimate;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalDocumentDetailCache(database: db);
    LocalDocumentDetailCache.sqliteWritesEnabled = true;
    drafts = OfflineDocumentDraftService(database: db, cache: cache);
    groups = LocalRepairGroups(database: db, cache: cache);
    estimate = await drafts.createStandaloneEstimate('shop', customerId: 'customer', customerName: 'Customer');
    for (final name in ['Brakes', 'Oil']) {
      await drafts.addLine('shop', estimate, name: name, quantity: 1,
        unitPrice: 100, taxRate: 0.1, lineKind: 'part');
    }
  });
  tearDown(() async { await db.close(); LocalDocumentDetailCache.sqliteWritesEnabled = false; });
  Future<Map<String, dynamic>> detail() async => (await cache.load('shop', estimate))!;
  Future<String> firstGroup() async {
    final id = await groups.add('shop', estimate, 'Brake repair');
    final lines = (await detail())['lines'] as List;
    await groups.move('shop', estimate, (lines.first as Map)['id'] as String, id);
    return id;
  }
  Future<void> authorize(String id, {String event = 'event', RepairDecision decision = RepairDecision.approved}) async {
    await groups.authorize('shop', estimate, eventId: event,
      expectedScope: await groups.snapshot('shop', estimate, await detail()),
      decisions: {id: decision}, method: RepairAuthorizationMethod.telephone,
      actor: 'Owner', notes: 'Customer authorized by telephone');
  }

  test('old estimate keeps all items and conversion behavior', () async {
    expect(await groups.enabled('shop', estimate), isFalse);
    final invoice = await drafts.convertEstimateOffline('shop', estimate);
    expect((await cache.load('shop', invoice))!['lines'], hasLength(2));
    expect(await drafts.convertEstimateOffline('shop', estimate), invoice);
  });
  test('move, rename, reorder and remove preserve line identity and total offline', () async {
    final before = await detail();
    final a = await firstGroup();
    final b = await groups.add('shop', estimate, 'Second');
    await groups.edit('shop', estimate, a, name: 'Brakes', description: 'Front axle');
    await groups.reorder('shop', estimate, [b, a]);
    final views = await groups.groups('shop', estimate, await detail());
    expect(views.map((group) => group.id), [b, a, RepairGroup.otherId]);
    expect(views.expand((group) => group.lines), hasLength(2));
    expect((await detail())['total_amount'], before['total_amount']);
    expect((await db.customSelect("SELECT * FROM repair_groups_v1 WHERE id='__other_items__'").get()), isEmpty);
    await groups.remove('shop', estimate, a);
    expect((await groups.groups('shop', estimate, await detail())).last.lines, hasLength(2));
  });
  test('only approved groups convert; source, declined quote and audit survive', () async {
    final a = await firstGroup();
    await authorize(a);
    await authorize(RepairGroup.otherId, event: 'decline', decision: RepairDecision.declined);
    final invoice = await drafts.convertEstimateOffline('shop', estimate);
    final billed = (await cache.load('shop', invoice))!;
    expect(billed['lines'], hasLength(1));
    expect(billed['total_amount'], 110);
    expect((await detail())['lines'], hasLength(2));
    expect(await groups.history('shop', estimate), hasLength(2));
    expect(await drafts.convertEstimateOffline('shop', estimate), invoice);
    expect(await db.customSelect("SELECT * FROM local_documents WHERE kind='invoice'").get(), hasLength(1));
    final unchanged = await groups.history('shop', estimate);
    await expectLater(db.customStatement('DELETE FROM repair_authorizations_v1'), throwsA(anything));
    expect(await groups.history('shop', estimate), unchanged);
  });
  test('undecided or all declined cannot bill supplies', () async {
    final a = await firstGroup();
    await drafts.addLine('shop', estimate, name: 'Shop supplies', quantity: 1,
      unitPrice: 15, taxRate: 0, lineKind: 'item');
    await expectLater(drafts.convertEstimateOffline('shop', estimate), throwsStateError);
    await authorize(a, decision: RepairDecision.declined);
    await authorize(RepairGroup.otherId, event: 'decline-other', decision: RepairDecision.declined);
    await expectLater(drafts.convertEstimateOffline('shop', estimate), throwsStateError);
    expect(await db.customSelect("SELECT * FROM local_documents WHERE kind='invoice'").get(), isEmpty);
  });
  test('edit and revert require renewed authorization, unaffected group remains approved', () async {
    final a = await firstGroup();
    await authorize(a);
    await authorize(RepairGroup.otherId, event: 'other');
    final line = ((await detail())['lines'] as List).first as Map;
    for (final price in [120, 100]) {
      await drafts.updateLine('shop', estimate, line['id'] as String,
        name: 'Brakes', quantity: 1, unitPrice: price, taxRate: 0.1, lineKind: 'part');
    }
    final states = await groups.decisions('shop', estimate, await detail());
    expect(states[a], RepairDecision.awaitingDecision);
    expect(states[RepairGroup.otherId], RepairDecision.approved);
    expect(await groups.history('shop', estimate), hasLength(2));
  });
  test('identical authorization retry is idempotent; conflicting event is rejected', () async {
    final a = await firstGroup();
    await authorize(a);
    await authorize(a);
    expect(await groups.history('shop', estimate), hasLength(1));
    await expectLater(authorize(a, decision: RepairDecision.declined), throwsStateError);
  });
  test('stale review and cross-business mutation fail without task or payment effects', () async {
    final a = await firstGroup();
    final scope = await groups.snapshot('shop', estimate, await detail());
    await groups.edit('shop', estimate, a, name: 'New scope', description: 'Changed');
    await expectLater(groups.authorize('shop', estimate, eventId: 'stale', expectedScope: scope,
      decisions: {a: RepairDecision.approved}, method: RepairAuthorizationMethod.inPerson,
      actor: 'Owner', notes: 'Customer present'), throwsStateError);
    await expectLater(groups.add('other-shop', estimate, 'Foreign group'), throwsStateError);
    expect(await groups.history('shop', estimate), isEmpty);
  });
  test('authorization leaves existing task states, assignments, payroll, numbering and payments untouched', () async {
    final payroll = LocalPayrollRepository(db, business: 'shop', owner: true);
    await payroll.prepare();
    await drafts.createQuickInvoice('shop', customerId: 'customer', customerName: 'Customer', initialLines: [
      {'name': 'Labor', 'description': 'Existing work', 'line_kind': 'labor',
        'quantity': 2, 'unit_price': 100, 'tax_rate': 0}
    ]);
    final a = await firstGroup();
    Future<String> protectedSnapshot() async {
      final result = <String, dynamic>{};
      for (final table in ['local_jobs', 'local_documents', 'regular_payroll_tasks',
        'regular_payroll_portions', 'regular_payroll_payments', 'regular_payroll_paid_work', 'sync_outbox']) {
        result[table] = (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get()).map((row) => row.data).toList();
      }
      return jsonEncode(result);
    }
    final before = await protectedSnapshot();
    await authorize(a);
    expect(await protectedSnapshot(), before);
  });
  test('signed decisions retain original photographs after source removal and replay after conversion', () async {
    final a = await firstGroup();
    final folder = await Directory.systemTemp.createTemp('repair-evidence-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/finding.png');
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lfoAAAAASUVORK5CYII=');
    await file.writeAsBytes(png);
    await groups.edit('shop', estimate, a, name: 'Brakes', description: 'Worn pads', evidence: [
      {'id': 'finding', 'body': 'Pads worn', 'photos': [{'local_file_path': file.path}]}
    ]);
    final scope = await groups.snapshot('shop', estimate, await detail());
    Future<void> submit() => groups.authorize('shop', estimate, eventId: 'signed', expectedScope: scope,
      decisions: {a: RepairDecision.approved}, method: RepairAuthorizationMethod.deviceSignature,
      actor: 'Customer', signature: png);
    await submit();
    final event = (await groups.history('shop', estimate)).single;
    final repair = (event['groups'] as List).single as Map;
    final finding = (repair['evidence'] as List).single as Map;
    final photo = (finding['photos'] as List).single as Map;
    await file.delete();
    expect(await groups.media('shop', photo['media_ref'] as String), png);
    expect(await groups.signature('shop', 'signed'), png);
    await drafts.convertEstimateOffline('shop', estimate);
    await submit();
    expect(await groups.history('shop', estimate), hasLength(1));
    await expectLater(db.customStatement('DELETE FROM repair_signatures_v1'), throwsA(anything));
    await expectLater(db.customStatement('DELETE FROM repair_authorization_media_v1'), throwsA(anything));
  });
  test('job-linked quote remains in the exact vehicle history without duplicated vehicle metadata', () async {
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,vehicle_id) VALUES('job','shop','full','Repair','open','vehicle')");
    await cache.save('shop', estimate, {...await detail(), 'job_id': 'job', 'vehicle_id': null});
    final a = await firstGroup();
    await authorize(a, decision: RepairDecision.declined);
    expect(await groups.vehicleHistory('shop', 'vehicle'), hasLength(1));
    expect(await groups.vehicleHistory('other-shop', 'vehicle'), isEmpty);
    expect(await groups.vehicleHistory('shop', 'unrelated-vehicle'), isEmpty);
  });
}
