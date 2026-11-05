import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'local_owner_authorization.dart';

/// Never caches full SSNs or credentials. Fresh Owner authorization is required
/// on every read; snapshots are encrypted and bound to business + Owner actor.
class SecureEmployeeDetailsCache {
  const SecureEmployeeDetailsCache();
  static const _storage=FlutterSecureStorage(iOptions:IOSOptions(accessibility:KeychainAccessibility.unlocked_this_device));
  String _key(String shop,String actor,String employee)=>'briskers_employee_private_v1:${jsonEncode([shop,actor,employee])}';
  Future<void> save(String shop,String employee,Map<String,dynamic> detail,LocalOwnerGrant grant) async {
    grant.assertValid(shop,grant.actorId);
    final safe={for(final k in ['id','name','phone','email','address','position_id','payment_type','hourly_rate','weekly_rate','compensation_enabled','active','ssn_last4'])
      if(detail.containsKey(k)) k:detail[k]};
    if(safe['id']!=employee)throw StateError('Employee identity differs.');
    await _storage.write(key:_key(shop,grant.actorId,employee),value:jsonEncode({'verified_at':DateTime.now().toUtc().toIso8601String(),'details':safe}));
    grant.assertValid(shop,grant.actorId);
  }
  Future<Map<String,dynamic>?> read(String shop,String employee,LocalOwnerGrant grant)async{
    grant.assertValid(shop,grant.actorId);
    final raw=await _storage.read(key:_key(shop,grant.actorId,employee));
    grant.assertValid(shop,grant.actorId);
    if(raw==null)return null;
    final value=Map<String,dynamic>.from(jsonDecode(raw) as Map);
    final time=DateTime.parse(value['verified_at'] as String);
    final age=DateTime.now().toUtc().difference(time);
    if(age.isNegative||age>const Duration(days:7))throw StateError('Verified offline details expired. No employee record was deleted.');
    if((value['details'] as Map)['id']!=employee)throw StateError('Employee identity differs.');
    return value;
  }
}
