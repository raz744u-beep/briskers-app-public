import 'dart:async';

import 'shop_lan_lab_transport.dart';

/// A foreground-only, single-flight automatic synchronizer for synthetic notes.
/// It does not open any real Briskers records and never requires Internet.
class LanLabAutoSyncState {
  const LanLabAutoSyncState({
    required this.phase,
    required this.message,
    required this.isRunning,
    required this.isSyncing,
    this.lastSuccessAt,
    this.lastImported = 0,
    this.lastSent = 0,
    this.failureCount = 0,
  });

  final String phase;
  final String message;
  final bool isRunning;
  final bool isSyncing;
  final DateTime? lastSuccessAt;
  final int lastImported;
  final int lastSent;
  final int failureCount;
}

class LanLabAutoSyncController {
  LanLabAutoSyncController({
    required Future<LanLabSyncResult> Function(LanLabPairing) transfer,
    required void Function(LanLabAutoSyncState) onState,
    this.onSuccess,
    this.interval = const Duration(seconds: 6),
    this.timeout = const Duration(seconds: 22),
    this.maxRetry = const Duration(seconds: 48),
  }) : _transfer = transfer,
       _onState = onState;

  final Future<LanLabSyncResult> Function(LanLabPairing) _transfer;
  final void Function(LanLabAutoSyncState) _onState;
  final Future<void> Function()? onSuccess;
  final Duration interval;
  final Duration timeout;
  final Duration maxRetry;

  LanLabPairing? _peer;
  Timer? _timer;
  bool _active = false;
  bool _disposed = false;
  bool _syncing = false;
  bool _resyncRequested = false;
  int _failures = 0;
  DateTime? _lastSuccess;
  int _lastSent = 0;
  int _lastImported = 0;
  String _message = 'Automatic sync waiting for pairing';
  String _phase = 'waiting';

  bool get isSyncing => _syncing;
  bool get isActive => _active && !_disposed;
  int get failureCount => _failures;
  DateTime? get lastSuccessAt => _lastSuccess;

  void start(LanLabPairing? peer) {
    if (_disposed) return;
    _peer = peer;
    _active = true;
    _schedule(Duration.zero);
    if (peer == null) _emit('waiting', 'Automatic sync waiting for QR pairing');
  }

  void setPeer(LanLabPairing? peer) {
    if (_disposed) return;
    _peer = peer;
    _failures = 0;
    if (peer != null) {
      _schedule(Duration.zero);
    } else {
      _timer?.cancel();
      _emit('waiting', 'Automatic sync waiting for QR pairing');
    }
  }

  void pause() {
    if (_disposed) return;
    _active = false;
    _timer?.cancel();
    _emit('paused', 'Automatic sync paused while app is in background');
  }

  void resume() {
    if (_disposed) return;
    _active = true;
    _schedule(Duration.zero);
  }

  /// Can be called after a new note or by the fallback Sync Now button.
  /// A request during a transfer is coalesced into one follow-up transfer.
  void requestNow() {
    if (_disposed || !_active || _peer == null) return;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }
    _schedule(Duration.zero);
  }

  void _schedule(Duration duration) {
    if (_disposed || !_active) return;
    _timer?.cancel();
    if (_peer == null) {
      _emit('waiting', 'Automatic sync waiting for QR pairing');
      return;
    }
    if (_syncing) {
      _resyncRequested = true;
      return;
    }
    _timer = Timer(duration, () {
      unawaited(runOnce());
    });
  }

  /// Public for deterministic unit tests. All paths share one flight.
  Future<void> runOnce() async {
    if (_disposed || !_active || _peer == null) return;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }
    _timer?.cancel();
    _syncing = true;
    final peer = _peer!;
    _emit('connecting', 'Auto-sync connecting to ${peer.host}:${peer.port}...');
    try {
      final result = await _transfer(peer).timeout(timeout);
      if (_disposed) return;
      _failures = 0;
      _lastSuccess = DateTime.now();
      _lastSent = result.sent;
      _lastImported = result.imported;
      _emit(
        'connected',
        'Auto-sync connected: ${result.totalLocal} notes saved. '
        '${result.imported} new received; ${result.sent} sent.',
      );
      if (onSuccess != null) {
        try {
          await onSuccess!();
        } catch (_) {
          // UI refresh failures must never invalidate a confirmed transfer.
        }
      }
    } catch (error) {
      if (_disposed) return;
      _failures++;
      _emit(
        'retrying',
        'Auto-sync unavailable (attempt $_failures): $error. '
        'Notes remain saved; retry is automatic.',
      );
    } finally {
      _syncing = false;
      if (!_disposed && _active) {
        if (_resyncRequested) {
          _resyncRequested = false;
          _schedule(Duration.zero);
        } else if (_failures == 0) {
          _schedule(interval);
        } else {
          final base = interval.inMilliseconds;
          final ceiling = maxRetry.inMilliseconds;
          final shift = (_failures - 1).clamp(0, 5).toInt();
          final millis = (base * (1 << shift)).clamp(base, ceiling).toInt();
          _schedule(Duration(milliseconds: millis));
        }
      }
    }
  }

  void _emit(String phase, String message) {
    if (_disposed) return;
    _phase = phase;
    _message = message;
    _onState(LanLabAutoSyncState(
      phase: _phase,
      message: _message,
      isRunning: _active,
      isSyncing: _syncing,
      lastSuccessAt: _lastSuccess,
      lastImported: _lastImported,
      lastSent: _lastSent,
      failureCount: _failures,
    ));
  }

  void dispose() {
    _disposed = true;
    _active = false;
    _timer?.cancel();
    _resyncRequested = false;
  }
}
