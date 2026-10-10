import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('linked estimates show Job number offline; standalone estimates do not',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    const business = 'estimate-job-test';
    final repo = LocalDocumentRepository(database: db);
    try {
      await db.customStatement(
        """INSERT INTO local_jobs(
          id,business_id,access_scope,job_number,title,status,status_name,
          sync_state
        ) VALUES ('job-1',?,'all','J-42','Service','open','In progress','synced')""",
        [business],
      );
      await repo.upsertFromServer(business, [
        {
          'id':'estimate-linked','kind':'estimate','document_number':'101',
          'job_id':'job-1','status':'draft','total_amount':50,
        },
        {
          'id':'estimate-standalone','kind':'estimate','document_number':'102',
          'job_id':null,'status':'draft','total_amount':80,
        }
      ]);
      final before = await repo.listByKind(business, kind:'estimate');
      expect(before.singleWhere((d)=>d['id']=='estimate-linked')['job_number'],
          'J-42');
      expect(before.singleWhere((d)=>d['id']=='estimate-standalone')['job_number'],
          isNull);

      // Conversion/linkage update must also refresh the local index.
      await repo.upsertFromServer(business, [
        {
          'id':'estimate-standalone','kind':'estimate','document_number':'102',
          'job_id':'job-1','status':'issued','total_amount':80,
        }
      ]);
      final after = await repo.listByKind(business, kind:'estimate');
      expect(after.singleWhere((d)=>d['id']=='estimate-standalone')['job_number'],
          'J-42');
    } finally {
      await db.close();
    }
  });
}
