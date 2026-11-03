import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/lab/shop_lan_lab_auto_sync.dart';
import 'package:briskers_app/lab/shop_lan_lab_transport.dart';

void main() {
  final peer = LanLabPairing(
    host: '192.168.1.60',
    port: 48571,
    key: newLanLabPairingKey(),
  );

  test('no pairing does not start a network transfer', () async {
    var calls = 0;
    final events = <LanLabAutoSyncState>[];
    final sync = LanLabAutoSyncController(
      transfer: (_) async {
        calls++;
        return const LanLabSyncResult(sent: 0, imported: 0, totalLocal: 0);
      },
      onState: events.add,
      interval: const Duration(milliseconds: 15),
    );
    addTearDown(sync.dispose);
    sync.start(null);
    await Future<void>.delayed(const Duration(milliseconds: 55));
    expect(calls, 0);
    expect(events.last.phase, 'waiting');

    sync.setPeer(peer);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, greaterThanOrEqualTo(1));
    expect(events.any((event) => event.phase == 'connected'), isTrue);
  });

  test('automatically polls, pauses and catches up after resume', () async {
    var calls = 0;
    final sync = LanLabAutoSyncController(
      transfer: (_) async {
        calls++;
        return LanLabSyncResult(sent: calls, imported: 0, totalLocal: calls);
      },
      onState: (_) {},
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(sync.dispose);
    sync.start(peer);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, greaterThanOrEqualTo(2));
    sync.pause();
    final before = calls;
    await Future<void>.delayed(const Duration(milliseconds: 55));
    expect(calls, before);
    sync.resume();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(calls, greaterThan(before));
  });

  test('failed transfer retries and later reports success without losing state',
      () async {
    var calls = 0;
    final events = <LanLabAutoSyncState>[];
    final sync = LanLabAutoSyncController(
      transfer: (_) async {
        calls++;
        if (calls == 1) throw StateError('simulated Wi-Fi interruption');
        return const LanLabSyncResult(sent: 2, imported: 1, totalLocal: 3);
      },
      onState: events.add,
      interval: const Duration(milliseconds: 25),
      maxRetry: const Duration(milliseconds: 50),
    );
    addTearDown(sync.dispose);
    sync.start(peer);
    await Future<void>.delayed(const Duration(milliseconds: 95));
    expect(calls, greaterThanOrEqualTo(2));
    expect(events.any((event) => event.phase == 'retrying'), isTrue);
    expect(events.any((event) => event.phase == 'connected'), isTrue);
    expect(sync.failureCount, 0);
    expect(sync.lastSuccessAt, isNotNull);
  });

  test('many triggers during an active transfer coalesce to one follow-up',
      () async {
    var calls = 0;
    final first = Completer<LanLabSyncResult>();
    final sync = LanLabAutoSyncController(
      transfer: (_) async {
        calls++;
        if (calls == 1) return first.future;
        return const LanLabSyncResult(sent: 1, imported: 0, totalLocal: 1);
      },
      onState: (_) {},
      interval: const Duration(seconds: 5),
    );
    addTearDown(sync.dispose);
    sync.start(peer);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(calls, 1);
    sync.requestNow();
    sync.requestNow();
    sync.requestNow();
    expect(calls, 1, reason: 'never allow concurrent transfers');
    first.complete(const LanLabSyncResult(sent: 1, imported: 1, totalLocal: 1));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, 2, reason: 'coalesces pending requests to one transfer');
  });

  test('disposal prevents future polling and notifications', () async {
    var calls = 0;
    final events = <LanLabAutoSyncState>[];
    final sync = LanLabAutoSyncController(
      transfer: (_) async {
        calls++;
        return const LanLabSyncResult(sent: 0, imported: 0, totalLocal: 0);
      },
      onState: events.add,
      interval: const Duration(milliseconds: 20),
    );
    sync.start(peer);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    sync.dispose();
    final count = calls;
    final eventCount = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 55));
    expect(calls, count);
    expect(events.length, eventCount);
  });
}
