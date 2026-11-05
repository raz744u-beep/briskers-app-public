import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/payroll_lan_enrollment.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_lan_workflow.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';

class _Secure implements PayrollEnrollmentStore {
  final values = <String, String>{};
  @override Future<String?> read({required String key}) async => values[key];
  @override Future<void> write({required String key, required String value}) async { values[key] = value; }
}
class _Unused implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}
Future<LocalOwnerGrant> _unlock(String session) async {
  final who = OwnerSessionIdentity('owner', session);
  return LocalOwnerAuthorization(store: _Unused(), currentIdentity: () => who,
    authenticateDevice: () async => true,
    verifyOwner: (_) async => throw StateError('No internet'),
    verifyLocalOwner: (shop) async => VerifiedOwnerEnrollment(who, shop)).authorizeLocal('shop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mechanics work directly with another Owner; original phone offline; one receipt after restart', () async {
    final override = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('owner-mechanics');
    final dbs = <BriskersLocalDatabase>[];
    BriskersLocalDatabase open(int i) {
      final db = BriskersLocalDatabase(NativeDatabase(File('${directory.path}/$i.sqlite')));
      dbs.add(db); return db;
    }
    var databases = [for (var i = 0; i < 4; i++) open(i)];
    final ids = await Future.wait([for (var i = 1; i <= 4; i++) PayrollLanIdentity.fromSeed(List.filled(32, i))]);
    final stores = [for (var i = 0; i < 4; i++) _Secure()];
    final enroll = [for (var i = 0; i < 4; i++) PayrollLanEnrollment(ids[i], store: stores[i])];
    PayrollOwnerLease lease(int i) => PayrollOwnerLease(identity: ids[i], business: 'shop', anchor: ids[0].deviceId,
      read: (key) => stores[i].read(key: key), write: (key, value) => stores[i].write(key: key, value: value));
    final ga = await _unlock('android'), gb = await _unlock('iphone');
    final aLease = lease(0);
    var bLease = lease(1);
    await aLease.migrate(ga);
    final ownerA = PayrollOwnerLan(lease: aLease, database: databases[0], actor: 'owner',
      approve: (_) async => ga, enrollment: enroll[0]);
    var ownerB = PayrollOwnerLan(lease: bLease, database: databases[1], actor: 'owner',
      approve: (_) async => gb, enrollment: enroll[1]);
    final links = <PayrollLanWorkflow>[];
    addTearDown(() async {
      for (final link in links) { await link.delivery.close(); }
      await ownerA.close(); await ownerB.close();
      for (final db in dbs) { await db.close(); }
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
      HttpOverrides.global = override;
      await directory.delete(recursive: true);
    });
    void authorize() {}
    Future<PayrollLanWorkflow> worker(int i) async {
      final employee = i == 2 ? 'a' : 'b';
      final peer = (await enroll[i].mechanicPeer('shop', employee))!;
      final result = PayrollLanWorkflow(database: databases[i], identity: ids[i], peer: peer,
        assertLink: authorize, onOwnerCertificate: (certificate) => enroll[i].acceptOwnerRoute('shop', employee, certificate));
      links.add(result); return result;
    }
    await LocalDocumentDetailCache.initialize(databases[0]);
    await databases[0].customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES('job','shop','owner','Shared job','open')");
    await databases[0].customStatement("INSERT INTO local_documents(id,business_id,job_id,kind) VALUES('invoice','shop','job','invoice')");
    for (final employee in ['a', 'b']) {
      await databases[0].customStatement('INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id) VALUES(?,?,?,?)',
        [employee, 'shop', 'job', employee]);
    }
    await LocalDocumentDetailCache(database: databases[0]).save('shop', 'invoice', {
      'id': 'invoice', 'job_id': 'job', 'kind': 'invoice',
      'lines': [{'id': 'labor', 'line_kind': 'labor', 'description': 'Shared work', 'quantity': 1}],
    });
    final address = InternetAddress.loopbackIPv4;
    for (var i = 2; i < 4; i++) {
      final employee = i == 2 ? 'a' : 'b';
      final code = await enroll[0].invite(business: 'shop', employee: employee,
        mechanicDevice: ids[i].deviceId, grant: ga);
      await enroll[i].accept(code: code, business: 'shop', verifiedOwnerDevice: ids[0].deviceId, actor: employee);
      final root = PayrollLanWorkflow(database: databases[0], identity: ids[0], peer: (await enroll[0].ownerPeer('shop', employee))!,
        assertLink: authorize, assertOwner: authorize, assertWriter: () async {}, ownerProof: await aLease.proof(ga));
      links.add(root);
      await root.assign(job: 'job', invoice: 'invoice', line: 'labor', description: 'Shared work', employeeName: employee, rate: 4000);
      final mech = await worker(i);
      final port = await mech.listen(address);
      await root.delivery.deliver(address, port);
      await mech.delivery.close();
    }
    await ownerA.listen(address, port: 0); await ownerB.listen(address, port: 0);
    await ownerB.connect('127.0.0.1:${ownerA.port}', gb);
    final proof = await ownerB.acquire(gb, 'owner-b-start');
    await ownerA.close(); // No permanent original Owner phone dependency.
    final recipients = <PayrollLanWorkflow>[];
    for (var i = 2; i < 4; i++) {
      final employee = i == 2 ? 'a' : 'b';
      final peer = (await enroll[1].ownerPeer('shop', employee))!;
      expect(peer.ownerDevice, ids[1].deviceId);
      final receiving = PayrollLanWorkflow(database: databases[1], identity: ids[1], peer: peer,
        assertLink: authorize, assertOwner: authorize, assertWriter: () async {}, ownerProof: proof);
      links.add(receiving); recipients.add(receiving);
      // The trusted route announcement requires no new mechanic pairing code.
      final mech = await worker(i);
      final port = await mech.listen(address);
      await receiving.listen(address);
      await receiving.delivery.deliver(address, port);
      await mech.delivery.close(); await receiving.delivery.close();
      for (final state in ['In Progress', 'Done']) {
        final row = (await mech.mechanicWork('job')).single;
        await mech.progress(job: 'job', id: row['id'] as String, state: state, minutes: 60,
          date: '2026-11-04', revision: row['revision'] as int);
      }
      // This live object still has its old route; queued changes are accepted
      // by the approved Owner and acknowledged with that Owner's own key.
      final receiverPort = await receiving.listen(address);
      await mech.delivery.deliver(address, receiverPort);
      await receiving.delivery.close();
      expect((await enroll[i].mechanicPeer('shop', employee))!.ownerDevice, ids[1].deviceId);
    }
    final ledger = recipients[0].repository;
    expect((await ledger.work()).map((r) => r['state']), everyElement('Done'));
    expect(await recipients[0].pay(operation: 'pay-only-a', week: '2026-11-02', date: '2026-11-04',
      method: 'Cash', selected: await ledger.work(employee: 'a'), net: 4000, reason: ''), isTrue);
    final paidMechanic = await worker(2);
    final paidPort = await paidMechanic.listen(address);
    final relay = await HttpServer.bind(address, 0);
    final client = HttpClient();
    try {
      relay.listen((request) async {
        final upstream = await client.postUrl(Uri(scheme: 'http', host: address.address, port: paidPort, path: request.uri.path));
        request.headers.forEach((name, values) { if (name.startsWith('x-briskers-')) upstream.headers.set(name, values); });
        await upstream.addStream(request); await (await upstream.close()).drain<void>();
        request.response.statusCode = 503; await request.response.close();
      });
      await expectLater(recipients[0].delivery.deliver(address, relay.port), throwsStateError);
    } finally { await relay.close(force: true); client.close(force: true); await paidMechanic.delivery.close(); }
    for (final link in links) { await link.delivery.close(); }
    links.clear();
    await ownerB.close();
    for (final db in dbs) { await db.close(); }
    dbs.clear(); databases = [for (var i = 0; i < 4; i++) open(i)];
    bLease = lease(1);
    ownerB = PayrollOwnerLan(lease: bLease, database: databases[1], actor: 'owner', approve: (_) async => gb, enrollment: enroll[1]);
    final currentProof = await ownerB.acquire(gb, 'restart-proof');
    final current = PayrollLanWorkflow(database: databases[1], identity: ids[1], peer: (await enroll[1].ownerPeer('shop', 'a'))!,
      assertLink: authorize, assertOwner: authorize, assertWriter: () async {}, ownerProof: currentProof);
    links.add(current);
    final resumed = await worker(2);
    final resumedPort = await resumed.listen(address);
    expect(await current.delivery.deliver(address, resumedPort), 1);
    expect(await current.delivery.deliver(address, resumedPort), 0);
    final reportA = await resumed.mechanicReport();
    final reportB = await (await worker(3)).mechanicReport();
    expect(reportA.receipts, hasLength(1)); expect(reportA.unpaid, 0);
    expect(reportB.receipts, isEmpty); expect(reportB.unpaid, 4000);
    expect(await current.repository.history('a'), hasLength(1));
    await expectLater(resumed.repository.mechanicReport('b', authorize), throwsStateError);
    await expectLater(resumed.pay(operation: 'forbidden', week: '2026-11-02', date: '2026-11-04',
      method: 'Cash', selected: [], net: 0, reason: ''), throwsStateError);
    expect((await databases[1].customSelect("SELECT status FROM local_jobs WHERE id='job'").getSingle()).data['status'], 'open');
    final exported = await ownerB.ledger.export();
    expect(exported, isNot(contains('briskers-payroll-pair-v1')));
    expect(jsonDecode(exported)['business'], 'shop');
  });
}
