import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/job_expense_access.dart';
import 'package:briskers_app/services/local_job_profitability.dart';
import 'package:briskers_app/widgets/job_expense_actions.dart';
import 'package:briskers_app/widgets/local_job_profitability_view.dart';

void main() {
  test('local expense permission is independent of online-only job administration', () {
    bool access(String role, {bool verified = true, bool preview = false, bool blocked = false}) =>
      canRecordJobExpense(role:role,onlineManage:false,localVerified:verified,
        firstFrameOnly:preview,contentBlocked:blocked);
    for (final role in ['owner','manager','office']) {
      expect(access(role), isTrue);
      expect(access(role,verified:false), isFalse);
      expect(access(role,preview:true), isFalse);
      expect(access(role,blocked:true), isFalse);
    }
    expect(access('mechanic'), isFalse);
    expect(access('porter'), isFalse);
  });

  testWidgets('J-61 empty expense panel always exposes usable Add Expense', (t) async {
    var added = 0, quick = 0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Column(children:[
      JobExpenseActions(onAdd:()=>added++,onQuick:()=>quick++),
      const Text('No expenses are linked to this job yet.'),
    ]))));
    expect(find.byKey(const Key('add-job-expense')).hitTestable(), findsOneWidget);
    await t.tap(find.byKey(const Key('add-job-expense')));
    await t.tap(find.byKey(const Key('quick-job-expense')));
    expect(added, 1); expect(quick, 1);
    expect(t.takeException(), isNull);
  });

  for (final width in [390.0,320.0]) {
    testWidgets('offline profitability shows known amounts and identifies missing cost at $width width', (t) async {
      t.view.physicalSize=Size(width,900); t.view.devicePixelRatio=1;
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(home:Scaffold(body:MediaQuery(
        data:const MediaQueryData(textScaler:TextScaler.linear(2)),
        child:SingleChildScrollView(child:LocalJobProfitabilityView(
          report:const LocalJobProfitability(
            revenueCents:100000,taxCents:8000,directCents:25000,laborCents:null,
            expenses:[],issues:['Completed labor is missing a saved hourly cost.']),
          onExpense:(_){},
        )),
      ))));
      expect(t.widget<Text>(find.byKey(const ValueKey('local-job-revenue'))).data, r'$1,000.00');
      expect(t.widget<Text>(find.byKey(const ValueKey('local-job-profit'))).data, 'Not saved');
      expect(find.textContaining('Go online'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  test('actual Job route uses local report and scoped expense actions without an RPC dependency', () {
    final source=File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(source, contains('LocalJobProfitabilityRepository(localDatabase).load('));
    expect(source, isNot(contains('_api.jobProfitability(')));
    expect(source, contains("if (key == 'expenses' && _canRecordJobExpense)"));
    final add=source.split('Future<void> _addJobExpense()').last.split('Future<void> _addQuickJobExpense()').first;
    expect(add, contains('jobId: _jobId'));
    expect(add, isNot(contains('_onlineReady')));
  });
}
