import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public payroll ID survives a fresh load and cannot sign', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = await PayrollLanIdentity.loadFromStorage(
      const FlutterSecureStorage(),
    );
    final reopened = await PayrollLanIdentity.loadFromStorage(
      const FlutterSecureStorage(),
    );
    expect(reopened.deviceId, first.deviceId);
    const challenge = 'offline payroll device proof';
    expect(await PayrollLanIdentity.verify(
      first.deviceId, challenge, await reopened.sign(challenge),
    ), isTrue);
    final copiedId = await PayrollLanIdentity.fromSeed(first.publicKey.bytes);
    expect(copiedId.deviceId, isNot(first.deviceId));
    expect(await PayrollLanIdentity.verify(
      first.deviceId, challenge, await copiedId.sign(challenge),
    ), isFalse);
  });
}
