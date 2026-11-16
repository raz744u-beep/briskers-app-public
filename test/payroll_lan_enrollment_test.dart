import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/payroll_lan_enrollment.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedEnrollmentStore implements OwnerEnrollmentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Owner authentication is device independent; mechanic links remain account scoped',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    const session = OwnerSessionIdentity('owner', 'session');
    Future<VerifiedOwnerEnrollment> verify(String shop) async =>
        VerifiedOwnerEnrollment(session, shop);
    final auth = LocalOwnerAuthorization(
      store: _UnusedEnrollmentStore(), currentIdentity: () => session,
      verifyOwner: (_) async => throw StateError('Internet is unavailable.'),
      verifyLocalOwner: verify, authenticateDevice: () async => true,
    );
    final grant = await auth.authorizeLocal('shop');
    final owner = await PayrollLanIdentity.fromSeed(List.filled(32, 1));
    final mechanic = await PayrollLanIdentity.fromSeed(List.filled(32, 2));
    final stranger = await PayrollLanIdentity.fromSeed(List.filled(32, 3));
    PayrollLanEnrollment installation(PayrollLanIdentity identity) =>
        PayrollLanEnrollment(identity, storage: storage, approvedWriter: owner.deviceId);
    final enroll = installation(owner);
    await enroll.assertWriter('shop', grant);
    await enroll.designate('shop', grant);
    final invitation = await enroll.invite(
      business: 'shop', employee: 'a', mechanicDevice: mechanic.deviceId,
      grant: grant,
    );
    await expectLater(enroll.invite(
      business: 'shop', employee: 'b', mechanicDevice: mechanic.deviceId,
      grant: grant,
    ), throwsStateError);
    final restored = installation(owner);
    await restored.assertWriter('shop', grant);
    expect((await restored.ownerPeer('shop', 'a'))?.mechanicDevice,
        mechanic.deviceId);
    await installation(stranger).assertWriter('shop', grant);

    // Simulate a separate installation's initially empty secure store.
    FlutterSecureStorage.setMockInitialValues({});
    await installation(stranger).assertWriter('shop', grant);
    await expectLater(installation(stranger).accept(
      code: invitation, business: 'shop', verifiedOwnerDevice: owner.deviceId,
      actor: 'mechanic',
    ), throwsStateError);
    final receiver = installation(mechanic);
    await expectLater(receiver.accept(
      code: invitation, business: 'other', verifiedOwnerDevice: owner.deviceId,
      actor: 'mechanic',
    ), throwsStateError);
    await expectLater(receiver.accept(
      code: invitation, business: 'shop', verifiedOwnerDevice: stranger.deviceId,
      actor: 'mechanic',
    ), throwsStateError);
    await receiver.accept(
      code: invitation, business: 'shop', verifiedOwnerDevice: owner.deviceId,
      actor: 'mechanic',
    );
    final reopened = installation(mechanic);
    expect((await reopened.mechanicPeer('shop', 'mechanic'))?.employee, 'a');
    await expectLater(reopened.mechanicPeer('shop', 'another'), throwsStateError);
    await expectLater(reopened.assertWriter('other-shop', grant), throwsStateError);
    auth.lock();
    await expectLater(reopened.assertWriter('shop', grant), throwsStateError);
  });
}
