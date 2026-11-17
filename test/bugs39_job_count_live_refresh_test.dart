import 'dart:async';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline job completion and reopen update the existing badge count stream', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    for (var i = 0; i < 4; i++) {
      await database.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status) "
        "VALUES(?,'shop','owner','Repair','open')", ['job-$i'],
      );
    }
    final jobs = LocalJobRepository(database: database);
    final changes = StreamIterator(jobs.watchActiveJobCount('shop'));
    addTearDown(changes.cancel);
    expect(await changes.moveNext(), isTrue);
    expect(changes.current, 4);
    final admin = OfflineJobAdminService(database: database);
    final completed = changes.moveNext().timeout(const Duration(seconds: 5));
    await admin.queueStatus('shop', 'job-0', code: 'completed', name: 'Completed');
    expect(await completed, isTrue);
    expect(changes.current, 3);
    final reopened = changes.moveNext().timeout(const Duration(seconds: 5));
    await admin.queueStatus('shop', 'job-0', code: 'open', name: 'Open');
    expect(await reopened, isTrue);
    expect(changes.current, 4);
    expect(await jobs.activeJobCount('shop'), 4);
  });
}
