import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_lan_peer.dart';
import 'package:briskers_app/services/payroll_lan_workflow.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final paidMinutes in [30, 60, 180]) {
  final creditedMinutes=paidMinutes==180?180:60;
  test('separate LAN ledgers preserve one $paidMinutes minute payment after lost reply and restart',
      () async {
    // The widget binding normally mocks HTTP. This test uses real loopback.
    final previousOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverride);
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('payroll-workflow');
    final databases = <BriskersLocalDatabase>[];
    final links = <PayrollLanWorkflow>[];
    addTearDown(() async {
      for (final link in links) {
        await link.delivery.close();
      }
      for (final database in databases) {
        await database.close();
      }
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
      await directory.delete(recursive: true);
    });
    BriskersLocalDatabase open(String device) {
      final db = BriskersLocalDatabase(
        NativeDatabase(File('${directory.path}/$device.sqlite')),
      );
      databases.add(db);
      return db;
    }

    var owner = open('owner');
    var mechanics = [open('a'), open('b')];
    const employees = ['a', 'b'];
    final identities = await Future.wait([
      for (var i = 1; i <= 3; i++)
        PayrollLanIdentity.fromSeed(List.filled(32, i)),
    ]);
    final peers = [
      for (var i = 0; i < 2; i++)
        PayrollLanPeer(
          business: 'shop', employee: employees[i],
          ownerDevice: identities[0].deviceId,
          mechanicDevice: identities[i + 1].deviceId,
          pairKey: List.filled(32, i + 10),
        ),
    ];
    void authorize() {}
    PayrollLanWorkflow link(int i, {required bool fromOwner}) {
      final result = PayrollLanWorkflow(
        database: fromOwner ? owner : mechanics[i],
        identity: identities[fromOwner ? 0 : i + 1],
        peer: peers[i], assertLink: authorize,
        assertOwner: fromOwner ? authorize : null,
        assertWriter: fromOwner ? () async {} : null,
      );
      links.add(result);
      return result;
    }

    await LocalDocumentDetailCache.initialize(owner);
    await owner.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status) "
      "VALUES('job','shop','owner','Repair','open')",
    );
    await owner.customStatement(
      "INSERT INTO local_documents(document_date,id,business_id,job_id,kind) "
      "VALUES('2026-11-07','invoice','shop','job','invoice')",
    );
    for (final employee in employees) {
      await owner.customStatement(
        "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id) "
        "VALUES(?,'shop','job',?)",
        [employee, employee],
      );
    }
    await LocalDocumentDetailCache(database: owner).save('shop', 'invoice', {
      'id': 'invoice', 'kind': 'invoice', 'job_id': 'job',
      'lines': [
        {'id': 'labor', 'line_kind': 'labor', 'description': 'Repair'},
      ],
    });
    var ownerLinks = [for (var i = 0; i < 2; i++) link(i, fromOwner: true)];
    var mechanicLinks = [for (var i = 0; i < 2; i++) link(i, fromOwner: false)];
    await ownerLinks[0].repository.bindPaymentAuthority(
      writerDeviceId: identities[0].deviceId, assertVerifiedPairing: authorize,
    );
    final loopback = InternetAddress.loopbackIPv4;
    for (var i = 0; i < 2; i++) {
      await ownerLinks[i].assign(
        job: 'job', invoice: 'invoice', line: 'labor', description: 'Repair',
        employeeName: employees[i], rate: 4000,
      );
      final port = await mechanicLinks[i].listen(loopback);
      expect(await ownerLinks[i].delivery.deliver(loopback, port), 1);
      await mechanicLinks[i].delivery.close();
      if (i == 0) {
        await LocalDocumentDetailCache(database: owner).save('shop', 'invoice', {
          'id': 'invoice', 'kind': 'invoice', 'job_id': 'job',
          'lines': [
            {'id': 'labor', 'line_kind': 'labor', 'quantity': 2,
              'description': 'Revised repair'},
          ],
        });
        await ownerLinks[i].synchronizeAssignments();
        await ownerLinks[i].synchronizeAssignments(); // unchanged snapshot is not requeued
        final revisedPort = await mechanicLinks[i].listen(loopback);
        expect(await ownerLinks[i].delivery.deliver(loopback, revisedPort), 1);
        await mechanicLinks[i].delivery.close();
        final revised = await mechanicLinks[i].mechanicWork('job');
        expect(revised.single['description'], 'Revised repair');
        expect(revised.single['actual_minutes'], 0);
        await mechanicLinks[i].repository.applyLanChange(
          PayrollLanOperation.assignment,
          {'job': 'job', 'invoice': 'invoice', 'line': 'labor',
            'description': 'Stale repair', 'employee': 'a', 'rate': 4000,
            'assignment_revision': 1},
          employee: 'a', assertLink: authorize,
        );
        expect((await mechanicLinks[i].mechanicWork('job')).single['description'],
          'Revised repair');

      }
      for (final state in ['In Progress', 'Done']) {
        final work = (await mechanicLinks[i].repository.mechanicWork(
          job: 'job', employee: employees[i], assertSession: authorize,
        )).single;
        await mechanicLinks[i].progress(
          job: 'job', id: work['id'] as String, state: state, minutes: 60,
          date: '2026-11-04', revision: work['revision'] as int,
        );
      }
    }
    final ledger = ownerLinks[0].repository;
    expect((await ledger.work()).map((row) => row['state']), everyElement('Open'));
    for (var i = 0; i < 2; i++) {
      final port = await ownerLinks[i].listen(loopback);
      expect(await mechanicLinks[i].delivery.deliver(loopback, port), 2);
      await ownerLinks[i].delivery.close();
    }
    expect((await ledger.work()).map((row) => row['state']), everyElement('Done'));
    if(creditedMinutes!=60){
      final first=(await ledger.work(employee:'a')).single;
      await ledger.recordAllocatedTime(first['id'] as String,'Done',60,creditedMinutes,'2026-11-04');
    }
    await expectLater(mechanicLinks[0].repository.mechanicReport('b', authorize),
        throwsStateError);
    await expectLater(mechanicLinks[0].pay(
      operation: 'forbidden', week: '2026-11-02', date: '2026-11-04',
      method: 'Cash', selected: [], net: 0, reason: '',
    ), throwsStateError);
    final wrongDevice = LocalPayrollRepository(
      owner, business: 'shop', owner: true, deviceId: identities[1].deviceId,
    );
    await expectLater(wrongDevice.verify(
      operation: 'unauthorized', employee: 'a', week: '2026-11-02',
      date: '2026-11-04', method: 'Cash', selected: await ledger.work(employee: 'a'),
      base: 0, hourlyAdjustment: 0, adjustmentReason: '', repayment: 0,
      confirmedNet: 4000,
    ), throwsStateError);
    expect(await ownerLinks[0].pay(
      operation: 'receipt-a', week: '2026-11-02', date: '2026-11-04',
      method: 'Cash', selected: [
        for (final row in await ledger.work(employee: 'a')) {...row, 'pay_minutes': paidMinutes},
      ],
      net: paidMinutes * 4000 ~/ 60, reason: '',
    ), isTrue);
    expect((await owner.customSelect("SELECT status FROM local_jobs WHERE id='job'")
        .getSingle()).data['status'], 'open');

    final port = await mechanicLinks[0].listen(loopback);
    final relay = await HttpServer.bind(loopback, 0);
    final client = HttpClient();
    try {
      relay.listen((incoming) async {
        final request = await client.postUrl(Uri(
          scheme: 'http', host: loopback.address, port: port,
          path: incoming.uri.path,
        ));
        await request.addStream(incoming);
        await (await request.close()).drain<void>();
        incoming.response.statusCode = HttpStatus.serviceUnavailable;
        await incoming.response.close();
      });
      await expectLater(ownerLinks[0].delivery.deliver(loopback, relay.port),
          throwsStateError);
    } finally {
      client.close(force: true);
      await relay.close(force: true);
      await mechanicLinks[0].delivery.close();
    }

    for (final db in databases) {
      await db.close();
    }
    databases.clear();
    owner = open('owner');
    mechanics = [open('a'), open('b')];
    ownerLinks = [for (var i = 0; i < 2; i++) link(i, fromOwner: true)];
    mechanicLinks = [for (var i = 0; i < 2; i++) link(i, fromOwner: false)];
    final retryPort = await mechanicLinks[0].listen(loopback);
    expect(await ownerLinks[0].delivery.deliver(loopback, retryPort), 1);
    expect(await ownerLinks[0].delivery.deliver(loopback, retryPort), 0);
    final ownerHistory = await ownerLinks[0].repository.history('a');
    expect(ownerHistory, hasLength(1));
    expect(ownerHistory.single['reconciliation_state'], 'reconciled');
    await expectLater(ownerLinks[0].pay(
      operation: 'duplicate-receipt', week: '2026-11-02', date: '2026-11-04',
      method: 'Cash', selected: await ownerLinks[0].repository.work(employee: 'a'),
      net: 4000, reason: '',
    ), throwsStateError);
    expect(await ownerLinks[1].repository.history('b'), isEmpty);
    final first = await mechanicLinks[0].repository.mechanicReport('a', authorize);
    final second = await mechanicLinks[1].repository.mechanicReport('b', authorize);
    expect(first.receipts.single['net'], paidMinutes * 4000 ~/ 60);
    final actual=(await mechanics[0].customSelect("SELECT minutes FROM regular_payroll_actual_time WHERE business_id='shop'").getSingle()).data['minutes'];
    expect(actual,60);
    expect(first.unpaid, (creditedMinutes - paidMinutes) * 4000 ~/ 60);
    final ownerBalance = (await ownerLinks[0].repository.work(employee: 'a')).single;
    expect(ownerBalance['remaining_cents'], first.unpaid);
    expect(ownerBalance['paid'], paidMinutes == creditedMinutes ? 1 : 0);
    expect(second.receipts, isEmpty);
    expect(second.unpaid, 4000);
  });
  }
}
