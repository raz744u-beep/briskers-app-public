import 'dart:async';
import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/payroll/owner_payroll_screen.dart';
import 'package:briskers_app/screens/payroll/payroll_ui_scope.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';
import 'package:briskers_app/services/payroll_owner_lan.dart';

class _Unused implements OwnerEnrollmentStore{
  @override Future<String?> read()async=>null;
  @override Future<void> write(String value)async{}
  @override Future<void> clear()async{}
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  for(final slow in [false,true]){
    testWidgets('profile keeps evenly spaced tabs usable without view unlock through slow DB and payment-grant expiry, slow=$slow',(tester)async{
      SharedPreferences.setMockInitialValues({});FlutterSecureStorage.setMockInitialValues({});
      final gate=Completer<void>();
      if(!slow)gate.complete();
      final db=BriskersLocalDatabase(LazyDatabase(()async{await gate.future;return NativeDatabase.memory();}));
      var clock=DateTime.now();
      const who=OwnerSessionIdentity('owner','local');
      final auth=LocalOwnerAuthorization(store:_Unused(),currentIdentity:()=>who,
        verifyOwner:(_)async=>throw StateError('No internet'),authenticateDevice:()async=>true,
        verifyLocalOwner:(shop)async=>VerifiedOwnerEnrollment(who,shop),now:()=>clock);
      final id=await PayrollLanIdentity.fromSeed(List.filled(32,3));
      final values=<String,String>{};
      final lease=PayrollOwnerLease(identity:id,business:'shop',anchor:id.deviceId,
        read:(k)async=>values[k],write:(k,v)async{values[k]=v;});
      final network=PayrollOwnerLan(lease:lease,database:db,actor:'owner',approve:(_)async=>null);
      addTearDown(()async{if(!gate.isCompleted)gate.complete();await network.close();await db.close();});
      await tester.pumpWidget(MaterialApp(home:PayrollUiScope(database:db,
        unlock:auth.authorizeLocal,connection:network,debugAllowOwnerView:true,
        child:OwnerPayrollScreen(businessId:'shop',employeeId:'a',
          employeeName:'Known Employee',employeeRole:'Mechanic',
          database:db,unlockOwner:auth.authorizeLocal,ownerConnection:network))));
      for(final name in ['Tasks','Payroll','Reports','Taxes']){expect(find.text(name),findsOneWidget);}
      final x=[for(final name in ['Tasks','Payroll','Reports','Taxes'])tester.getCenter(find.text(name)).dx];
      expect(x[1]-x[0],closeTo(x[2]-x[1],1));expect(x[2]-x[1],closeTo(x[3]-x[2],1));
      await tester.tap(find.text('Taxes'));await tester.pumpAndSettle();
      expect(find.textContaining('1099'),findsWidgets);
      // View-only navigation never challenges the OS or expires after 2 min.
      expect(find.text('Unlock Owner payroll'),findsNothing);
      await tester.tap(find.text('Reports'));await tester.pumpAndSettle();
      if(slow){
        await tester.pump(const Duration(seconds:9));
        expect(find.textContaining('taking longer'),findsWidgets);
        await tester.tap(find.text('Tasks'));await tester.pumpAndSettle();
        gate.complete();
        await tester.tap(find.text('Retry'));await tester.pump();
      }
      for(var i=0;i<35;i++){
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));
        await tester.pump();
      }
      clock=clock.add(const Duration(minutes:3));
      await tester.pump(const Duration(seconds:6));
      expect(find.text('Unlock Owner payroll'),findsNothing);
      await tester.tap(find.text('Taxes'));await tester.pumpAndSettle();
      expect(find.textContaining('1099'),findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());await tester.pump();
      expect(tester.takeException(),isNull);
    });
  }
}
