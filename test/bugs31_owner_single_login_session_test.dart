import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';

class _Enrollment implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Owner session grants payment permission without another device login',
      () async {
    const owner = OwnerSessionIdentity('owner', 'shop-session-1');
    OwnerSessionIdentity? active = owner;
    var prompts = 0;
    var roleChecks = 0;
    final authority = LocalOwnerAuthorization(
      store: _Enrollment(),
      currentIdentity: () => active,
      verifyOwner: (_) async => throw StateError('No network allowed'),
      authenticateDevice: () async { prompts++; return true; },
      verifyLocalOwner: (shop) async {
        roleChecks++;
        if (shop != 'shop' || active == null || active!.actorId != 'owner') {
          throw StateError('Not Owner');
        }
        return VerifiedOwnerEnrollment(active!, shop);
      },
    );
    final grant = await authority.authorizeSession('shop');
    grant.assertValid('shop', 'owner');
    final same = await authority.authorizeSession('shop');
    expect(identical(same, grant), isTrue);
    expect(prompts, 0);
    expect(roleChecks, 1);
    // App backgrounding and a long workday do not require another login.
    grant.assertValid('shop', 'owner');
    active = const OwnerSessionIdentity('owner', 'new-session');
    expect(() => grant.assertValid('shop', 'owner'), throwsStateError);
    final replacement = await authority.authorizeSession('shop');
    expect(identical(replacement, grant), isFalse);
    expect(prompts, 0);
    active = null;
    expect(() => replacement.assertValid('shop', 'owner'), throwsStateError);
    await authority.revoke();
  });

  test('a Secretary cannot obtain an Owner payment grant', () async {
    final authority = LocalOwnerAuthorization(
      store: _Enrollment(),
      currentIdentity: () => const OwnerSessionIdentity('secretary', 'session'),
      verifyOwner: (_) async => throw StateError('No network allowed'),
      authenticateDevice: () async => throw StateError('No OS challenge expected'),
      verifyLocalOwner: (_) async => throw StateError('Only Owner'),
    );
    await expectLater(authority.authorizeSession('shop'), throwsStateError);
  });
}
