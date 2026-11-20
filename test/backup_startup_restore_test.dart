import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/backup/backup_archive.dart';
import 'package:briskers_app/services/backup/local_backup_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
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
    await database.customStatement('VACUUM INTO ?', [
      '${source.path}/Database/briskers_local.sqlite',
    ]);
    await BackupArchive.seal(
      source,
      businessId: 'shop',
      appVersion: 'test',
      sourceFiles: {},
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
}
