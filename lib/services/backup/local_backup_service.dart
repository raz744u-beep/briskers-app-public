import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../local/local_database_provider.dart';
import '../../core/connection_mode.dart';
import '../device_owner_authorization.dart';
import '../offline_attachment_mirror_service.dart';
import 'backup_archive.dart';
import 'restored_attachment_lookup.dart';

class LocalBackupService {
  static const channel = MethodChannel('com.briskers/backup');
  static final progress = ValueNotifier<String>('');
  static bool _busy = false;
  static const rootKey = 'briskers_backup_tree_v1';
  static const statusKey = 'briskers_backup_status_v1';
  static const automaticKey = 'briskers_backup_automatic_v1';
  static const restoreRequest = 'briskers_backup_restore_request_v1';

  static bool safePreference(String key) =>
      key.startsWith('briskers_') &&
      !RegExp(
        r'auth|token|secret|password|session|enrollment|device|backup|membership|role|supabase|gateway',
        caseSensitive: false,
      ).hasMatch(key);

  static Future<void> authorize(String businessId) async {
    await DeviceOwnerAuthorization.instance.authority.authorizeSession(
      businessId,
    );
  }

  static Future<String?> chooseFolder() =>
      channel.invokeMethod<String>('pickFolder');

  static Future<Map<String, dynamic>> create(String businessId) async {
    await authorize(businessId);
    if (_busy) throw StateError('A backup or restore is already running');
    _busy = true;
    Directory? scratch;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tree = prefs.getString(rootKey);
      if (tree == null) throw StateError('Choose a backup folder first');
      final root = await getTemporaryDirectory();
      scratch = await Directory('${root.path}/briskers-backup-').createTemp();
      progress.value = 'Saving database';
      final manifest = await snapshot(businessId, scratch);
      progress.value = 'Copying backup to your folder and checking every file';
      final name =
          'backup-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}-${DateTime.now().microsecondsSinceEpoch}';
      final exported = await channel.invokeMethod<String>('exportFolder', {
        'tree': tree,
        'source': scratch.path,
        'name': name,
      });
      if (exported == null) {
        throw StateError('Backup folder copy did not finish');
      }
      final status = <String, dynamic>{
        'created_at': manifest['created_at'],
        'complete': manifest['complete'],
        'warnings': manifest['warnings'],
        'folder': exported,
        'files': (manifest['files'] as Map).length,
      };
      await prefs.setString(statusKey, jsonEncode(status));
      progress.value = manifest['complete'] == true
          ? 'Backup verified'
          : 'Backup saved with missing-file warnings';
      return status;
    } finally {
      if (scratch != null && await scratch.exists()) {
        await scratch.delete(recursive: true);
      }
      _busy = false;
    }
  }

  static Future<Map<String, dynamic>> snapshot(
    String businessId,
    Directory folder,
  ) async {
    final dbFile = File('${folder.path}/Database/briskers_local.sqlite');
    await dbFile.parent.create(recursive: true);
    // SQLite's own snapshot includes committed WAL pages; copying a live .sqlite
    // file directly can silently omit the most recent offline records.
    await localDatabase.customStatement('VACUUM INTO ?', [dbFile.path]);
    final sourceFiles = <String, String>{};
    final warnings = <String>[];
    var index = 0;
    Future<void> copyOriginal(String original) async {
      if (sourceFiles.containsKey(original)) return;
      final relative = 'Originals/file-${index++}';
      final destination = File('${folder.path}/$relative');
      await destination.parent.create(recursive: true);
      try {
        if (original.startsWith('content://')) {
          await channel.invokeMethod<void>('copyOriginal', {
            'uri': original,
            'destination': destination.path,
          });
        } else {
          final path = original.startsWith('file://')
              ? Uri.parse(original).toFilePath()
              : original;
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type == FileSystemEntityType.directory) return;
          if (type != FileSystemEntityType.file) {
            throw StateError('Original unavailable');
          }
          await File(path).copy(destination.path);
        }
        sourceFiles[original] = relative;
      } catch (_) {
        warnings.add('Original unavailable: $original');
        if (await destination.exists()) await destination.delete();
      }
    }

    final db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
    late Set<String> references;
    try {
      references = BackupArchive.referencedFiles(db);
    } finally {
      db.close();
    }
    // Include every owned original and cached attachment, even if a legacy
    // projection no longer points to it. Never include a live database, tokens,
    // temporary downloads, or the backup folder itself.
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    for (final root in [support, documents]) {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = entity.path.substring(root.path.length + 1);
        if (relative.startsWith('briskers_media/') ||
            relative.startsWith('attachment_cache/') ||
            RegExp(
              r'\.(pdf|jpg|jpeg|png|webp|heic|gif)$',
              caseSensitive: false,
            ).hasMatch(relative)) {
          references.add(entity.path);
        }
      }
    }
    final restoredOriginals = await RestoredAttachmentLookup.originals();
    references.addAll(restoredOriginals.values.map((file) => file.path));
    for (final reference in references) {
      progress.value = 'Saving original ${index + 1} of ${references.length}';
      await copyOriginal(reference);
    }
    // Retain the original deterministic cache identities through repeated
    // backup/restore generations, as well as the current physical paths.
    for (final entry in restoredOriginals.entries) {
      final copied = sourceFiles[entry.value.path];
      if (copied != null) sourceFiles[entry.key] = copied;
    }
    final inventory = await OfflineAttachmentMirrorService().inventory(
      businessId,
    );
    if (inventory.available < inventory.known) {
      warnings.add(
        '${inventory.known - inventory.available} known cloud attachments are not stored on this device.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final settings = {
      for (final key in prefs.getKeys().where(safePreference))
        key: prefs.get(key),
    };
    final settingsFile = File('${folder.path}/Settings/preferences.json');
    await settingsFile.parent.create(recursive: true);
    await settingsFile.writeAsString(jsonEncode(settings), flush: true);
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('copyApk', {
        'destination': '${folder.path}/App/Briskers.apk',
      });
    }
    final info = await PackageInfo.fromPlatform();
    return BackupArchive.seal(
      folder,
      businessId: businessId,
      appVersion: '${info.version}+${info.buildNumber}',
      sourceFiles: sourceFiles,
      warnings: warnings,
    );
  }

  /// Downloads a chosen dated folder and verifies an isolated restore. No live
  /// records are modified by inspection or by a cancelled confirmation.
  static Future<Directory?> inspect(String businessId) async {
    await authorize(businessId);
    if (_busy) throw StateError('A backup or restore is already running');
    final tree = await chooseFolder();
    if (tree == null) return null;
    _busy = true;
    final root = await getApplicationSupportDirectory();
    final container = await Directory(
      '${root.path}/backup-review-',
    ).createTemp();
    try {
      progress.value = 'Reading and verifying backup';
      final imported = Directory('${container.path}/import');
      await channel.invokeMethod<void>('importFolder', {
        'tree': tree,
        'destination': imported.path,
      });
      await BackupArchive.verify(imported, businessId: businessId);
      final restored = Directory('${container.path}/Restored');
      await BackupArchive.restoreTo(imported, restored, businessId: businessId);
      progress.value = 'Restore test passed';
      return imported;
    } catch (_) {
      await container.delete(recursive: true);
      rethrow;
    } finally {
      _busy = false;
    }
  }

  static Future<void> requestRestore(
    String businessId,
    Directory source,
  ) async {
    await authorize(businessId);
    await BackupArchive.verify(source, businessId: businessId);
    final prefs = await SharedPreferences.getInstance();
    // Restoring is a replacement, never a synchronization or a replay of wages.
    await prefs.setString('briskers_connection_mode', 'offline');
    BriskersConnectionModeController.instance.useSafeOfflineFallback();
    await prefs.setString(
      restoreRequest,
      jsonEncode({'business': businessId, 'source': source.path}),
    );
  }

  /// Runs at bootstrap before document caches, session/network initialization,
  /// and background scheduling. The SQL transaction keeps the live DB intact
  /// on any copy/schema failure. A safety snapshot is retained before replacement.
  static Future<void> applyRequestedRestore() async {
    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 8),
    );
    final raw = prefs.getString(restoreRequest);
    if (raw == null) return;
    final request = jsonDecode(raw) as Map;
    final support = await getApplicationSupportDirectory();
    final source = Directory(request['source'] as String);
    final root = await support.resolveSymbolicLinks();
    final sourceRoot = await source.resolveSymbolicLinks();
    if (!sourceRoot.startsWith('$root/backup-review-')) {
      throw StateError('Invalid restore request');
    }
    final business = request['business'] as String;
    await BackupArchive.verify(source, businessId: business);
    String? committedTarget;
    final markerExists = await localDatabase
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='briskers_backup_restore_marker'",
        )
        .get();
    if (markerExists.isNotEmpty) {
      final markers = await localDatabase
          .customSelect('SELECT id,target FROM briskers_backup_restore_marker')
          .get();
      for (final marker in markers) {
        if (marker.read<String>('id') == sourceRoot) {
          committedTarget = marker.read<String>('target');
        }
      }
    }
    late Directory target;
    if (committedTarget != null) {
      // SQL already committed on a previous launch. Never apply it twice or
      // point records to a different set of restored originals after a crash.
      target = Directory(committedTarget);
      final canonical = await target.resolveSymbolicLinks();
      if (!canonical.startsWith('$root/restored-backup-')) {
        throw StateError('Invalid restored media location');
      }
    } else {
      target = Directory(
        '${support.path}/restored-backup-${DateTime.now().microsecondsSinceEpoch}',
      );
      final restored = await BackupArchive.restoreTo(
        source,
        target,
        businessId: business,
      );
      final original = File(
        '${support.path}/backup-safety/before-restore-${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      await original.parent.create(recursive: true);
      await localDatabase.customStatement('VACUUM INTO ?', [original.path]);
      final oldDb = sqlite3.open(original.path, mode: OpenMode.readOnly);
      final newDb = sqlite3.open(restored.path, mode: OpenMode.readOnly);
      late Map<String, String> oldSchema, newSchema;
      try {
        oldSchema = BackupArchive.schema(oldDb);
        newSchema = BackupArchive.schema(newDb);
        if (oldDb.userVersion != newDb.userVersion) {
          throw StateError(
            'Use the matching app version to restore this backup',
          );
        }
        for (final entry in oldSchema.entries) {
          if (newSchema[entry.key] != entry.value) {
            throw StateError('Database layout differs; restore stopped safely');
          }
        }
      } finally {
        oldDb.close();
        newDb.close();
      }
      await localDatabase.customStatement(
        'ATTACH DATABASE ? AS backup_restore',
        [restored.path],
      );
      try {
        await localDatabase.transaction(() async {
          await localDatabase.customStatement('PRAGMA defer_foreign_keys=ON');
          for (final entry in newSchema.entries) {
            if (!oldSchema.containsKey(entry.key)) {
              await localDatabase.customStatement(entry.value);
            }
          }
          for (final table in newSchema.keys) {
            await localDatabase.customStatement(
              'DELETE FROM ${BackupArchive.quote(table)}',
            );
          }
          for (final table in newSchema.keys) {
            final quoted = BackupArchive.quote(table);
            await localDatabase.customStatement(
              'INSERT INTO $quoted SELECT * FROM backup_restore.$quoted',
            );
          }
          if ((await localDatabase
                  .customSelect('PRAGMA foreign_key_check')
                  .get())
              .isNotEmpty) {
            throw StateError('Restore failed record-link verification');
          }
          await localDatabase.customStatement(
            'CREATE TABLE IF NOT EXISTS briskers_backup_restore_marker (id TEXT PRIMARY KEY, target TEXT NOT NULL)',
          );
          await localDatabase.customStatement(
            'DELETE FROM briskers_backup_restore_marker',
          );
          await localDatabase.customStatement(
            'INSERT INTO briskers_backup_restore_marker VALUES (?,?)',
            [sourceRoot, target.path],
          );
        });
      } finally {
        await localDatabase.customStatement('DETACH DATABASE backup_restore');
      }
    }
    final restoredSettings =
        jsonDecode(
              await File(
                '${target.path}/Settings/preferences.json',
              ).readAsString(),
            )
            as Map;
    for (final entry in restoredSettings.entries) {
      final key = entry.key as String;
      if (!safePreference(key)) continue;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
    await prefs.setString('briskers_connection_mode', 'offline');
    await prefs.remove(restoreRequest);
    await prefs.setString(
      'briskers_backup_restored_at_v1',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  static Future<void> automaticIfDue() async {
    if (_busy || !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(automaticKey) != true ||
          prefs.getString(rootKey) == null) {
        return;
      }
      final raw = prefs.getString(statusKey);
      if (raw != null) {
        final status = jsonDecode(raw) as Map;
        final time = DateTime.tryParse(status['created_at'] as String? ?? '');
        if (time != null &&
            DateTime.now().toUtc().difference(time) < const Duration(days: 1)) {
          return;
        }
      }
      final business = prefs.getString('briskers_backup_business_v1');
      if (business == null) return;
      await create(business);
    } catch (error) {
      progress.value =
          'Automatic backup did not finish. Open Backup & Restore to retry.';
    }
  }
}
