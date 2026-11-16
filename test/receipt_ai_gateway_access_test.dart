import 'dart:async';

import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/receipt_ai_gateway_access.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenStorage implements ReceiptAiTokenStorage {
  final values=<String,String>{};
  int writes=0;
  @override
  Future<String?> read(String key) async=>values[key];
  @override
  Future<void> write(String key,String value) async{
    values[key]=value;
    writes++;
  }
  @override
  Future<void> delete(String key) async{values.remove(key);}
}

void main(){
  const ownerA=OwnerSessionIdentity('owner-a','session-a');
  const ownerB=OwnerSessionIdentity('owner-b','session-b');
  test('Owner can pair and reuse a token for only their business/account',()async{
    final storage=_MemoryTokenStorage();
    var identity=ownerA;
    final access=ReceiptAiGatewayAccess(
      storage:storage,
      identity:()=>identity,
      verifyOwner:(business)async=>business=='shop-a',
    );
    expect(await access.read('shop-a'),isNull);
    await access.saveVerified('shop-a','synthetic-strong-test-gateway-token');
    expect(await access.read('shop-a'),'synthetic-strong-test-gateway-token');
    expect(storage.values.length,1);
    identity=ownerB;
    expect(await access.read('shop-a'),isNull);
    await expectLater(access.read('shop-b'),throwsStateError);
    identity=ownerA;
    expect(await access.read('shop-a'),'synthetic-strong-test-gateway-token');
    await access.disconnect('shop-a');
    expect(await access.read('shop-a'),isNull);
  });

  test('Owner verification fails closed without writing or reading secrets',()async{
    final storage=_MemoryTokenStorage();
    OwnerSessionIdentity? identity=ownerA;
    var allowed=false;
    final access=ReceiptAiGatewayAccess(
      storage:storage,identity:()=>identity,
      verifyOwner:(_)async=>allowed,
    );
    await expectLater(access.saveVerified('shop-a','synthetic-long-token-value'),throwsStateError);
    expect(storage.values,isEmpty);
    await expectLater(access.read('shop-a'),throwsStateError);
    allowed=true;
    identity=null;
    await expectLater(access.read('shop-a'),throwsStateError);
    expect(storage.values,isEmpty);
  });

  test('malformed token is never accepted even for saved Owner',()async{
    final storage=_MemoryTokenStorage();
    final access=ReceiptAiGatewayAccess(
      storage:storage,identity:()=>ownerA,
      verifyOwner:(_)async=>true,
    );
    for(final invalid in [
      '', 'short', 'bad token with spaces',
      'line\\nbreak synthetic token',
    ]){
      await expectLater(access.saveVerified('shop-a',invalid),
        throwsFormatException);
    }
    expect(storage.values,isEmpty);
  });

  test('legacy unscoped gateway credential migrates only for verified Owner',()async{
    final storage=_MemoryTokenStorage();
    storage.values['receipt_ai_gateway_token:shop-a']=
      'synthetic-existing-cloudflare-token';
    var allowed=false;
    final access=ReceiptAiGatewayAccess(
      storage:storage,identity:()=>ownerA,
      verifyOwner:(_)async=>allowed,
    );
    await expectLater(access.read('shop-a'),throwsStateError);
    expect(storage.values.containsKey('receipt_ai_gateway_token:shop-a'),true);
    allowed=true;
    expect(await access.read('shop-a'),'synthetic-existing-cloudflare-token');
    expect(storage.values.containsKey('receipt_ai_gateway_token:shop-a'),false);
    expect(storage.values.values.single,'synthetic-existing-cloudflare-token');
  });

  test('changed Owner session during verification rejects credential access',()async{
    final storage=_MemoryTokenStorage();
    var identity=ownerA;
    final wait=Completer<void>();
    final access=ReceiptAiGatewayAccess(
      storage:storage,identity:()=>identity,
      verifyOwner:(_)async{await wait.future;return true;},
    );
    final pending=access.saveVerified('shop-a','synthetic-long-token-value');
    identity=ownerB;
    wait.complete();
    await expectLater(pending,throwsStateError);
    expect(storage.values,isEmpty);
  });
}
