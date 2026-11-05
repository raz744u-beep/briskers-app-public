import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../local/briskers_local_database.dart';
import 'local_payroll_repository.dart';
import 'payroll_lan_delivery.dart';
import 'payroll_lan_identity.dart';
import 'payroll_lan_peer.dart';

/// A single signed link between the payment device and one mechanic.
class PayrollLanWorkflow {
  PayrollLanWorkflow({
    required BriskersLocalDatabase database,
    required PayrollLanIdentity identity,
    required this.peer,
    required void Function() assertLink,
    void Function()? assertOwner,
    Future<void> Function()? assertWriter,
  }) : isOwner = identity.deviceId == peer.ownerDevice {
    if (isOwner && (assertOwner == null || assertWriter == null)) {
      throw ArgumentError('Owner payroll authorization is required.');
    }
    repository = LocalPayrollRepository(
      database, business: peer.business, owner: isOwner,
      deviceId: identity.deviceId, assertOwnerGrant: assertOwner,
      assertLanWriter: assertWriter, pairedEmployee: isOwner ? null : peer.employee,
    );
    delivery = PayrollLanDelivery(
      database: database, identity: identity, peer: peer,
      assertEnrollment: assertLink,
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
    final operation = await _operationId(['assign', job, invoice, line]);
    await repository.registerAssignedLabor(
      jobId: job, invoiceId: invoice, lineId: line, employeeId: peer.employee,
      employeeName: employeeName, rateCents: rate,
      queueChange: () => delivery.enqueue(
        operationId: operation,
        kind: PayrollLanOperation.assignment,
        payload: {'job': job, 'invoice': invoice, 'line': line,
          'employee': peer.employee, 'description': description, 'rate': rate},
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
  }) async {
    if (!isOwner) throw StateError('Only the Owner can record payment.');
    await delivery.prepare();
    return repository.verify(
      operation: operation, employee: peer.employee, week: week, date: date,
      method: method, selected: selected, base: base, hourlyAdjustment: adjustment,
      adjustmentReason: reason, repayment: repayment, confirmedNet: net,
      beforeCommit: () => delivery.enqueue(
        operationId: operation, kind: PayrollLanOperation.payment,
        payload: {'operation': operation, 'employee': peer.employee, 'week': week,
          'date': date, 'method': method, 'gross': net + repayment, 'repayment': repayment, 'net': net,
          'work': selected.map((row) => row['id'] as String).toList()},
      ),
    );
  }
}
