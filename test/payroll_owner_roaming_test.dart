import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_lan_enrollment.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_ledger.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';

class _Unused implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}
class _PairStore implements PayrollEnrollmentStore {
  _PairStore(this.values);
  final Map<String, String> values;
  @override Future<String?> read({required String key}) async => values[key];
  @override Future<void> write({required String key, required String value}) async { values[key] = value; }
}
Future<LocalOwnerGrant> _owner(String session, {String business = 'shop'}) async {
  final identity = OwnerSessionIdentity('raz', session);
  final auth = LocalOwnerAuthorization(store: _Unused(), currentIdentity: () => identity,
    verifyOwner: (_) async => throw StateError('No internet'), authenticateDevice: () async => true,
    verifyLocalOwner: (shop) async => VerifiedOwnerEnrollment(identity, shop));
  return auth.authorizeLocal(business);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [(false, false, false, false), (true, false, false, false), (false, true, false, false), (false, false, true, false), (false, false, false, true)]) {
    final concurrent = scenario.$1;
    final lostReply = scenario.$2;
    var activationFailure = scenario.$3;
    var fenceFailure = scenario.$4;
    test('two authenticated Owners preserve one payment, concurrent=$concurrent lostReply=$lostReply activationFailure=${scenario.$3} fenceFailure=${scenario.$4}', () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final folder = await Directory.systemTemp.createTemp('owner-payroll');
      var a = BriskersLocalDatabase(NativeDatabase(File('${folder.path}/a.sqlite')));
      var b = BriskersLocalDatabase(NativeDatabase(File('${folder.path}/b.sqlite')));
      final identities = [await PayrollLanIdentity.fromSeed(List.filled(32, 1)),
        await PayrollLanIdentity.fromSeed(List.filled(32, 2))];
      final secure = [<String, String>{}, <String, String>{}];
      PayrollOwnerLease lease(int i) => PayrollOwnerLease(identity: identities[i],
        business: 'shop', anchor: identities[0].deviceId,
        read: (key) async => secure[i][key], write: (key, value) async {
          if (i == 1 && activationFailure && key == 'briskers_owner_payroll_lease_v2:shop') {
            final candidate = jsonDecode(value) as Map;
            if (candidate['status'] == 'active') {
              activationFailure = false;
              throw StateError('Interrupted secure activation after SQLite commit');
            }
          }
          if (i == 0 && fenceFailure && key == 'briskers_owner_payroll_lease_v2:shop:epoch' && value == '1') {
            fenceFailure = false;
            throw StateError('Interrupted sender fence after durable offering state');
          }
          secure[i][key] = value;
        });
      final ga = await _owner('android');
      final gb = await _owner('iphone');
      var la = lease(0), lb = lease(1);
      await la.migrate(ga);
      var dropReply = lostReply;
      var na = PayrollOwnerLan(lease: la, database: a, actor: 'raz', enrollment: PayrollLanEnrollment(identities[0], store: _PairStore(secure[0])), approve: (_) async => ga,
        onResponse: (command) async {
          if (command == 'take' && dropReply) { dropReply = false; throw StateError('Lost reply'); }
        });
      var nb = PayrollOwnerLan(lease: lb, database: b, actor: 'raz', enrollment: PayrollLanEnrollment(identities[1], store: _PairStore(secure[1])), approve: (_) async => gb);
      addTearDown(() async {
        await na.close(); await nb.close(); await a.close(); await b.close();
        LocalDocumentDetailCache.sqliteWritesEnabled = false;
        await folder.delete(recursive: true);
      });
      await LocalDocumentDetailCache.initialize(a);
      await a.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES('job','shop','owner','Shared repair','open')");
      await a.customStatement("INSERT INTO local_documents(document_date,id,business_id,job_id,kind) VALUES('2026-11-09','invoice','shop','job','invoice')");
      for (final employee in ['mechanic-a', 'mechanic-b']) {
        await a.customStatement('INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) VALUES(?,?,?,?,?)',
          [employee, 'shop', 'job', employee, employee]);
      }
      await LocalDocumentDetailCache(database: a).save('shop', 'invoice', {
        'id': 'invoice', 'kind': 'invoice', 'job_id': 'job', 'lines': [
          {'id': 'labor', 'line_kind': 'labor', 'name': 'Repair', 'quantity': 1},
        ],
      });
      final original = LocalPayrollRepository(a, business: 'shop', owner: true,
        deviceId: identities[0].deviceId, ownerProof: await la.proof(ga));
      for (final employee in ['mechanic-a', 'mechanic-b']) {
        await original.registerAssignedLabor(jobId: 'job', invoiceId: 'invoice', lineId: 'labor',
          employeeId: employee, employeeName: employee, rateCents: 4000);
        final work = (await original.work(employee: employee)).single;
        await original.updateWork(work['id'] as String, 'In Progress', 0, '2026-11-04');
        await original.updateWork(work['id'] as String, 'Done', 100, '2026-11-04');
      }
      final selected = await original.work(employee: 'mechanic-a');
      final scope = LocalPayrollRepository(a, business: 'shop', owner: false, deviceId: identities[0].deviceId, ownerProof: await la.proof(ga));
      await expectLater(scope.history('mechanic-a'), throwsStateError);
      await expectLater(nb.acquire(gb, 'unconnected'), throwsA(isA<PayrollPending>()));
      await na.listen(InternetAddress.loopbackIPv4, port: 0);
      await nb.listen(InternetAddress.loopbackIPv4, port: 0);
      await nb.connect('127.0.0.1:${na.port}', gb);
      Future<bool> pay(PayrollOwnerLan network, LocalOwnerGrant grant, String op,
          BriskersLocalDatabase db) async {
        final proof = await network.acquire(grant, op);
        final repo = LocalPayrollRepository(db, business: 'shop', owner: true,
          deviceId: network.lease.identity.deviceId, ownerProof: proof);
        return repo.verify(operation: op, employee: 'mechanic-a', week: '2026-11-02',
          date: '2026-11-04', method: 'Cash', selected: selected,
          base: 0, hourlyAdjustment: 0, adjustmentReason: '', repayment: 0, confirmedNet: 4000);
      }
      if (concurrent) {
        final results = await Future.wait([
          pay(na, ga, 'android-payment', a).then<Object>((v) => v).catchError((Object e) => e),
          pay(nb, gb, 'iphone-payment', b).then<Object>((v) => v).catchError((Object e) => e),
        ]);
        expect(results.where((r) => r == true), hasLength(1));
      } else {
        if (lostReply || scenario.$3 || scenario.$4) {
          await expectLater(pay(nb, gb, 'iphone-payment', b), throwsA(isA<PayrollPending>()));
          await expectLater(la.proof(ga), throwsA(isA<PayrollPending>()));
          final pa = na.port, pb = nb.port;
          await na.close(); await nb.close(); await a.close(); await b.close();
          a = BriskersLocalDatabase(NativeDatabase(File('${folder.path}/a.sqlite')));
          b = BriskersLocalDatabase(NativeDatabase(File('${folder.path}/b.sqlite')));
          la = lease(0); lb = lease(1);
          na = PayrollOwnerLan(lease: la, database: a, actor: 'raz', enrollment: PayrollLanEnrollment(identities[0], store: _PairStore(secure[0])), approve: (_) async => ga);
          nb = PayrollOwnerLan(lease: lb, database: b, actor: 'raz', enrollment: PayrollLanEnrollment(identities[1], store: _PairStore(secure[1])), approve: (_) async => gb);
          await na.listen(InternetAddress.loopbackIPv4, port: pa);
          await nb.listen(InternetAddress.loopbackIPv4, port: pb);
        }
        expect(await pay(nb, gb, 'iphone-payment', b), isTrue);
        expect(await pay(nb, gb, 'iphone-payment', b), isFalse);
        final originalTransfer = (await la.state())!['operation'] as String;
        // The authenticated Android Owner can take the ledger back, but cannot
        // pay an already covered credit under a different payment identity.
        await expectLater(pay(na, ga, 'duplicate-android', a), throwsA(anything));
        await expectLater(la.offer(operation: originalTransfer,
          recipient: Map<String, dynamic>.from((await lb.state())!['certificate'] as Map),
          export: na.ledger.export), throwsA(anything));
        await la.proof(ga);

      }
      if ((await la.state())?['status'] == 'active') {
        await nb.refresh(gb);
      } else {
        await na.refresh(ga);
      }
      final root = LocalPayrollRepository(a, business: 'shop', owner: true);
      final other = LocalPayrollRepository(b, business: 'shop', owner: true);
      expect(await root.history('mechanic-a'), hasLength(1));
      expect(await other.history('mechanic-a'), hasLength(1));
      expect((await root.work(employee: 'mechanic-b')).single['remaining_cents'], 4000);
      expect((await other.work(employee: 'mechanic-b')).single['remaining_cents'], 4000);
      expect((await a.customSelect("SELECT status FROM local_jobs WHERE id='job'").getSingle()).data['status'], 'open');
      // Restart both app databases and re-open the independent secure identities.
      final pa = na.port, pb = nb.port;
      await na.close(); await nb.close(); await a.close(); await b.close();
      a = BriskersLocalDatabase(NativeDatabase(File('${folder.path}/a.sqlite')));
      b = BriskersLocalDatabase(NativeDatabase(File('${folder.path}/b.sqlite')));
      la = lease(0); lb = lease(1);
      na = PayrollOwnerLan(lease: la, database: a, actor: 'raz', enrollment: PayrollLanEnrollment(identities[0], store: _PairStore(secure[0])), approve: (_) async => ga);
      nb = PayrollOwnerLan(lease: lb, database: b, actor: 'raz', enrollment: PayrollLanEnrollment(identities[1], store: _PairStore(secure[1])), approve: (_) async => gb);
      await na.listen(InternetAddress.loopbackIPv4, port: pa);
      await nb.listen(InternetAddress.loopbackIPv4, port: pb);
      await expectLater(pay(nb, gb, 'retry-after-restart', b), throwsA(anything));
      final finalRepo = LocalPayrollRepository(b, business: 'shop', owner: true);
      final copiedId = LocalPayrollRepository(b, business: 'shop', owner: true,
        deviceId: 'copied-public-id', assertLanWriter: () async {});
      await copiedId.bindPaymentAuthority(writerDeviceId: 'copied-public-id', assertVerifiedPairing: () {});
      await expectLater(copiedId.verify(operation: 'copied-database-attempt', employee: 'mechanic-b',
        week: '2026-11-02', date: '2026-11-04', method: 'Cash', selected: await finalRepo.work(employee: 'mechanic-b'),
        base: 0, hourlyAdjustment: 0, adjustmentReason: '', repayment: 0, confirmedNet: 4000),
        throwsA(isA<PayrollPending>()));

      expect(await finalRepo.history('mechanic-a'), hasLength(1));
      expect(await finalRepo.history('mechanic-b'), isEmpty);
      expect((await finalRepo.work(employee: 'mechanic-b')).single['remaining_cents'], 4000);
      // Copying certificates or database authority rows does not authorize an
      // unrelated installation, even when an Owner is properly logged in there.
      final stranger = await PayrollLanIdentity.fromSeed(List.filled(32, 9));
      final clone = PayrollOwnerLease(identity: stranger, business: 'shop', anchor: identities[0].deviceId,
        read: (key) async => secure[1][key], write: (_, _) async {});
      await expectLater(clone.proof(gb), throwsA(anything));
      await expectLater(lb.proof(await _owner('wrong-shop', business: 'other')), throwsStateError);
      expect(jsonDecode(await PayrollOwnerLedger(b, 'shop').export())['business'], 'shop');
    });
  }
}
