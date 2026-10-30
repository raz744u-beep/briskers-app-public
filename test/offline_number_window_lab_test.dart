import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/offline_number_window_lab.dart';

OfflineNumberWindowLab twoDevices() => OfflineNumberWindowLab(
  masterDeviceId: 'master',
  deviceIds: ['master', 'slave'],
  firstNumber: 6401,
);

void main() {
  test('Master 6401 and Slave 6411 compress into 6401 and 6402', () {
    final lab = twoDevices();
    expect(lab.windowSize, 10);
    expect(lab.leases['master']!.start, 6401);
    expect(lab.leases['master']!.end, 6410);
    expect(lab.leases['slave']!.start, 6411);
    expect(lab.leases['slave']!.end, 6420);

    final master = lab.create(
      deviceId: 'master', documentId: 'invoice-master',
      operationId: 'op-master', createdOrder: 1,
    );
    final slave = lab.create(
      deviceId: 'slave', documentId: 'invoice-slave',
      operationId: 'op-slave', createdOrder: 2,
    );
    expect(master.provisionalNumber, 6401);
    expect(slave.provisionalNumber, 6411);
    expect(slave.visibleReference, 'Provisional #6411');

    final sync = lab.synchronize(
      batchId: 'batch-1', acknowledgedDevices: {'master', 'slave'},
    );
    expect(sync.assignments.map((x) => x.finalNumber), [6401, 6402]);
    expect(sync.assignments.last.provisionalNumber, 6411);
    expect(sync.assignments.last.numberChanged, isTrue);
    expect(lab.claims['invoice-slave']!.visibleReference, 'Invoice #6402');
    expect(sync.newLeases['master']!.start, 6403);
    expect(sync.newLeases['master']!.end, 6412);
    expect(sync.newLeases['slave']!.start, 6413);
    expect(sync.newLeases['slave']!.end, 6422);
    expect(sync.nextFinalNumber, 6403);
  });

  test('Master priority protects its sequence even when Slave created earlier', () {
    final lab = twoDevices();
    lab.create(deviceId: 'slave', documentId: 's1',
      operationId: 'os1', createdOrder: 1);
    lab.create(deviceId: 'master', documentId: 'm1',
      operationId: 'om1', createdOrder: 2);
    lab.create(deviceId: 'master', documentId: 'm2',
      operationId: 'om2', createdOrder: 3);
    final sync = lab.synchronize(
      batchId: 'b1', acknowledgedDevices: {'master', 'slave'},
    );
    expect(sync.assignments.map((a) => a.documentId), ['m1', 'm2', 's1']);
    expect(sync.assignments.map((a) => a.finalNumber), [6401, 6402, 6403]);
    expect(sync.newLeases['master']!.start, 6404);
    expect(sync.newLeases['slave']!.start, 6414);
  });

  test('A number window is refilled with 10 numbers after each synchronized batch', () {
    final lab = twoDevices();
    lab.create(deviceId: 'master', documentId: 'm1',
      operationId: 'om1', createdOrder: 1);
    lab.create(deviceId: 'slave', documentId: 's1',
      operationId: 'os1', createdOrder: 2);
    lab.synchronize(batchId: 'b1',
      acknowledgedDevices: {'master', 'slave'});
    final later = lab.create(deviceId: 'slave', documentId: 's2',
      operationId: 'os2', createdOrder: 3);
    expect(later.provisionalNumber, 6413);
    final second = lab.synchronize(batchId: 'b2',
      acknowledgedDevices: {'master', 'slave'});
    expect(second.assignments.single.finalNumber, 6403);
    expect(second.newLeases['master']!.start, 6404);
    expect(second.newLeases['slave']!.start, 6414);
  });

  test('Disconnected device cannot be silently stripped of unused numbers', () {
    final lab = twoDevices();
    lab.create(deviceId: 'master', documentId: 'm1',
      operationId: 'op1', createdOrder: 1);
    expect(
      () => lab.synchronize(batchId: 'b1',
        acknowledgedDevices: {'master'}),
      throwsStateError,
    );
    expect(lab.epoch, 1);
    expect(lab.leases['slave']!.start, 6411);
    expect(lab.claims['m1']!.finalNumber, isNull);
  });

  test('Provisional already shared externally is never silently renumbered', () {
    final lab = twoDevices();
    lab.create(deviceId: 'master', documentId: 'm1',
      operationId: 'op1', createdOrder: 1);
    lab.create(deviceId: 'slave', documentId: 's1',
      operationId: 'op2', createdOrder: 2,
      externallyShared: true);
    expect(
      () => lab.synchronize(batchId: 'b1',
        acknowledgedDevices: {'master', 'slave'}),
      throwsStateError,
    );
    expect(lab.claims['m1']!.finalNumber, isNull);
    expect(lab.claims['s1']!.finalNumber, isNull);
    expect(lab.epoch, 1);
  });

  test('Exhausted 10-number block still allows a safe local reference', () {
    final lab = twoDevices();
    final slots = <int?>[];
    for (var i = 0; i < 11; i++) {
      slots.add(lab.create(deviceId: 'slave',
        documentId: 's$i', operationId: 'os$i',
        createdOrder: i).provisionalNumber);
    }
    expect(slots.take(10), orderedEquals(
      List.generate(10, (i) => 6411 + i)));
    expect(slots.last, isNull);
    expect(lab.claims['s10']!.visibleReference, 'Local invoice s10');
    final sync = lab.synchronize(batchId: 'b1',
      acknowledgedDevices: {'master', 'slave'});
    expect(sync.assignments.map((a) => a.finalNumber),
      orderedEquals(List.generate(11, (i) => 6401 + i)));
  });

  test('Repeated operation does not use a second number; altered identity rejected', () {
    final lab = twoDevices();
    final original = lab.create(deviceId: 'slave',
      documentId: 'invoice-id', operationId: 'operation-id',
      createdOrder: 1);
    final retry = lab.create(deviceId: 'slave',
      documentId: 'invoice-id', operationId: 'operation-id',
      createdOrder: 1);
    expect(identical(original, retry), isTrue);
    expect(lab.leases['slave']!.consumed, {6411});
    expect(() => lab.create(deviceId: 'slave', documentId: 'different',
      operationId: 'operation-id', createdOrder: 2), throwsStateError);
  });

  test('Duplicate synchronization ID returns unchanged result and leases', () {
    final lab = twoDevices();
    lab.create(deviceId: 'master', documentId: 'm1',
      operationId: 'op1', createdOrder: 1);
    final first = lab.synchronize(batchId: 'b1',
      acknowledgedDevices: {'master', 'slave'});
    final retry = lab.synchronize(batchId: 'b1',
      acknowledgedDevices: {'master', 'slave'});
    expect(identical(first, retry), isTrue);
    expect(lab.epoch, 2);
    expect(lab.nextFinalNumber, 6402);
  });

  test('Cannot allocate for unknown device or reuse a document ID', () {
    final lab = twoDevices();
    expect(() => lab.create(deviceId: 'rogue', documentId: 'id1',
      operationId: 'op1', createdOrder: 1), throwsStateError);
    lab.create(deviceId: 'master', documentId: 'id1',
      operationId: 'op1', createdOrder: 2);
    expect(() => lab.create(deviceId: 'master', documentId: 'id1',
      operationId: 'op2', createdOrder: 3), throwsStateError);
  });
}
