import 'package:briskers_app/screens/jobs/offline_job_purge_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('item labels show invoice estimate and payment amount with method',() {
    expect(offlinePurgeItemLabel({'kind':'local_documents','label':'I-23','document_kind':'invoice'}),'Invoice I-23');
    expect(offlinePurgeItemLabel({'kind':'local_documents','label':'E-7','document_kind':'estimate'}),'Estimate E-7');
    expect(offlinePurgeItemLabel({'kind':'payment','label':'Queued payment','amount_cents':12345,'method_name':'Cash','currency':'USD'}),'Queued payment · USD 123.45 · Cash');
  });
  testWidgets('one explicit irreversible action follows itemized local preview',(tester) async {
    bool? accepted;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:() async {
      accepted=await showOfflineJobPurgeConfirmation(context,jobLabel:'J-draft',items:[
        {'kind':'local_documents','document_kind':'invoice','label':'I-draft'},
        {'kind':'payment','label':'Queued payment','amount_cents':5000,'method_name':'Cash'}]);
    },child:const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    expect(find.text('Permanently delete J-draft?'),findsOneWidget);
    expect(find.text('Invoice I-draft'),findsOneWidget);
    expect(find.textContaining('50.00 · Cash'),findsOneWidget);
    expect(accepted,isNull);
    await tester.tap(find.text('Permanently delete these records')); await tester.pumpAndSettle();
    expect(accepted,isTrue);
  });
}
