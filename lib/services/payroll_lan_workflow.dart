import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_payroll_repository.dart';
import 'payroll_lan_delivery.dart';
import 'payroll_lan_identity.dart';
import 'payroll_lan_peer.dart';
import 'payroll_owner_lease.dart';

/// A single signed link between the payment device and one mechanic.
class PayrollLanWorkflow {
  PayrollLanWorkflow({
    required BriskersLocalDatabase database,
    required PayrollLanIdentity identity,
    required this.peer,
    required void Function() assertLink,
    void Function()? assertOwner,
    Future<void> Function()? assertWriter,
    PayrollOwnerProof? ownerProof,
    Future<void> Function(Map<String, dynamic>)? onOwnerCertificate,
  }) : _database = database, isOwner = identity.deviceId == peer.ownerDevice {
    if (isOwner && (assertOwner == null || assertWriter == null)) {
      throw ArgumentError('Owner payroll authorization is required.');
    }
    repository = LocalPayrollRepository(
      database, business: peer.business, owner: isOwner,
      deviceId: identity.deviceId, assertOwnerGrant: assertOwner,
      assertLanWriter: assertWriter, ownerProof: ownerProof, pairedEmployee: isOwner ? null : peer.employee,
    );
    delivery = PayrollLanDelivery(
      database: database, identity: identity, peer: peer,
      assertEnrollment: assertLink,
      onOwnerCertificate: onOwnerCertificate,
      onAcknowledged: (kind, id) async {
        if (!isOwner || kind != PayrollLanOperation.payment) return;
        await database.customStatement(
          "UPDATE regular_payroll_sync_outbox SET state='reconciled' "
          'WHERE business_id=? AND operation_id=?',
          [peer.business, id],
        );
      },
      apply: (kind, payload) => repository.applyLanChange(
        kind, payload, employee: peer.employee, assertLink: assertLink,
      ),
    );
    _assertLink = assertLink;
  }

  final BriskersLocalDatabase _database;
  final PayrollLanPeer peer;
  final bool isOwner;
  late final LocalPayrollRepository repository;
  late final PayrollLanDelivery delivery;
  late final void Function() _assertLink;

  Future<List<Map<String, dynamic>>> mechanicWork(String? job) =>
      repository.mechanicWork(
        job: job, employee: peer.employee, assertSession: _assertLink,
      );

  Future<({int unpaid, List<Map<String, dynamic>> receipts})> mechanicReport() =>
      repository.mechanicReport(peer.employee, _assertLink);

  Future<int> listen(InternetAddress address, {int port = 0}) async {
    await repository.prepare();
    await synchronizeAssignments();
    return delivery.listen(address, port: port);
  }

  Future<String> _operationId(List<Object> fields) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(jsonEncode(fields)))).bytes);

  Future<void> assign({
    required String job,
    required String invoice,
    required String line,
    required String description,
    required String employeeName,
    required int rate,
  }) async {
    await delivery.prepare();
    await repository.registerAssignedLabor(
      jobId: job, invoiceId: invoice, lineId: line, employeeId: peer.employee,
      employeeName: employeeName, rateCents: rate,
      queueChange: synchronizeAssignments,
    );
  }

  /// Persist changed assignment snapshots before opening the shop LAN session.
  /// A separate sequence per credit prevents stale packets from reverting edits.
  Future<void> synchronizeAssignments() async {
    if (!isOwner) return;
    await delivery.prepare();
    await repository.prepare();
    await _database.customStatement(
      'CREATE TABLE IF NOT EXISTS regular_payroll_assignment_outgoing '
      '(business_id TEXT NOT NULL,peer TEXT NOT NULL,credit TEXT NOT NULL,'
      'revision INTEGER NOT NULL,body TEXT NOT NULL,'
      'PRIMARY KEY(business_id,peer,credit))');
    for (final payload in await repository.assignmentSnapshots(peer.employee)) {
      await _database.transaction(() async {
        final credit = payload['credit'] as String;
        final rows = await _database.customSelect(
          'SELECT revision,body FROM regular_payroll_assignment_outgoing '
          'WHERE business_id=? AND peer=? AND credit=?',
          variables: [peer.business, peer.mechanicDevice, credit]
            .map(Variable<String>.new).toList(),
        ).get();
        final body = jsonEncode(payload);
        if (rows.isNotEmpty && rows.single.data['body'] == body) return;
        final revision = rows.isEmpty ? 1 : (rows.single.data['revision'] as int) + 1;
        await delivery.enqueue(
          operationId: await _operationId(['assignment', credit, revision]),
          kind: PayrollLanOperation.assignment,
          payload: {...payload, 'assignment_revision': revision},
        );
        await _database.customStatement(
          'INSERT INTO regular_payroll_assignment_outgoing VALUES(?,?,?,?,?) '
          'ON CONFLICT(business_id,peer,credit) DO UPDATE SET '
          'revision=excluded.revision,body=excluded.body',
          [peer.business, peer.mechanicDevice, credit, revision, body],
        );
      });
    }
  }

  Future<void> assignRecheck({
    required String operation, required String job, required String description,
    required String employeeName, required int rate, required int estimatedMinutes,
  }) async {
    if (!isOwner) throw StateError('Only the Owner assigns rechecks.');
    await delivery.prepare();
    await repository.createRecheck(
      operation: operation, job: job, description: description,
      employee: peer.employee, name: employeeName, rate: rate,
      estimatedMinutes: estimatedMinutes,
      queueChange: () => delivery.enqueue(
        operationId: operation, kind: PayrollLanOperation.assignment,
        payload: {
          'kind': 'recheck', 'operation': operation, 'job': job,
          'description': description, 'employee': peer.employee, 'rate': rate,
          'estimated_minutes': estimatedMinutes,
        },
      ),
    );
  }

  Future<void> progress({
    required String job,
    required String id,
    required String state,
    required int minutes,
    required String date,
    required int revision,
  }) async {
    if (isOwner) throw StateError('Only this mechanic can send their progress.');
    await delivery.prepare();
    final operation = await _operationId(['progress', id, revision]);
    await repository.updateMechanicWork(
      job: job, employee: peer.employee, id: id, state: state,
      minutes: minutes, date: date, expectedRevision: revision,
      assertSession: _assertLink,
      queueChange: () => delivery.enqueue(
        operationId: operation,
        kind: PayrollLanOperation.progress,
        payload: {'job': job, 'id': id, 'employee': peer.employee,
          'state': state, 'minutes': minutes, 'date': date, 'revision': revision},
      ),
    );
  }

  /// A trusted Owner relay can forward already recorded receipts after a
  /// portable-ledger reconciliation; it cannot invent or finalize payments.
  Future<void> queueRecordedPayments() async {
    if (!isOwner) throw StateError('Only an Owner can forward payment receipts.');
    await delivery.prepare();
    for (final payment in await repository.history(peer.employee)) {
      final operation = payment['operation_id'] as String;
      final coverage = await repository.recordedCoverage(peer.employee, operation);
      await delivery.enqueue(operationId: operation, kind: PayrollLanOperation.payment,
        payload: {'operation': operation, 'employee': peer.employee,
          'week': payment['week'], 'date': payment['verified_date'],
          'method': payment['method'], 'gross': payment['gross'],
          'repayment': payment['repayment'], 'net': payment['net'],
          'work': coverage.map((row) => row['credit_id'] as String).toList(),
          'coverage': coverage});
    }
  }

  Future<bool> pay({
    required String operation,
    required String week,
    required String date,
    required String method,
    required List<Map<String, dynamic>> selected,
    required int net,
    required String reason,
    int base = 0,
    int adjustment = 0,
    int repayment = 0,
    Future<void> Function()? onRecorded,
  }) async {
    if (!isOwner) throw StateError('Only the Owner can record payment.');
    await delivery.prepare();
    return repository.verify(
      operation: operation, employee: peer.employee, week: week, date: date,
      method: method, selected: selected, base: base, hourlyAdjustment: adjustment,
      adjustmentReason: reason, repayment: repayment, confirmedNet: net,
      beforeCommit: () async {
        await delivery.enqueue(
        operationId: operation, kind: PayrollLanOperation.payment,
        payload: {'operation': operation, 'employee': peer.employee, 'week': week,
          'date': date, 'method': method, 'gross': net + repayment, 'repayment': repayment, 'net': net,
          'work': selected.map((row) => row['id'] as String).toList(),
          'coverage': await repository.recordedCoverage(peer.employee, operation)},
        );
        await onRecorded?.call();
      },
    );
  }
}
