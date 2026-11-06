import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';

/// Raised before transport. Callers may retain their outbox state, but cannot
/// bypass the independent durable fence by resetting that state to pending.
class SyncReplayDeferred implements Exception {
  const SyncReplayDeferred(this.reason);
  final String reason;
  @override
  String toString() =>
      'Synchronization paused: $reason. Saved work is retained.';
}

bool isSyncVersionConflict(Object error) {
  if (error is PostgrestException &&
      const {'40001', 'PT409'}.contains(error.code)) {
    return true;
  }
  final text = error.toString();
  return text.contains('40001') || text.contains('PT409');
}

/// An additive SQLite transport fence shared by foreground/background workers.
/// No timers, automatic reset, payload rewrites, or record deletion. Claims are
/// committed before sending. An interrupted claim requires reconciliation;
/// expiring a lease while an uncertain mutation is still running is unsafe.
class SyncReplayFence {
  SyncReplayFence(
    this.db, {
    DateTime Function()? now,
    double Function()? random,
    bool Function()? networkAllowed,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random().nextDouble,
       _networkAllowed =
           networkAllowed ??
           (() => !BriskersConnectionModeController.instance.forceOffline);

  final BriskersLocalDatabase db;
  final DateTime Function() _now;
  final double Function() _random;
  final bool Function() _networkAllowed;
  static const maxAttempts = 5;
  static final Object _activeFence = Object();

  Future<void> ensureSchema() => db.customStatement('''
    CREATE TABLE IF NOT EXISTS sync_replay_fences_v1 (
      business_id TEXT NOT NULL, replay_key TEXT NOT NULL,
      status TEXT NOT NULL, attempts INTEGER NOT NULL,
      not_before_ms INTEGER NOT NULL, error_code TEXT,
      PRIMARY KEY (business_id,replay_key)
    )
  ''');

  Future<T> run<T>(
    String businessId,
    String key,
    Future<T> Function() request, {
    int? outboxId,
  }) async {
    if (!_networkAllowed()) throw const SyncReplayDeferred('Force Offline');
    // An outbox mutation can call a directly protected API. The outer scope
    // owns its durable budget: independent nested jitter deadlines could
    // otherwise turn a legitimate delayed retry into another held failure.
    if (Zone.current[_activeFence] == (db, businessId)) return request();
    await ensureSchema();
    final now = _now().millisecondsSinceEpoch;
    await db.transaction(() async {
      // Also fence pre-upgrade failures before sending even one stale request.
      if (outboxId != null) {
        final queued = await db
            .customSelect(
              'SELECT state,last_error,attempt_count FROM sync_outbox '
              'WHERE business_id=? AND id=?',
              variables: [
                Variable<String>(businessId),
                Variable<int>(outboxId),
              ],
            )
            .getSingleOrNull();
        if (queued == null ||
            !{'pending', 'inflight'}.contains(queued.read<String>('state'))) {
          throw const SyncReplayDeferred('operation needs review');
        }
        final previous = queued.readNullable<String>('last_error');
        if (previous != null && isSyncVersionConflict(previous)) {
          throw const SyncReplayDeferred(
            'version conflict needs reconciliation',
          );
        }
      }
      await db.customStatement(
        "INSERT OR IGNORE INTO sync_replay_fences_v1 VALUES (?,?,'ready',0,0,NULL)",
        [businessId, key],
      );
      final row = await db
          .customSelect(
            'SELECT * FROM sync_replay_fences_v1 WHERE business_id=? AND replay_key=?',
            variables: [Variable<String>(businessId), Variable<String>(key)],
          )
          .getSingle();
      if (row.read<String>('status') != 'ready' ||
          row.read<int>('attempts') >= maxAttempts ||
          row.read<int>('not_before_ms') > now) {
        throw const SyncReplayDeferred(
          'cooldown, active request, or Owner review',
        );
      }
      await db.customStatement(
        "UPDATE sync_replay_fences_v1 SET status='inflight',attempts=attempts+1 "
        'WHERE business_id=? AND replay_key=?',
        [businessId, key],
      );
    });
    try {
      // Recheck after SQLite awaits, including a mode change during a claim.
      if (!_networkAllowed()) throw const SyncReplayDeferred('Force Offline');
      final result = await runZoned(
        request,
        zoneValues: {_activeFence: (db, businessId)},
      );
      await db.customStatement(
        'DELETE FROM sync_replay_fences_v1 WHERE business_id=? AND replay_key=?',
        [businessId, key],
      );
      return result;
    } catch (error) {
      final conflict = isSyncVersionConflict(error);
      final transient = _isTransient(error);
      final row = await db
          .customSelect(
            'SELECT attempts FROM sync_replay_fences_v1 WHERE business_id=? AND replay_key=?',
            variables: [Variable<String>(businessId), Variable<String>(key)],
          )
          .getSingle();
      final attempts = row.read<int>('attempts');
      // 30s, 60s, 120s, 240s (+0..25% jitter); fifth failure is held.
      final delayMs =
          (30000 * (1 << (attempts - 1)) * (1 + 0.25 * _random().clamp(0, 1)))
              .round();
      await db.customStatement(
        'UPDATE sync_replay_fences_v1 SET status=?,not_before_ms=?,error_code=? '
        'WHERE business_id=? AND replay_key=?',
        [
          conflict
              ? 'conflict'
              : (transient && attempts < maxAttempts ? 'ready' : 'review'),
          _now().millisecondsSinceEpoch + delayMs,
          error is PostgrestException
              ? error.code
              : error.runtimeType.toString(),
          businessId,
          key,
        ],
      );
      rethrow;
    }
  }

  static bool _isTransient(Object error) {
    if (error is TimeoutException) return true;
    if (error is PostgrestException) {
      return const {
        'PGRST000',
        'PGRST001',
        'PGRST002',
        'PGRST003',
        '503',
        '504',
        '520',
        '53300',
        '57P01',
      }.contains(error.code);
    }
    // dart:io cannot be imported into the web app; classify transport types
    // without mistaking business validation failures for network failures.
    return const {
      'SocketException',
      'ClientException',
      'HandshakeException',
    }.contains(error.runtimeType.toString());
  }
}
