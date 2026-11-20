import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:briskers_app/services/backup/restored_attachment_lookup.dart';
import 'package:briskers_app/services/local_mechanic_work_credit_repository.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/backup/backup_archive.dart';
import 'package:briskers_app/services/backup/local_backup_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, source;
  late BriskersLocalDatabase database;
  late PathProviderPlatform previousPaths;
  late String request;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'briskers_language_code': 'en',
      'keep_auth_token': 'device-only',
    });
    root = await Directory.systemTemp.createTemp('briskers-startup-restore-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    database = BriskersLocalDatabase(
      NativeDatabase(File('${root.path}/live.sqlite')),
    );
    debugUseLocalDatabase(database);
    await database.customStatement(
      "INSERT INTO local_customers(id,business_id,display_name) VALUES('c','shop','Backup Customer')",
    );
    await database.customStatement(
      'CREATE TABLE backup_fixture_ledger(id TEXT PRIMARY KEY,paid INTEGER,amount INTEGER,payload TEXT)',
    );
    await database.customStatement(
      "INSERT INTO backup_fixture_ledger VALUES('same-payment',1,48000,'{}')",
    );
    await LocalMechanicWorkCreditRepository(database: database).prepare();
    await LocalJobDeletionV3.ensureSchema(database);
    await database.customStatement(
      "INSERT INTO local_job_deletion_v3_entities VALUES('shop','deleted-job','verified-delete','job','deleted-job')",
    );
    await database.customStatement(
      "INSERT INTO local_mechanic_work_credits_v1(business_id,allocation_id,job_id,labor_line_id,task_id,employee_id,actual_minutes,rate_cents,completed,paid_operation_id) VALUES('shop','paid-allocation','job','line','task','mechanic',120,4000,1,'paid-operation')",
    );
    final paidProof = File(
      '${root.path}/briskers_media/shop/payroll/proof.jpg',
    );
    await paidProof.parent.create(recursive: true);
    await paidProof.writeAsBytes([2, 4, 6]);
    await database.customStatement(
      'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
      [
        'shop',
        'paid-allocation',
        'paid-operation',
        120,
        8000,
        jsonEncode({'proof': paidProof.path}),
      ],
    );
    await database.customStatement(
      'CREATE INDEX backup_fixture_paid_index ON backup_fixture_ledger(paid)',
    );
    await database.customStatement(
      'CREATE VIEW backup_fixture_paid_view AS SELECT * FROM backup_fixture_ledger WHERE paid=1',
    );
    source = Directory('${root.path}/backup-review-fixture/import');
    await Directory('${source.path}/Database').create(recursive: true);
    await Directory('${source.path}/Settings').create();
    await File('${source.path}/Settings/preferences.json').writeAsString(
      jsonEncode({
        'briskers_language_code': 'es',
        'briskers_connection_mode': 'auto',
        'keep_auth_token': 'never-restore',
      }),
    );
    await Directory('${source.path}/Photos').create();
    await paidProof.copy('${source.path}/Photos/paid-proof.jpg');
    await database.customStatement('VACUUM INTO ?', [
      '${source.path}/Database/briskers_local.sqlite',
    ]);
    await BackupArchive.seal(
      source,
      businessId: 'shop',
      appVersion: 'test',
      sourceFiles: {paidProof.path: 'Photos/paid-proof.jpg'},
      warnings: [],
    );
    await database.customStatement(
      "UPDATE local_customers SET display_name='Current Customer'",
    );
    await database.customStatement(
      "INSERT INTO backup_fixture_ledger VALUES('new-current-record',0,100,'{}')",
    );
    request = jsonEncode({'business': 'shop', 'source': source.path});
    await File(
      '${root.path}/backup-restore-request.json',
    ).writeAsString(request);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalBackupService.restoreRequest, request);
  });

  tearDown(() async {
    debugUseLocalDatabase(null);
    await database.close();
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test(
    'startup restores records atomically, retains safety snapshot and forces offline',
    () async {
      await LocalBackupService.applyRequestedRestore();
      expect(
        (await database
                .customSelect('SELECT display_name FROM local_customers')
                .getSingle())
            .read<String>('display_name'),
        'Backup Customer',
      );
      final payments = await database
          .customSelect('SELECT * FROM backup_fixture_ledger')
          .get();
      expect(payments.length, 1);
      expect(payments.single.read<String>('id'), 'same-payment');
      expect(payments.single.read<int>('paid'), 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('briskers_connection_mode'), 'offline');
      expect(prefs.getString('briskers_language_code'), 'es');
      expect(prefs.getString('keep_auth_token'), 'device-only');
      expect(
        await File('${root.path}/backup-restore-request.json').exists(),
        false,
      );
      expect(await Directory('${root.path}/backup-safety').list().length, 1);
    },
  );

  test(
    'damaged backup refuses replacement and retains current records',
    () async {
      await File(
        '${source.path}/Settings/preferences.json',
      ).writeAsString('damaged');
      await expectLater(
        LocalBackupService.applyRequestedRestore(),
        throwsStateError,
      );
      expect(
        (await database
                .customSelect('SELECT display_name FROM local_customers')
                .getSingle())
            .read<String>('display_name'),
        'Current Customer',
      );
      expect(
        (await database
                .customSelect('SELECT * FROM backup_fixture_ledger')
                .get())
            .length,
        2,
      );
    },
  );

  test(
    'restart after committed SQL does not restore or duplicate payments twice',
    () async {
      await LocalBackupService.applyRequestedRestore();
      await database.customStatement(
        "UPDATE local_customers SET display_name='After committed restore'",
      );
      // Simulate a crash after the SQLite commit but before clearing the request.
      await File(
        '${root.path}/backup-restore-request.json',
      ).writeAsString(request);
      await LocalBackupService.applyRequestedRestore();
      expect(
        (await database
                .customSelect('SELECT display_name FROM local_customers')
                .getSingle())
            .read<String>('display_name'),
        'After committed restore',
      );
      expect(
        (await database
                .customSelect('SELECT * FROM backup_fixture_ledger')
                .get())
            .length,
        1,
      );
      expect(await Directory('${root.path}/backup-safety').list().length, 1);
    },
  );
  test(
    'complete service snapshot copies owned photos and reports missing originals',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Briskers',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: 'test',
      );
      final photo = File(
        '${root.path}/briskers_media/shop/expenses/receipt.jpg',
      );
      await photo.parent.create(recursive: true);
      await photo.writeAsBytes([3, 1, 4, 1, 5]);
      final missing = '${root.path}/missing-receipt.jpg';
      await database.customStatement(
        'UPDATE backup_fixture_ledger SET payload=? WHERE id=?',
        [
          jsonEncode({
            'photos': [photo.path, missing],
          }),
          'same-payment',
        ],
      );
      final snapshot = Directory('${root.path}/snapshot-test');
      await snapshot.create();
      final manifest = await LocalBackupService.snapshot('shop', snapshot);
      expect(manifest['complete'], false);
      expect(
        (manifest['warnings'] as List).any(
          (item) => '$item'.contains('missing-receipt'),
        ),
        true,
      );
      final copied = (manifest['source_files'] as Map)[photo.path] as String;
      expect(copied, startsWith('Receipts/'));
      expect(await File('${snapshot.path}/$copied').readAsBytes(), [
        3,
        1,
        4,
        1,
        5,
      ]);
      await BackupArchive.verify(snapshot, businessId: 'shop');
    },
  );

  test(
    'cached photo identities survive restore and the next backup generation',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Briskers',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: 'test',
      );
      await Directory('${source.path}/Photos').create(recursive: true);
      await File('${source.path}/Photos/cached.jpg').writeAsBytes([9, 8, 7]);
      const old = '/data/old-phone/files/attachment_cache/findings/abc.jpg';
      await BackupArchive.seal(
        source,
        businessId: 'shop',
        appVersion: 'test',
        sourceFiles: {old: 'Photos/cached.jpg'},
        warnings: [],
      );
      await LocalBackupService.applyRequestedRestore();
      final cached = await RestoredAttachmentLookup.find(
        'attachment_cache/findings/abc.jpg',
      );
      expect(cached, isNotNull);
      expect(await cached!.readAsBytes(), [9, 8, 7]);
      final snapshot = Directory('${root.path}/next-generation');
      await snapshot.create();
      final manifest = await LocalBackupService.snapshot('shop', snapshot);
      final preserved = (manifest['source_files'] as Map)[old] as String;
      expect(await File('${snapshot.path}/$preserved').readAsBytes(), [
        9,
        8,
        7,
      ]);
    },
  );

  test(
    'cancel requested restore leaves current records and every source file intact',
    () async {
      await LocalBackupService.cancelRequestedRestore();
      await LocalBackupService.applyRequestedRestore();
      expect(
        (await database
                .customSelect('SELECT display_name FROM local_customers')
                .getSingle())
            .read<String>('display_name'),
        'Current Customer',
      );
      expect(await File('${source.path}/backup-info.json').exists(), true);
      expect(
        await File('${root.path}/backup-restore-request.json').exists(),
        false,
      );
    },
  );
  test(
    'real paid-work guards, indexes and views survive full restoration',
    () async {
      await expectLater(
        database.customStatement("DELETE FROM regular_payroll_work_coverage"),
        throwsA(anything),
      );
      await LocalBackupService.applyRequestedRestore();
      final row = await database
          .customSelect('SELECT * FROM regular_payroll_work_coverage')
          .getSingle();
      expect(row.read<String>('operation_id'), 'paid-operation');
      expect(row.read<int>('amount'), 8000);
      final proof =
          (jsonDecode(row.read<String>('snapshot')) as Map)['proof'] as String;
      expect(proof, contains('restored-backup-'));
      expect(await File(proof).readAsBytes(), [2, 4, 6]);
      await expectLater(
        database.customStatement("DELETE FROM regular_payroll_work_coverage"),
        throwsA(anything),
      );
      await expectLater(
        database.customStatement(
          "UPDATE local_mechanic_work_credits_v1 SET actual_minutes=0",
        ),
        throwsA(anything),
      );
      expect(
        (await database
                .customSelect('SELECT * FROM backup_fixture_paid_view')
                .get())
            .length,
        1,
      );
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='index' AND name='backup_fixture_paid_index'",
                )
                .get())
            .length,
        1,
      );
    },
  );
  test(
    'verified deletion history and its no-delete guards survive restoration',
    () async {
      await LocalBackupService.applyRequestedRestore();
      final markers = await database
          .customSelect('SELECT * FROM local_job_deletion_v3_entities')
          .get();
      expect(markers.length, 1);
      expect(markers.single.read<String>('entity_id'), 'deleted-job');
      expect(markers.single.read<String>('operation_id'), 'verified-delete');
      await expectLater(
        database.customStatement('DELETE FROM local_job_deletion_v3_entities'),
        throwsA(anything),
      );
    },
  );
  test(
    'runtime tables first created after the backup do not block older compatible restore',
    () async {
      await database.customStatement(
        'CREATE TABLE later_runtime(id TEXT PRIMARY KEY)',
      );
      await database.customStatement(
        "INSERT INTO later_runtime VALUES('after-backup')",
      );
      await database.customStatement(
        "CREATE TRIGGER later_runtime_no_delete BEFORE DELETE ON later_runtime BEGIN SELECT RAISE(ABORT,'immutable'); END",
      );
      await LocalBackupService.applyRequestedRestore();
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE name='later_runtime'",
                )
                .get())
            .isEmpty,
        true,
      );
      expect(
        (await database
                .customSelect('SELECT * FROM regular_payroll_work_coverage')
                .get())
            .length,
        1,
      );
    },
  );
  test(
    'customer-note originals referenced only in preferences are copied and relocated',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Briskers',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: 'test',
      );
      final external = await Directory.systemTemp.createTemp(
        'briskers-external-note-',
      );
      addTearDown(() => external.delete(recursive: true));
      final original = File('${external.path}/note-original.bin');
      await original.writeAsBytes([7, 5, 3, 1]);
      const key = 'briskers_customer_section_shop_customer_notes';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'attachments': [
            {'local_file_path': original.path},
          ],
        }),
      );
      final folder = Directory('${root.path}/notes-snapshot');
      await folder.create();
      final manifest = await LocalBackupService.snapshot('shop', folder);
      expect(
        (manifest['source_files'] as Map).containsKey(original.path),
        true,
      );
      final restored = Directory('${root.path}/notes-restored');
      await BackupArchive.restoreTo(folder, restored, businessId: 'shop');
      final settings =
          jsonDecode(
                await File(
                  '${restored.path}/Settings/preferences.json',
                ).readAsString(),
              )
              as Map;
      final notes = jsonDecode(settings[key] as String) as Map;
      final restoredPath =
          (notes['attachments'] as List).single['local_file_path'] as String;
      expect(restoredPath, startsWith(restored.path));
      expect(await File(restoredPath).readAsBytes(), [7, 5, 3, 1]);
    },
  );
}
