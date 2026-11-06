import 'dart:async';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/sync_replay_fence.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late BriskersLocalDatabase db;
  late DateTime now;
  late bool online;
  SyncReplayFence fence() => SyncReplayFence(
    db,
    now: () => now,
    random: () => 0.5,
    networkAllowed: () => online,
  );
  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 6);
    online = true;
  });
  tearDown(() => db.close());

  for (final code in ['40001', 'PT409']) {
    test(
      '$code makes exactly one request despite 1000 triggers and new workers',
      () async {
        var calls = 0;
        Future<void> send() async {
          calls++;
          throw PostgrestException(message: 'changed', code: code);
        }

        await expectLater(
          fence().run('shop', 'op', send),
          throwsA(isA<PostgrestException>()),
        );
        for (var i = 0; i < 1000; i++) {
          now = now.add(const Duration(minutes: 1));
          await expectLater(
            fence().run('shop', 'op', send),
            throwsA(isA<SyncReplayDeferred>()),
          );
        }
        expect(calls, 1);
        // A different operation is independent, not stalled behind this one.
        expect(await fence().run('shop', 'healthy', () async => 42), 42);
      },
    );
  }

  for (final error in <Object>[
    TimeoutException('lost response'),
    const SocketException('offline'),
    const PostgrestException(message: 'pool', code: 'PGRST003'),
    const PostgrestException(message: 'temporary', code: '503'),
  ]) {
    test(
      '${error.runtimeType}: bounded persisted jittered backoff and retry budget',
      () async {
        var calls = 0;
        Future<void> send() async {
          calls++;
          throw error;
        }

        for (var attempt = 1; attempt <= 5; attempt++) {
          await expectLater(
            fence().run('shop', 'op', send),
            throwsA(same(error)),
          );
          final saved = await db
              .customSelect('SELECT * FROM sync_replay_fences_v1')
              .getSingle();
          expect(saved.read<int>('attempts'), attempt);
          final until = saved.read<int>('not_before_ms');
          expect(
            until - now.millisecondsSinceEpoch,
            (30000 * (1 << (attempt - 1)) * 1.125).round(),
          );
          for (var i = 0; i < 25; i++) {
            await expectLater(
              fence().run('shop', 'op', send),
              throwsA(isA<SyncReplayDeferred>()),
            );
          }
          now = DateTime.fromMillisecondsSinceEpoch(until);
        }
        now = now.add(const Duration(days: 100));
        await expectLater(
          fence().run('shop', 'op', send),
          throwsA(isA<SyncReplayDeferred>()),
        );
        expect(calls, 5);
      },
    );
  }

  test(
    'concurrent foreground/resume/background triggers send one mutation',
    () async {
      var calls = 0;
      final started = Completer<void>();
      final finish = Completer<String>();
      final first = fence().run('shop', 'payment-id', () {
        calls++;
        started.complete();
        return finish.future;
      });
      await started.future;
      final duplicates = List.generate(
        20,
        (_) => expectLater(
          fence().run('shop', 'payment-id', () async {
            calls++;
            return 'duplicate';
          }),
          throwsA(isA<SyncReplayDeferred>()),
        ),
      );
      await Future.wait(duplicates);
      finish.complete('receipt-id');
      expect(await first, 'receipt-id');
      expect(calls, 1);
    },
  );

  test(
    'Force Offline blocks ordinary writes without consuming attempts',
    () async {
      var calls = 0;
      online = false;
      await expectLater(
        fence().run('shop', 'op', () async {
          calls++;
        }),
        throwsA(isA<SyncReplayDeferred>()),
      );
      expect(calls, 0);
      online = true;
      await fence().run('shop', 'op', () async {
        calls++;
      });
      expect(calls, 1);
    },
  );

  test(
    'recovery after server becomes healthy preserves request identity',
    () async {
      var calls = 0;
      Future<String> send() async {
        calls++;
        if (calls == 1) {
          throw const PostgrestException(message: 'busy', code: 'PGRST003');
        }
        return 'same-operation-receipt';
      }

      await expectLater(
        fence().run('shop', 'stable-op', send),
        throwsA(isA<PostgrestException>()),
      );
      now = now.add(const Duration(minutes: 1));
      expect(
        await fence().run('shop', 'stable-op', send),
        'same-operation-receipt',
      );
      expect(calls, 2);
      expect(
        await db.customSelect('SELECT * FROM sync_replay_fences_v1').get(),
        isEmpty,
      );
    },
  );

  test(
    'legacy stale outbox, payload, version and payment metadata are retained',
    () async {
      await db.customStatement(
        "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,base_row_version,last_error) VALUES ('shop','payment','doc','create','{\"operation_id\":\"stable\",\"amount\":123}',4,'40001 stale')",
      );
      final before =
          (await db.customSelect('SELECT * FROM sync_outbox').getSingle()).data;
      var calls = 0;
      await expectLater(
        fence().run('shop', 'outbox:1', () async {
          calls++;
        }, outboxId: 1),
        throwsA(isA<SyncReplayDeferred>()),
      );
      expect(calls, 0);
      expect(
        (await db.customSelect('SELECT * FROM sync_outbox').getSingle()).data,
        before,
      );
    },
  );

  test(
    'two devices: winning revision accepted, stale device fenced once',
    () async {
      final other = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      var version = 1, writes = 0, attempts = 0;
      Future<void> send(int expected) async {
        attempts++;
        if (expected != version) {
          throw const PostgrestException(message: 'changed', code: 'PT409');
        }
        version++;
        writes++;
      }

      await fence().run('shop', 'op-A', () => send(1));
      final second = SyncReplayFence(other, networkAllowed: () => true);
      await expectLater(
        second.run('shop', 'op-B', () => send(1)),
        throwsA(isA<PostgrestException>()),
      );
      for (var i = 0; i < 20; i++) {
        await expectLater(
          second.run('shop', 'op-B', () => send(1)),
          throwsA(isA<SyncReplayDeferred>()),
        );
      }
      expect(writes, 1);
      expect(attempts, 2);
    },
  );

  test('file-backed restart retains cooldown and interrupted claims', () async {
    final dir = await Directory.systemTemp.createTemp('briskers-replay-test-');
    final file = File('${dir.path}/test.sqlite');
    var disk = BriskersLocalDatabase(NativeDatabase(file));
    SyncReplayFence diskFence() => SyncReplayFence(
      disk,
      now: () => now,
      networkAllowed: () => true,
      random: () => 0,
    );
    await expectLater(
      diskFence().run('shop', 'op', () async {
        throw TimeoutException('lost');
      }),
      throwsA(isA<TimeoutException>()),
    );
    await disk.close();
    disk = BriskersLocalDatabase(NativeDatabase(file));
    var calls = 0;
    await expectLater(
      diskFence().run('shop', 'op', () async {
        calls++;
      }),
      throwsA(isA<SyncReplayDeferred>()),
    );
    // Simulate a crash after the committed transport claim, before a response.
    await disk.customStatement(
      "UPDATE sync_replay_fences_v1 SET status='inflight'",
    );
    await disk.close();
    disk = BriskersLocalDatabase(NativeDatabase(file));
    now = now.add(const Duration(days: 2));
    await expectLater(
      diskFence().run('shop', 'op', () async {
        calls++;
      }),
      throwsA(isA<SyncReplayDeferred>()),
    );
    expect(calls, 0);
    await disk.close();
    await dir.delete(recursive: true);
  });

  test(
    'nested API protection shares the outbox budget and recovers once',
    () async {
      var calls = 0;
      Future<String> replay() => fence().run(
        'shop',
        'outbox:1',
        () => fence().run('shop', 'rpc:mileage', () async {
          calls++;
          if (calls == 1) {
            throw const PostgrestException(message: 'busy', code: 'PGRST003');
          }
          return 'verified';
        }),
      );
      await expectLater(replay(), throwsA(isA<PostgrestException>()));
      final rows = await db
          .customSelect('SELECT * FROM sync_replay_fences_v1')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('replay_key'), 'outbox:1');
      await expectLater(replay(), throwsA(isA<SyncReplayDeferred>()));
      now = now.add(const Duration(minutes: 1));
      expect(await replay(), 'verified');
      expect(calls, 2);
      expect(
        await db.customSelect('SELECT * FROM sync_replay_fences_v1').get(),
        isEmpty,
      );
    },
  );
}
