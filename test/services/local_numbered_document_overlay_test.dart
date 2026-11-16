import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_numbered_document_overlay.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());
  test('offline detail uses assigned number and preserves original lines/payments',() async {
    await db.customStatement(
      """INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number)
         VALUES('job-a','shop','full','Test','open','J-42')""");
    await db.customStatement(
      """INSERT INTO local_documents(id,business_id,job_id,kind,status,
         display_status_code,document_number,sync_state,total)
         VALUES('invoice-a','shop','job-a','invoice','issued','open','8200','pending',100)""");
    final original=<String,dynamic>{
      'id':'invoice-a','document_number':null,'job_number':'TEMP-1',
      'lines':[{'name':'Synthetic item','quantity':2}],
      'payments':[{'operation_id':'local-test','amount':30}],
      'total_amount':100.0,
    };
    final displayed=await LocalNumberedDocumentOverlay(database:db)
      .apply('shop','invoice-a',original);
    expect(displayed['document_number'],'8200');
    expect(displayed['job_number'],'J-42');
    expect(displayed['display_status'],'Open');
    expect(displayed['lines'],original['lines']);
    expect(displayed['payments'],original['payments']);
    expect(displayed['total_amount'],100);
    expect(original['document_number'],null);
  });
  test('no assigned number leaves cached local invoice unchanged',() async {
    final original=<String,dynamic>{'id':'missing','lines':[],'document_number':null};
    expect(await LocalNumberedDocumentOverlay(database:db)
      .apply('shop','missing',original),same(original));
  });
}
