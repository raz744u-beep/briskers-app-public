import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/secure_employee_details_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
class _Unused implements OwnerEnrollmentStore{
  @override Future<String?> read()async=>null;
  @override Future<void> write(String value)async{}
  @override Future<void> clear()async{}
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('secure details are verified, actor/shop scoped, redacted and revoked with the Owner grant',()async{
    FlutterSecureStorage.setMockInitialValues({});
    const who=OwnerSessionIdentity('owner','a');
    final auth=LocalOwnerAuthorization(store:_Unused(),currentIdentity:()=>who,verifyOwner:(_)async=>throw StateError('No network'),
      authenticateDevice:()async=>true,verifyLocalOwner:(s)async=>VerifiedOwnerEnrollment(who,s));
    final grant=await auth.authorizeLocal('shop');
    const cache=SecureEmployeeDetailsCache();
    expect(await cache.read('shop','employee',grant),isNull);
    await cache.save('shop','employee',{'id':'employee','name':'Verified Employee','hourly_rate':40,'ssn':'123456789','ssn_last4':'6789'},grant);
    final saved=await cache.read('shop','employee',grant);
    expect((saved!['details'] as Map)['name'],'Verified Employee');
    expect((saved['details'] as Map).containsKey('ssn'),isFalse);
    await expectLater(cache.read('other','employee',grant),throwsStateError);
    await auth.revoke();await expectLater(cache.read('shop','employee',grant),throwsStateError);
  });
}
