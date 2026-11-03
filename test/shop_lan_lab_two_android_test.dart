// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/lab/shop_lan_lab_store.dart';
import 'package:briskers_app/lab/shop_lan_lab_transport.dart';

const ownerId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const secondaryId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('briskers-lan-lab-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('synthetic note survives reopening its local journal', () async {
    final store = LanLabStore(Directory(root.path + '/owner'));
    final note = await LanLabNote.create(ownerId, 'test Brake Pad');
    expect(await store.save(note), isTrue);
    final restarted = LanLabStore(Directory(root.path + '/owner'));
    expect((await restarted.all()).single.text, 'test Brake Pad');
    expect(await restarted.save(note), isFalse);
    expect((await restarted.all()).length, 1);
  });

  test('manipulated note text is rejected by digest validation', () async {
    final note = await LanLabNote.create(ownerId, 'unchanged');
    final forged = note.toJson()..['text'] = 'tampered';
    expect(
      () => LanLabNote.fromJson(forged),
      throwsFormatException,
    );
  });

  test('distinct unacknowledged notes sync in both directions over LAN', () async {
    final key = newLanLabPairingKey();
    final ownerStore = LanLabStore(Directory(root.path + '/owner'));
    final secondaryStore = LanLabStore(Directory(root.path + '/secretary'));
    await ownerStore.save(await LanLabNote.create(ownerId, 'owner work'));
    await secondaryStore.save(
      await LanLabNote.create(secondaryId, 'secretary work'),
    );
    final owner = LanLabTransport(
      store: ownerStore, pairingKey: key, deviceId: ownerId,
    );
    final secretary = LanLabTransport(
      store: secondaryStore, pairingKey: key, deviceId: secondaryId,
    );
    await owner.start();
    addTearDown(owner.close);

    final peer = LanLabPairing(
      host: '127.0.0.1', port: owner.port!, key: key,
    );
    final result = await secretary.syncWith(peer);
    expect(result.sent, 1);
    expect(result.imported, 1);
    expect(result.totalLocal, 2);
    expect((await ownerStore.all()).length, 2);
    expect((await secondaryStore.all()).length, 2);

    // Simulate a lost earlier ACK by intentionally replaying the full batch.
    final retry = await secretary.syncWith(peer);
    expect(retry.imported, 0);
    expect((await ownerStore.all()).length, 2);
    expect((await secondaryStore.all()).length, 2);

    // Both devices retain the same two records even after store restart.
    expect((await LanLabStore(Directory(root.path + '/owner')).all()).length, 2);
    expect((await LanLabStore(Directory(root.path + '/secretary')).all()).length, 2);
  });

  test('another app occupying preferred port does not prevent LAN startup',
      () async {
    // Simulates the old TEST #15/#16 app still listening on this same phone.
    final blocker = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    addTearDown(() => blocker.close(force: true));

    final key = newLanLabPairingKey();
    final receiverStore = LanLabStore(Directory(root.path + '/receiver'));
    final senderStore = LanLabStore(Directory(root.path + '/sender'));
    await senderStore.save(
      await LanLabNote.create(secondaryId, 'port fallback survives'),
    );
    final receiver = LanLabTransport(
      store: receiverStore,
      pairingKey: key,
      deviceId: ownerId,
      preferredPort: blocker.port,
    );
    await receiver.start();
    addTearDown(receiver.close);

    expect(receiver.port, isNotNull);
    expect(receiver.port, isNot(blocker.port));
    final sender = LanLabTransport(
      store: senderStore, pairingKey: key, deviceId: secondaryId,
    );
    final pairing = LanLabPairing(
      host: '127.0.0.1', port: receiver.port!, key: key,
    );
    expect((await sender.syncWith(pairing)).totalLocal, 1);
    expect((await receiverStore.all()).single.text, 'port fallback survives');
    expect((await sender.syncWith(pairing)).imported, 0);
  });

  test('wrong shared key is rejected without sending any readable notes', () async {
    final good = newLanLabPairingKey();
    final bad = newLanLabPairingKey();
    final ownerStore = LanLabStore(Directory(root.path + '/owner'));
    final secondaryStore = LanLabStore(Directory(root.path + '/secondary'));
    await secondaryStore.save(
      await LanLabNote.create(secondaryId, 'do not leak'),
    );
    final owner = LanLabTransport(
      store: ownerStore, pairingKey: good, deviceId: ownerId,
    );
    await owner.start();
    addTearDown(owner.close);
    final sender = LanLabTransport(
      store: secondaryStore, pairingKey: bad, deviceId: secondaryId,
    );
    await expectLater(
      sender.syncWith(LanLabPairing(
        host: '127.0.0.1', port: owner.port!, key: bad,
      )),
      throwsStateError,
    );
    expect(await ownerStore.all(), isEmpty);
    expect((await secondaryStore.all()).length, 1);
  });

  test('AES-GCM rejects altered ciphertext', () async {
    final cipher = LanLabCipher(newLanLabPairingKey());
    final sealed = await cipher.seal(
      {'operation': 'synthetic test'}, purpose: 'request',
    );
    final tampered = Map<String, dynamic>.from(sealed);
    final bytes = base64Url.decode(tampered['cipher'] as String);
    bytes[0] ^= 1;
    tampered['cipher'] = base64Url.encode(bytes);
    await expectLater(
      cipher.open(tampered, purpose: 'request'),
      throwsA(anything),
    );
  });

  test('pairing QR has strict format and does not accept public IPs', () {
    final key = newLanLabPairingKey();
    final good = LanLabPairing(
      host: '192.168.1.40', port: 45000, key: key,
    );
    final decoded = LanLabPairing.parse(jsonEncode(good.toJson()));
    expect(decoded.host, good.host);
    expect(decoded.key, key);
    expect(
      () => LanLabPairing.parse(jsonEncode({
        ...good.toJson(), 'host': '8.8.8.8',
      })),
      throwsFormatException,
    );
    expect(
      () => LanLabPairing.parse(jsonEncode({
        ...good.toJson(), 'key': '1234',
      })),
      throwsFormatException,
    );
  });

  test('untrusted operation IDs cannot choose arbitrary file paths', () async {
    final note = await LanLabNote.create(ownerId, 'safe note');
    final changed = note.toJson()..['id'] = '../../outside';
    expect(() => LanLabNote.fromJson(changed), throwsFormatException);
  });
}
