import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_number_service.dart';
import 'package:briskers_app/services/local_numbered_document_overlay.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';

class _Store implements OwnerEnrollmentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  late BriskersLocalDatabase db;
  late Directory dir;
  late LocalOwnerAuthorization authority;
  late LocalOwnerGrant grant;
  late bool offline;
  const identity = OwnerSessionIdentity('owner', 'session');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('job-number-');
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    offline = true;
    authority = LocalOwnerAuthorization(
      store: _Store(), currentIdentity: () => identity,
      verifyOwner: (b) async => VerifiedOwnerEnrollment(identity, b),
      verifyLocalOwner: (b) async => VerifiedOwnerEnrollment(identity, b),
      authenticateDevice: () async => true,
    );
    grant = await authority.authorizeLocal('shop');
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,"
      "job_number,customer_id,vehicle_id,sync_state) "
      "VALUES('job','shop','full','Repair','open','J-45','customer','vehicle','pending')");
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,"
      "document_number,status,total,sync_state) "
      "VALUES('invoice','shop','job','customer','invoice','9001','issued',446.68,'pending')");
    for (final entry in {
      'document_draft_create': {
        'operation_id': 'draft-op', 'provisional_job_id': 'job',
        'local_document_number': '9001', 'local_job_number': 'J-45',
        'customer_id': 'customer', 'vehicle_id': 'vehicle',
      },
      'invoice_payment_received': {
        'operation_id': 'payment-op', 'invoice_id': 'invoice',
        'amount_cents': 44668, 'method_id': 'cash',
      },
    }.entries) {
      await db.customStatement(
        "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,"
        "payload_json,state,attempt_count,created_at) "
        "VALUES('shop',?,'invoice','create',?,'pending',0,1)",
        [entry.key, jsonEncode(entry.value)]);
    }
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<void> assign([int number = 34]) => LocalJobNumberService(db,
      forceOffline: () => offline).assign('shop', 'invoice', 'job', number, grant);
  Future<Map<String, dynamic>> row(String table) async =>
      (await db.customSelect('SELECT * FROM $table LIMIT 1').getSingle()).data;
  Future<String> payment() async => (await db.customSelect(
      "SELECT payload_json FROM sync_outbox WHERE entity_type='invoice_payment_received'")
      .getSingle()).read<String>('payload_json');

  test('renumber preserves customer, vehicle, invoice and payment through restart', () async {
    final beforeJob = await row('local_jobs');
    final beforeInvoice = await row('local_documents');
    final beforePayment = await payment();
    await assign();
    expect(await row('local_jobs'), {...beforeJob, 'job_number': 'J-34'});
    expect(await row('local_documents'), beforeInvoice);
    expect(await payment(), beforePayment);
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    expect((await row('local_jobs'))['job_number'], 'J-34');
    expect(await payment(), beforePayment);
    final projected = await LocalNumberedDocumentOverlay(database: db)
        .apply('shop', 'invoice', {'job_number': 'J-45', 'paid_amount': 446.68});
    expect(projected['job_number'], 'J-34');
    expect(projected['paid_amount'], 446.68);
    final draft = await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='document_draft_create'")
        .getSingle();
    expect(jsonDecode(draft.read<String>('payload_json'))['local_job_number'], 'J-34');
  });

  test('duplicate number rolls back job and old reservation', () async {
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('other','shop','full','Other','completed','J34')");
    await expectLater(assign(), throwsStateError);
    expect((await row('local_jobs'))['job_number'], 'J-45');
    expect((await row('local_documents'))['document_number'], '9001');
  });

  test('number freed by local deletion is reusable', () async {
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('old','shop','full','Old','open','J-34')");
    await expectLater(assign(), throwsStateError);
    await db.customStatement("DELETE FROM local_jobs WHERE id='old'");
    await assign();
    expect((await row('local_jobs'))['job_number'], 'J-34');
  });

  test('expired Owner grant, wrong linkage and online mode cannot change job', () async {
    await expectLater(LocalJobNumberService(db, forceOffline: () => true)
        .assign('shop', 'invoice', 'wrong', 34, grant), throwsStateError);
    offline = false;
    await expectLater(assign(), throwsStateError);
    offline = true;
    authority.lock();
    await expectLater(assign(), throwsStateError);
    expect((await row('local_jobs'))['job_number'], 'J-45');
  });

  test('authorization lost before commit rolls back all changes', () async {
    var checks = 0;
    final before = await row('local_jobs');
    await expectLater(LocalJobNumberService(db, forceOffline: () {
      checks++;
      return checks < 3;
    }).assign('shop', 'invoice', 'job', 34, grant), throwsStateError);
    expect(await row('local_jobs'), before);
    final draft = await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE entity_type='document_draft_create'")
        .getSingle();
    expect(jsonDecode(draft.read<String>('payload_json'))['local_job_number'], 'J-45');
  });

  test('previously attempted or missing creation is not renumbered', () async {
    await db.customStatement("UPDATE sync_outbox SET attempt_count=1 "
        "WHERE entity_type='document_draft_create'");
    await expectLater(assign(), throwsStateError);
    await db.customStatement("DELETE FROM sync_outbox WHERE entity_type='document_draft_create'");
    await expectLater(assign(), throwsStateError);
    expect((await row('local_jobs'))['job_number'], 'J-45');
  });

  test('accepts J34, J-34 and 34; rejects invalid numbers', () {
    for (final value in ['J34', 'j-34', '34', '  J-34 ']) {
      expect(LocalJobNumberService.parse(value), 34);
    }
    for (final value in ['', '0', '-1', 'J--34', '3.4', '1000000000']) {
      expect(() => LocalJobNumberService.parse(value), throwsStateError);
    }
  });
}
