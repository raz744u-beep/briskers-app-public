import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_work_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved labor requires the exact shop, job and active assignment',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('payroll-source-');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
      await directory.delete(recursive: true);
    });
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs (id, business_id, access_scope, title, status) "
      "VALUES ('job-a', 'shop-a', 'owner', 'Repair', 'open')",
    );
    await db.customStatement(
      "INSERT INTO local_documents (id, business_id, job_id, kind) "
      "VALUES ('invoice-a', 'shop-a', 'job-a', 'invoice')",
    );
    await db.customStatement(
      "INSERT INTO local_job_assignments "
      "(assignment_id, business_id, job_id, employee_id) "
      "VALUES ('assignment-a', 'shop-a', 'job-a', 'employee-a')",
    );
    final cache = LocalDocumentDetailCache(database: db);
    await cache.save('shop-a', 'invoice-a', {
      'id': 'invoice-a',
      'kind': 'invoice',
      'job_id': 'job-a',
      'lines': [
        {'id': 'labor-a', 'line_kind': 'labor', 'description': 'Repair'},
        {'id': 'part-a', 'line_kind': 'part', 'name': 'Labor'},
        {'id': 'ambiguous', 'line_kind': 'labor'},
        {'id': 'ambiguous', 'line_kind': 'part'},
      ],
    });
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));

    final source = LocalPayrollWorkSource(db);
    Future<Map<String, dynamic>?> resolve({
      String business = 'shop-a',
      String job = 'job-a',
      String employee = 'employee-a',
      String line = 'labor-a',
    }) =>
        source.resolve(
          businessId: business,
          jobId: job,
          invoiceId: 'invoice-a',
          lineId: line,
          employeeId: employee,
        );

    expect((await resolve())?['description'], 'Repair');
    expect(await resolve(business: 'shop-b'), isNull);
    expect(await resolve(job: 'job-b'), isNull);
    expect(await resolve(employee: 'employee-b'), isNull);
    expect(await resolve(line: 'part-a'), isNull);
    expect(await resolve(line: 'ambiguous'), isNull);

    await db.customStatement(
      "UPDATE local_job_assignments SET active = 0 "
      "WHERE assignment_id = 'assignment-a'",
    );
    expect(await resolve(), isNull);
  });
}
