import 'dart:async';
import 'dart:convert';

import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryEnrollmentStore implements OwnerEnrollmentStore {
  String? value;
  bool failClear = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async { this.value = value; }
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('Key store unavailable');
    value = null;
  }
}

void main() {
  late MemoryEnrollmentStore store;
  late OwnerSessionIdentity? identity;
  late LocalOwnerAuthorization auth;
  late DateTime now;
  late bool isOwner;
  late bool deviceAccepted;
  late int networkChecks;
  late Future<bool> Function() deviceChallenge;
  const owner = OwnerSessionIdentity('owner-a', 'session-a');

  LocalOwnerAuthorization service() => LocalOwnerAuthorization(
    store: store, currentIdentity: () => identity, now: () => now,
    verifyOwner: (business) async {
      networkChecks++;
      if (!isOwner) throw StateError('Not Owner');
      return VerifiedOwnerEnrollment(identity!, business);
    },
    authenticateDevice: () => deviceChallenge(),
  );

  setUp(() {
    store = MemoryEnrollmentStore();
    identity = owner;
    now = DateTime.utc(2026, 11, 1);
    isOwner = true;
    deviceAccepted = true;
    networkChecks = 0;
    deviceChallenge = () async => deviceAccepted;
    auth = service();
  });

  test('no protected enrollment means no offline Owner grant', () async {
    await expectLater(auth.unlock('shop-a'), throwsStateError);
    expect(networkChecks, 0);
  });
  test('server non-Owner cannot enroll despite accepting device challenge', () async {
    isOwner = false;
    await expectLater(auth.enroll('shop-a'), throwsStateError);
    expect(store.value, isNull);
  });
  test('cancelled device enrollment writes no authority', () async {
    deviceAccepted = false;
    await expectLater(auth.enroll('shop-a'), throwsStateError);
    expect(store.value, isNull);
  });
  test('restart offline unlock uses protected record with no network call', () async {
    await auth.enroll('shop-a');
    isOwner = false; // Offline verifier must never be called.
    final reopened = service();
    final grant = await reopened.unlock('shop-a');
    grant.assertValid('shop-a', 'owner-a');
    expect(networkChecks, 1);
  });
  test('grant cannot authorize another business or actor', () async {
    await auth.enroll('shop-a');
    final grant = await auth.unlock('shop-a');
    expect(() => grant.assertValid('shop-b', 'owner-a'), throwsStateError);
    expect(() => grant.assertValid('shop-a', 'mechanic-a'), throwsStateError);
  });
  test('enrollment is bound to the business', () async {
    await auth.enroll('shop-a');
    await expectLater(auth.unlock('shop-b'), throwsStateError);
  });
  test('same user in a new session must enroll again', () async {
    await auth.enroll('shop-a');
    identity = const OwnerSessionIdentity('owner-a', 'new-session');
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('another account cannot use the device enrollment', () async {
    await auth.enroll('shop-a');
    identity = const OwnerSessionIdentity('mechanic-a', 'session-a');
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('signout invalidates a grant immediately', () async {
    await auth.enroll('shop-a');
    final grant = await auth.unlock('shop-a');
    final revoked = auth.revoke();
    expect(() => grant.assertValid('shop-a', 'owner-a'), throwsStateError);
    await revoked;
    expect(store.value, isNull);
  });
  test('grant expires before the enrollment expires', () async {
    await auth.enroll('shop-a');
    final grant = await auth.unlock('shop-a');
    now = now.add(LocalOwnerAuthorization.unlockLifetime);
    expect(() => grant.assertValid('shop-a', 'owner-a'), throwsStateError);
  });
  test('expired enrollment cannot unlock offline', () async {
    await auth.enroll('shop-a');
    now = now.add(LocalOwnerAuthorization.enrollmentLifetime);
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('clock rollback is rejected', () async {
    await auth.enroll('shop-a');
    now = now.subtract(const Duration(seconds: 1));
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('malformed or extended lifetime record fails closed', () async {
    await auth.enroll('shop-a');
    final record = jsonDecode(store.value!) as Map<String, dynamic>;
    record['expires_at'] = now.add(const Duration(days: 30)).millisecondsSinceEpoch;
    store.value = jsonEncode(record);
    await expectLater(auth.unlock('shop-a'), throwsStateError);
    store.value = '{broken';
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('cancelled unlock returns no grant', () async {
    await auth.enroll('shop-a');
    deviceAccepted = false;
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('account switch during device prompt cannot create a grant', () async {
    await auth.enroll('shop-a');
    deviceChallenge = () async {
      identity = const OwnerSessionIdentity('mechanic-a', 'other-session');
      return true;
    };
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('revocation during enrollment cannot re-enroll the signed-out account', () async {
    deviceChallenge = () async {
      await auth.revoke();
      return true;
    };
    await expectLater(auth.enroll('shop-a'), throwsStateError);
    expect(store.value, isNull);
  });
  test('failed secure-store revocation blocks every existing grant', () async {
    await auth.enroll('shop-a');
    final grant = await auth.unlock('shop-a');
    store.failClear = true;
    await expectLater(auth.revoke(), throwsStateError);
    expect(() => grant.assertValid('shop-a', 'owner-a'), throwsStateError);
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
  test('concurrent unlocks do not share a device challenge', () async {
    await auth.enroll('shop-a');
    final challenge = Completer<bool>();
    deviceChallenge = () => challenge.future;
    final first = auth.unlock('shop-a');
    await expectLater(auth.unlock('shop-a'), throwsStateError);
    challenge.complete(true);
    (await first).assertValid('shop-a', 'owner-a');
  });
  test('enrollment expiry during device challenge denies grant', () async {
    await auth.enroll('shop-a');
    deviceChallenge = () async {
      now = now.add(LocalOwnerAuthorization.enrollmentLifetime);
      return true;
    };
    await expectLater(auth.unlock('shop-a'), throwsStateError);
  });
}
