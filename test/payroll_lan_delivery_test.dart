import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/payroll_lan_delivery.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_lan_peer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LAN delivery survives receiver commit, lost ack and both restarts',
      () async {
    final dir = await Directory.systemTemp.createTemp('payroll_lan_test');
    addTearDown(() => dir.delete(recursive: true));
    BriskersLocalDatabase open(String file) =>
        BriskersLocalDatabase(NativeDatabase(File('${dir.path}/$file')));
    final owner = await PayrollLanIdentity.fromSeed(List.filled(32, 1));
    final mechanic = await PayrollLanIdentity.fromSeed(List.filled(32, 2));
    final peer = PayrollLanPeer(
      business: 'shop',
      ownerDevice: owner.deviceId,
      mechanicDevice: mechanic.deviceId,
      employee: 'mechanic-a',
      pairKey: List.filled(32, 3),
    );
    var senderDb = open('owner.sqlite');
    var receiverDb = open('mechanic.sqlite');
    addTearDown(() async {
      await senderDb.close();
      await receiverDb.close();
    });
    await receiverDb.customStatement('CREATE TABLE applied(employee TEXT)');
    PayrollLanDelivery sender() => PayrollLanDelivery(
      database: senderDb,
      identity: owner,
      peer: peer,
      assertEnrollment: () {},
      apply: (_, _) async => throw StateError('Unexpected delivery'),
    );
    PayrollLanDelivery receiver() => PayrollLanDelivery(
      database: receiverDb,
      identity: mechanic,
      peer: peer,
      assertEnrollment: () {},
      apply: (kind, payload) async {
        expect(kind, PayrollLanOperation.payment);
        await receiverDb.customStatement(
          'INSERT INTO applied VALUES(?)',
          [payload['employee']],
        );
      },
    );
    final address = InternetAddress.loopbackIPv4;
    const operation = 'receipt-1';
    await sender().enqueue(
      operationId: operation,
      kind: PayrollLanOperation.payment,
      payload: {'employee': 'mechanic-a', 'net': 10529},
    );
    await expectLater(
      sender().enqueue(
        operationId: operation,
        kind: PayrollLanOperation.payment,
        payload: {'employee': 'mechanic-b', 'net': 10529},
      ),
      throwsStateError,
    );
    final first = receiver();
    final firstPort = await first.listen(address);
    final proxy = await HttpServer.bind(address, 0);
    final forwarder = HttpClient();
    try {
      proxy.listen((incoming) async {
        final outgoing = await forwarder.postUrl(Uri(
          scheme: 'http',
          host: address.address,
          port: firstPort,
          path: incoming.uri.path,
        ));
        await outgoing.addStream(incoming);
        final reply = await outgoing.close();
        await reply.drain<void>();
        incoming.response.statusCode = HttpStatus.serviceUnavailable;
        await incoming.response.close();
      });
      await expectLater(sender().deliver(address, proxy.port), throwsStateError);
      expect(await receiverDb.customSelect('SELECT * FROM applied').get(),
          hasLength(1));
    } finally {
      forwarder.close(force: true);
      await proxy.close(force: true);
      await first.close();
    }
    await senderDb.close();
    await receiverDb.close();
    senderDb = open('owner.sqlite');
    receiverDb = open('mechanic.sqlite');
    final restarted = receiver();
    final port = await restarted.listen(address);
    try {
      expect(await sender().deliver(address, port), 1);
      expect(await sender().deliver(address, port), 0);
      expect(await receiverDb.customSelect('SELECT * FROM applied').get(),
          hasLength(1));
    } finally {
      await restarted.close();
    }
  });
}
