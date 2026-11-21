import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';
import 'package:briskers_app/services/backup/restored_attachment_lookup.dart';
import 'package:briskers_app/services/local_mechanic_work_credit_repository.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/backup/backup_archive.dart';
import 'package:briskers_app/services/backup/expenseiq_originals_import.dart';
import 'package:briskers_app/services/backup/local_backup_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => '$root/cache';
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
    await Directory('${root.path}/cache').create();
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
    await File('${root.path}/backup-restore-request.json')
        .writeAsString(request);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalBackupService.restoreRequest, request);
  });

  tearDown(() async {
    LocalBackupService.debugOwnerAuthorization = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalBackupService.channel, null);
    debugUseLocalDatabase(null);
    await database.close();
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  test(
    'legacy import preserves newer photos and restores both offline',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Briskers',
        packageName: 'com.briskers.briskers_app',
        version: '0.10.9',
        buildNumber: '4772',
        buildSignature: '',
      );
      String legacyUri(String path, {String folder = 'photos'}) => Uri(
        scheme: 'content',
        host: 'com.android.externalstorage.documents',
        pathSegments: ['document', 'primary:ExpenseIQ/$folder/$path'],
      ).toString();
      final current = File('${root.path}/briskers_media/current.jpg');
      await current.parent.create(recursive: true);
      await current.writeAsBytes([1, 2, 3]);
      Future<void> link(String id, String? uri) => database.customStatement(
        'INSERT INTO local_expense_iq_photos '
        '(business_id, transaction_id, photo_id, filename, source_uri, state, updated_at) '
        "VALUES ('shop', ?, 'receipt', 'receipt.jpg', ?, 'uploaded', 1)",
        [id, uri],
      );
      await link('old', legacyUri('receipt.jpg', folder: 'Photos'));
      await link('new', current.uri.toString());
      await link('unmatched', legacyUri('absent/receipt.jpg'));
      final fixtures = {
        legacyUri('receipt.jpg'): [4, 5, 6],
        legacyUri('extra/receipt.jpg'): [7, 8, 9],
        legacyUri('duplicate.jpg'): [4, 5, 6],
        legacyUri('unreadable.jpg'): <int>[],
      };
      final media = Directory(
        '${root.path}/briskers_media/expenseiq_originals',
      );
      final scratch = await Directory('${root.path}/cache').createTemp();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var copies = 0;
      messenger.setMockMethodCallHandler(LocalBackupService.channel, (
        call,
      ) async {
        if (call.method == 'listExpenseIqOriginals') {
          return [
            for (final entry in fixtures.entries)
              {
                'path': Uri.parse(entry.key).pathSegments.last
                    .substring('primary:ExpenseIQ/photos/'.length),
                'uri': entry.key,
                'size': entry.value.length,
                'modified': 1,
              },
          ];
        }
        if (call.method == 'copyExpenseIqOriginal') {
          copies++;
          final args = call.arguments as Map;
          final bytes = fixtures[args['uri']]!;
          if (bytes.isEmpty) throw PlatformException(code: 'unreadable');
          final target = await File(args['destination'] as String)
              .writeAsBytes(bytes);
          return BackupArchive.digest(target);
        }
        throw StateError('Unexpected channel operation ${call.method}');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          LocalBackupService.channel,
          null,
        ),
      );
      final importer = ExpenseIqOriginalsImport(
        database,
        media,
        scratch,
        LocalBackupService.channel,
      );
      final first = await importer.run('shop', 'test-tree', (_) {});
      expect(first, (
        scanned: 4,
        copied: 2,
        reused: 1,
        unreadable: 1,
        linked: 1,
        outstanding: 1,
      ));
      final second = await importer.run('shop', 'test-tree', (_) {});
      expect(second, (
        scanned: 4,
        copied: 0,
        reused: 3,
        unreadable: 1,
        linked: 0,
        outstanding: 1,
      ));
      expect(copies, 5);
      expect(await media.list().length, 2);
      var reader = ExpenseIqLocalPhotoSync(database: database);
      expect(
        (await reader.localForExpense('shop', 'new'))?['source_uri'],
        current.uri.toString(),
      );
      expect(
        (await reader.localForExpense('shop', 'old'))?['state'],
        'uploaded',
      );
      expect(
        (await reader.localForExpense('shop', 'unmatched'))?['source_uri'],
        legacyUri('absent/receipt.jpg'),
      );
      // Remove the deliberately unresolved legacy test link so the remaining
      // backup can be verified without the external folder or its SAF grant.
      await database.customStatement(
        "DELETE FROM local_expense_iq_photos WHERE transaction_id='unmatched'",
      );
      final export = Directory(
        '${root.path}/backup-review-photo-export/import',
      );
      await export.create(recursive: true);
      final manifest = await LocalBackupService.snapshot('shop', export);
      final sources = manifest['source_files'] as Map;
      expect(sources[current.path], sources[current.uri.toString()]);
      final restored = await BackupArchive.restoreTo(
        export,
        Directory('${root.path}/restored-backup-photo-test'),
        businessId: 'shop',
      );
      await media.delete(recursive: true);
      await current.delete();
      final restoredDb = BriskersLocalDatabase(NativeDatabase(restored));
      addTearDown(restoredDb.close);
      reader = ExpenseIqLocalPhotoSync(database: restoredDb);
      Future<List<int>> read(String id) async {
        final photo = (await reader.localForExpense('shop', id))!;
        return reader.readOriginalPhoto(
          'shop',
          id,
          photo,
          reader: (_) async =>
              throw StateError('External folder is unavailable'),
        );
      }

      expect(await read('old'), [4, 5, 6]);
      expect(await read('new'), [1, 2, 3]);
      final unlinked = await restoredDb
          .customSelect(
            "SELECT file_uri FROM local_expense_iq_imported_files WHERE relative_path='extra/receipt.jpg'",
          )
          .getSingle();
      expect(
        await File.fromUri(Uri.parse(unlinked.read<String>('file_uri')))
            .readAsBytes(),
        [7, 8, 9],
      );
    },
  );

  test('startup restores records atomically, retains safety snapshot and forces offline', () async {
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
  });

  test(
    'damaged backup refuses replacement and retains current records',
    () async {
      await File('${source.path}/Settings/preferences.json')
          .writeAsString('damaged');
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

  test('restart after committed SQL does not restore or duplicate payments twice', () async {
    await LocalBackupService.applyRequestedRestore();
    await database.customStatement(
      "UPDATE local_customers SET display_name='After committed restore'",
    );
    // Simulate a crash after the SQLite commit but before clearing the request.
    await File('${root.path}/backup-restore-request.json')
        .writeAsString(request);
    await LocalBackupService.applyRequestedRestore();
    expect(
      (await database
              .customSelect('SELECT display_name FROM local_customers')
              .getSingle())
          .read<String>('display_name'),
      'After committed restore',
    );
    expect(
      (await database.customSelect('SELECT * FROM backup_fixture_ledger').get())
          .length,
      1,
    );
    expect(await Directory('${root.path}/backup-safety').list().length, 1);
  });
  test('complete service snapshot copies owned photos and reports missing originals', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Briskers',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: 'test',
    );
    final photo = File('${root.path}/briskers_media/shop/expenses/receipt.jpg');
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
  });

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

  test('cancel requested restore leaves current records and every source file intact', () async {
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
  });
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
  test('runtime tables first created after the backup do not block older compatible restore', () async {
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
  });
  test('customer-note originals referenced only in preferences are copied and relocated', () async {
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
    expect((manifest['source_files'] as Map).containsKey(original.path), true);
    final restored = Directory('${root.path}/notes-restored');
    await BackupArchive.restoreTo(folder, restored, businessId: 'shop');
    final settings = jsonDecode(
      await File('${restored.path}/Settings/preferences.json').readAsString(),
    ) as Map;
    final notes = jsonDecode(settings[key] as String) as Map;
    final restoredPath =
        (notes['attachments'] as List).single['local_file_path'] as String;
    expect(restoredPath, startsWith(restored.path));
    expect(await File(restoredPath).readAsBytes(), [7, 5, 3, 1]);
  });
  test(
    'restored external receipts stay readable without the old folder grant',
    () async {
      const content = 'content://old-device-grant/receipt.jpg';
      final manifest = jsonDecode(
        await File('${source.path}/backup-info.json').readAsString(),
      ) as Map;
      await Directory('${source.path}/Receipts').create();
      await File('${source.path}/Receipts/original.jpg')
          .writeAsBytes([255, 216, 255, 219, 1]);
      final sourceDb = sqlite3.open(
        '${source.path}/Database/briskers_local.sqlite',
      );
      sourceDb.execute('INSERT INTO backup_fixture_ledger VALUES(?,?,?,?)', [
        'receipt-link',
        0,
        0,
        jsonEncode({'source_uri': content}),
      ]);
      sourceDb.close();
      await BackupArchive.seal(
        source,
        businessId: 'shop',
        appVersion: 'test',
        sourceFiles: {
          ...(manifest['source_files'] as Map).cast<String, String>(),
          content: 'Receipts/original.jpg',
        },
        warnings: [],
      );
      final target = Directory('${root.path}/uri-restored');
      final restored = await BackupArchive.restoreTo(
        source,
        target,
        businessId: 'shop',
      );
      final db = sqlite3.open(restored.path);
      final payload = jsonDecode(
        db
                .select(
                  "SELECT payload FROM backup_fixture_ledger WHERE id='receipt-link'",
                )
                .single['payload']
            as String,
      ) as Map;
      db.close();
      final uri = payload['source_uri'] as String;
      expect(Uri.parse(uri).scheme, 'file');
      final bytes = await ExpenseIqLocalPhotoSync(database: database)
          .readOriginalPhoto(
            'shop',
            'receipt-transaction',
            {'filename': 'receipt.jpg', 'source_uri': uri},
            reader: (_) async =>
                throw StateError('External folder permission is unavailable'),
          );
      expect(bytes, [255, 216, 255, 219, 1]);
    },
  );
  Future<void> copyFolder(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final item in from.list(recursive: true, followLinks: false)) {
      final relative = item.path.substring(from.path.length + 1);
      if (item is Directory) {
        await Directory('${to.path}/$relative').create(recursive: true);
      } else if (item is File) {
        final target = File('${to.path}/$relative');
        await target.parent.create(recursive: true);
        await item.copy(target.path);
      }
    }
  }

  test('Create Backup uses a real temporary directory and saves a verified external copy', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Briskers',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: 'test',
    );
    var authorizations = 0;
    LocalBackupService.debugOwnerAuthorization = (business) async {
      expect(business, 'shop');
      authorizations++;
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      LocalBackupService.rootKey,
      'content://selected-backup-parent',
    );
    Directory? exported;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalBackupService.channel, (call) async {
          expect(call.method, 'exportFolder');
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          final staged = Directory(arguments['source'] as String);
          expect(await staged.exists(), true);
          expect(
            staged.path,
            startsWith('${root.path}/cache/briskers-backup-'),
          );
          await BackupArchive.verify(staged, businessId: 'shop');
          exported = Directory('${root.path}/external/${arguments['name']}');
          await copyFolder(staged, exported!);
          await BackupArchive.verify(exported!, businessId: 'shop');
          return 'content://verified-dated-backup';
        });
    final status = await LocalBackupService.create('shop');
    expect(status['complete'], true);
    expect(authorizations, 1);
    expect(prefs.getString(LocalBackupService.statusKey), isNotNull);
    expect(await Directory('${root.path}/cache').list().isEmpty, true);
    expect(await exported!.exists(), true);
  });

  test(
    'failed export preserves the earlier backup and permits retries',
    () async {
      LocalBackupService.debugOwnerAuthorization = (_) async {};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalBackupService.rootKey,
        'content://selected-folder',
      );
      final dates = <String>[];
      final exported = Directory('${root.path}/last-valid');
      var attempt = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalBackupService.channel, (call) async {
            expect(call.method, 'exportFolder');
            final args = call.arguments as Map;
            dates.add(args['name'] as String);
            switch (++attempt) {
              case 1:
                await copyFolder(Directory(args['source'] as String), exported);
                return 'content://last-valid';
              case 2:
                throw PlatformException(
                  code: 'folder_permission',
                  message:
                      'Android access was revoked. Select the folder again.',
                );
              case 3:
                throw PlatformException(
                  code: 'backup_failed',
                  message: 'File transfer was interrupted.',
                );
              default:
                return 'content://verified-new-backup';
            }
          });

      await LocalBackupService.create('shop');
      final previousStatus = prefs.getString(LocalBackupService.statusKey);
      for (final code in ['folder_permission', 'backup_failed']) {
        await expectLater(
          LocalBackupService.create('shop'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
        expect(prefs.getString(LocalBackupService.statusKey), previousStatus);
        expect(await Directory('${root.path}/cache').list().isEmpty, true);
        expect((await BackupArchive.verify(exported))['complete'], true);
      }
      expect(
        (await LocalBackupService.create('shop'))['folder'],
        'content://verified-new-backup',
      );
      expect(dates.toSet(), hasLength(4));
      expect((await BackupArchive.verify(exported))['complete'], true);
    },
  );

  test('restore selection creates a staging folder and verifies an isolated restore', () async {
    LocalBackupService.debugOwnerAuthorization = (_) async {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalBackupService.channel, (call) async {
          if (call.method == 'pickRestoreFolder') {
            return 'content://selected-dated-backup';
          }
          expect(call.method, 'importFolder');
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          await copyFolder(
            source,
            Directory(arguments['destination'] as String),
          );
          return null;
        });
    final inspected = await LocalBackupService.inspect('shop');
    expect(inspected, isNotNull);
    expect(inspected!.path, startsWith('${root.path}/backup-review-'));
    expect(
      await File(
        '${inspected.parent.path}/Restored/Database/briskers_local.sqlite',
      ).exists(),
      true,
    );
    expect(
      (await database
              .customSelect('SELECT display_name FROM local_customers')
              .getSingle())
          .read<String>('display_name'),
      'Current Customer',
    );
  });

  test(
    'interrupted restore import clears staging and permits a later backup',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Briskers',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: 'test',
      );
      LocalBackupService.debugOwnerAuthorization = (_) async {};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalBackupService.rootKey,
        'content://selected-backup-parent',
      );
      String? failedStaging;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalBackupService.channel, (call) async {
            if (call.method == 'pickRestoreFolder') {
              return 'content://selected-dated-backup';
            }
            if (call.method == 'importFolder') {
              failedStaging = (call.arguments as Map)['destination'] as String;
              await Directory(failedStaging!).create(recursive: true);
              throw PlatformException(code: 'copy_interrupted');
            }
            expect(call.method, 'exportFolder');
            return 'content://verified-retry-backup';
          });
      await expectLater(
        LocalBackupService.inspect('shop'),
        throwsA(isA<PlatformException>()),
      );
      expect(await Directory(failedStaging!).parent.exists(), false);
      expect((await LocalBackupService.create('shop'))['complete'], true);
    },
  );
}
