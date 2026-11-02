import 'dart:convert';

/// The only persistent authority is the platform-protected enrollment record.
/// Business/UI caches are deliberately not inputs to this service.
abstract interface class OwnerEnrollmentStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class OwnerSessionIdentity {
  const OwnerSessionIdentity(this.actorId, this.sessionId);
  final String actorId;
  final String sessionId;
  bool matches(OwnerSessionIdentity? other) => other != null &&
      actorId == other.actorId && sessionId == other.sessionId;
}

class VerifiedOwnerEnrollment {
  const VerifiedOwnerEnrollment(this.identity, this.businessId);
  final OwnerSessionIdentity identity;
  final String businessId;
}

/// Callers obtain this only after platform authentication. Its validity is
/// checked on every preview and commit, including after asynchronous work.
class LocalOwnerGrant {
  LocalOwnerGrant._(this._authority, this._generation, this._identity,
      this.businessId, this._expiresAt);
  final LocalOwnerAuthorization _authority;
  final int _generation;
  final OwnerSessionIdentity _identity;
  final String businessId;
  final DateTime _expiresAt;
  String get actorId => _identity.actorId;

  void assertValid(String business, String actor) {
    final now = _authority._now().toUtc();
    if (_generation != _authority._generation ||
        !_identity.matches(_authority._currentIdentity()) ||
        business != businessId || actor != actorId ||
        !now.isBefore(_expiresAt) || now.isBefore(_authority._lastVerifiedAt)) {
      throw StateError('Owner authorization expired. Unlock the Owner account again.');
    }
  }
}

class LocalOwnerAuthorization {
  LocalOwnerAuthorization({
    required OwnerEnrollmentStore store,
    required OwnerSessionIdentity? Function() currentIdentity,
    required Future<VerifiedOwnerEnrollment> Function(String business) verifyOwner,
    required Future<bool> Function() authenticateDevice,
    DateTime Function()? now,
  }) : _store = store, _currentIdentity = currentIdentity,
       _verifyOwner = verifyOwner, _authenticateDevice = authenticateDevice,
       _now = now ?? DateTime.now;

  final OwnerEnrollmentStore _store;
  final OwnerSessionIdentity? Function() _currentIdentity;
  final Future<VerifiedOwnerEnrollment> Function(String) _verifyOwner;
  final Future<bool> Function() _authenticateDevice;
  final DateTime Function() _now;
  int _generation = 0;
  bool _busy = false;
  bool _storageFailed = false;
  Future<void> _writes = Future<void>.value();
  DateTime _lastVerifiedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  static const enrollmentLifetime = Duration(days: 7);
  static const unlockLifetime = Duration(minutes: 2);

  Future<void> _write(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) { _storageFailed = true; });
    return next;
  }

  /// Invalidates in-memory grants synchronously, even if secure storage fails.
  Future<void> revoke() {
    _generation++;
    return _write(_store.clear);
  }

  bool get isAuthenticating => _busy;

  void lock() { _generation++; }

  void _check(OwnerSessionIdentity identity, int generation) {
    if (_storageFailed || generation != _generation ||
        !identity.matches(_currentIdentity())) {
      throw StateError('Owner account changed. Start authorization again.');
    }
  }

  /// Requires a fresh server-authenticated Owner check and device unlock.
  /// This method must be explicitly requested; it never enrolls a role cache.
  Future<void> enroll(String businessId) async {
    if (_busy) throw StateError('Owner authentication is already open.');
    _busy = true;
    try {
      final identity = _currentIdentity();
      if (identity == null || businessId.isEmpty) {
        throw StateError('Sign in to the Owner account before enrolling this device.');
      }
      final generation = ++_generation;
      final verified = await _verifyOwner(businessId);
      _check(identity, generation);
      if (!verified.identity.matches(identity) || verified.businessId != businessId) {
        throw StateError('The server did not verify this business Owner.');
      }
      if (!await _authenticateDevice()) throw StateError('Owner unlock cancelled.');
      _check(identity, generation);
      final now = _now().toUtc();
      final record = jsonEncode({
        'version': 1, 'actor_id': identity.actorId, 'session_id': identity.sessionId,
        'business_id': businessId, 'verified_at': now.millisecondsSinceEpoch,
        'expires_at': now.add(enrollmentLifetime).millisecondsSinceEpoch,
      });
      await _write(() async {
        _check(identity, generation);
        await _store.write(record);
      });
      _check(identity, generation);
      _lastVerifiedAt = now;
    } finally { _busy = false; }
  }

  /// No network calls: a protected enrollment plus a fresh device challenge.
  Future<LocalOwnerGrant> unlock(String businessId) async {
    if (_busy) throw StateError('Owner authentication is already open.');
    _busy = true;
    try {
      final identity = _currentIdentity();
      if (identity == null) throw StateError('Sign in to the enrolled Owner account.');
      final generation = ++_generation;
      await _writes;
      _check(identity, generation);
      final raw = await _store.read();
      _check(identity, generation);
      Map<String, dynamic> record;
      try { record = Map<String, dynamic>.from(jsonDecode(raw ?? '') as Map); }
      catch (_) { throw StateError('Enroll this Owner device while online first.'); }
      final verifiedAt = record['verified_at'];
      final expiresAt = record['expires_at'];
      final now = _now().toUtc();
      if (record['version'] != 1 || record['actor_id'] != identity.actorId ||
          record['session_id'] != identity.sessionId || record['business_id'] != businessId ||
          verifiedAt is! int || expiresAt is! int || expiresAt <= verifiedAt ||
          expiresAt - verifiedAt > enrollmentLifetime.inMilliseconds ||
          now.millisecondsSinceEpoch < verifiedAt || now.millisecondsSinceEpoch >= expiresAt) {
        throw StateError('Owner enrollment expired or belongs to another account. Enroll again while online.');
      }
      _lastVerifiedAt = DateTime.fromMillisecondsSinceEpoch(verifiedAt, isUtc: true);
      if (!await _authenticateDevice()) throw StateError('Owner unlock cancelled.');
      _check(identity, generation);
      final after = _now().toUtc();
      if (after.millisecondsSinceEpoch >= expiresAt || after.isBefore(now)) {
        throw StateError('Owner enrollment expired during unlock.');
      }
      final until = after.add(unlockLifetime).millisecondsSinceEpoch;
      return LocalOwnerGrant._(this, generation, identity, businessId,
          DateTime.fromMillisecondsSinceEpoch(until < expiresAt ? until : expiresAt, isUtc: true));
    } finally { _busy = false; }
  }
}
