import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:briskers_app/services/backup/backup_archive.dart';
import 'package:briskers_app/services/backup/local_backup_service.dart';

void main() {
  late Directory root, backup;
  late String original, contentUri;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('briskers-backup-test-');
    backup = Directory('${root.path}/snapshot');
    await Directory('${backup.path}/Database').create(recursive: true);
    await Directory('${backup.path}/Settings').create();
    await Directory('${backup.path}/Originals').create();
    original = '${root.path}/receipt.jpg';
    contentUri = 'content://receipts/original-5';
    await File('${backup.path}/Originals/file-0').writeAsBytes([1, 2, 3]);
    await File('${backup.path}/Originals/file-1').writeAsBytes([4, 5, 6]);
    await File('${backup.path}/Settings/preferences.json').writeAsString('{}');
    final db = sqlite3.open('${backup.path}/Database/briskers_local.sqlite');
    db.execute('PRAGMA user_version=7');
    db.execute(
      'CREATE TABLE invoices(id TEXT PRIMARY KEY,status TEXT,total INTEGER)',
    );
    db.execute("INSERT INTO invoices VALUES ('6359','Closed',788211)");
    db.execute(
      'CREATE TABLE payments(id TEXT PRIMARY KEY,invoice_id TEXT REFERENCES invoices(id),amount INTEGER)',
    );
    db.execute(
      "INSERT INTO payments VALUES ('p1','6359',300000),('p2','6359',488211)",
    );
    db.execute(
      'CREATE TABLE runtime_payroll(id TEXT PRIMARY KEY,paid INTEGER,hours REAL)',
    );
    db.execute("INSERT INTO runtime_payroll VALUES ('already-paid',1,12)");
    db.execute(
      'CREATE TABLE outbox(id TEXT PRIMARY KEY,payload TEXT,attempt_count INTEGER)',
    );
    db.execute('INSERT INTO outbox VALUES (?,?,?)', [
      'unchanged-operation',
      jsonEncode({
        'photos': [
          original,
          {'source_uri': contentUri},
        ],
        'status': 'Done',
      }),
      3,
    ]);
    db.close();
    await BackupArchive.seal(
      backup,
      businessId: 'shop',
      appVersion: 'test',
      sourceFiles: {
        original: 'Originals/file-0',
        contentUri: 'Originals/file-1',
      },
      warnings: [],
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'complete snapshot verifies totals, payment identities and runtime tables',
    () async {
      final result = await BackupArchive.verify(backup, businessId: 'shop');
      expect(result['complete'], true);
      expect((result['table_counts'] as Map)['payments'], 2);
      expect((result['table_counts'] as Map)['runtime_payroll'], 1);
    },
  );
  test(
    'restore relocates originals inside nested outbox JSON without replay',
    () async {
      final target = Directory('${root.path}/different-phone');
      final file = await BackupArchive.restoreTo(
        backup,
        target,
        businessId: 'shop',
      );
      final db = sqlite3.open(file.path);
      try {
        expect(
          db.select('SELECT status FROM invoices').single['status'],
          'Closed',
        );
        expect(
          db
              .select('SELECT SUM(amount) AS total FROM payments')
              .single['total'],
          788211,
        );
        expect(db.select('SELECT paid FROM runtime_payroll').single['paid'], 1);
        final row = db.select('SELECT * FROM outbox').single;
        expect(row['id'], 'unchanged-operation');
        expect(row['attempt_count'], 3);
        final payload = jsonDecode(row['payload'] as String) as Map;
        expect(payload['photos'], [
          '${target.path}/Originals/file-0',
          {'source_uri': '${target.path}/Originals/file-1'},
        ]);
        expect(await File('${target.path}/Originals/file-1').readAsBytes(), [
          4,
          5,
          6,
        ]);
      } finally {
        db.close();
      }
      expect(await BackupArchive.verify(backup), isNotNull);
    },
  );
  test('corrupted bytes fail verification before destination exists', () async {
    await File('${backup.path}/Originals/file-0').writeAsBytes([9, 9, 9]);
    final target = Directory('${root.path}/do-not-create');
    await expectLater(
      BackupArchive.restoreTo(backup, target, businessId: 'shop'),
      throwsStateError,
    );
    expect(await target.exists(), false);
  });
  test('missing originals and missing manifest are rejected', () async {
    await File('${backup.path}/Originals/file-1').delete();
    await expectLater(
      BackupArchive.verify(backup),
      throwsA(isA<FileSystemException>()),
    );
    await File('${backup.path}/${BackupArchive.manifestName}').delete();
    await expectLater(
      BackupArchive.verify(backup),
      throwsA(isA<FileSystemException>()),
    );
  });
  test('different business cannot restore', () async {
    await expectLater(
      BackupArchive.verify(backup, businessId: 'another-shop'),
      throwsStateError,
    );
  });
  test('partial backup retains explicit incompleteness', () async {
    await BackupArchive.seal(
      backup,
      businessId: 'shop',
      appVersion: 'test',
      sourceFiles: {},
      warnings: ['Missing receipt'],
    );
    final manifest = await BackupArchive.verify(backup);
    expect(manifest['complete'], false);
    expect(manifest['warnings'], ['Missing receipt']);
  });
  test('path traversal and symlink escapes are refused', () async {
    for (final name in [
      '../secret',
      '/tmp/secret',
      'Originals/../../secret',
      'a\\b',
      'content://x',
      'a//b',
    ]) {
      expect(() => BackupArchive.safeRelative(name), throwsFormatException);
    }
    await File('${backup.path}/Originals/file-0').delete();
    final outside = File('${root.path}/outside');
    await outside.writeAsBytes([1, 2, 3]);
    await Link('${backup.path}/Originals/file-0').create(outside.path);
    await expectLater(BackupArchive.verify(backup), throwsStateError);
  });
  test('restore never overwrites an existing destination', () async {
    final target = Directory('${root.path}/existing');
    await target.create();
    await expectLater(
      BackupArchive.restoreTo(backup, target, businessId: 'shop'),
      throwsStateError,
    );
    expect(await target.exists(), true);
  });
  test('discovery includes nested JSON and content URI originals', () {
    final db = sqlite3.open('${backup.path}/Database/briskers_local.sqlite');
    try {
      expect(
        BackupArchive.referencedFiles(db),
        containsAll([original, contentUri]),
      );
    } finally {
      db.close();
    }
  });
  test(
    'settings never export credentials, sessions or device authorization',
    () {
      for (final key in [
        'sb-auth-token',
        'briskers_auth',
        'briskers_owner_delete_enrollment_v1',
        'briskers_device_id',
        'briskers_receipt_gateway_secret',
        'briskers_backup_tree_v1',
        'briskers_session',
        'briskers_membership',
      ]) {
        expect(LocalBackupService.safePreference(key), false, reason: key);
      }
      expect(LocalBackupService.safePreference('briskers_language'), true);
      expect(
        LocalBackupService.safePreference('briskers_connection_mode'),
        true,
      );
    },
  );
  test(
    'SQLite WAL snapshot includes committed changes without closing source',
    () async {
      final live = sqlite3.open('${root.path}/live.sqlite');
      try {
        live.execute('PRAGMA journal_mode=WAL');
        live.execute('CREATE TABLE records(id TEXT PRIMARY KEY)');
        live.execute(
          "INSERT INTO records VALUES('most-recent-offline-record')",
        );
        final copy = '${root.path}/wal-snapshot.sqlite';
        live.execute('VACUUM INTO ?', [copy]);
        final snapshot = sqlite3.open(copy, mode: OpenMode.readOnly);
        try {
          expect(
            snapshot.select('SELECT id FROM records').single['id'],
            'most-recent-offline-record',
          );
        } finally {
          snapshot.close();
        }
      } finally {
        live.close();
      }
    },
  );
}
