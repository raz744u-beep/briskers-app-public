import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

/// Portable, streamed folder snapshots. No network calls or live DB replacement.
class BackupArchive {
  static const format = 1;
  static const manifestName = 'backup-info.json';

  static String quote(String name) => '"${name.replaceAll('"', '""')}"';
  static Future<String> digest(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    return (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String safeRelative(String name) {
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
        name.contains(':')) {
      throw const FormatException('Unsafe backup filename');
    }
    return name;
  }

  static Map<String, int> counts(Database db) => {
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'briskers_backup_restore_marker' ORDER BY name",
    ))
      row['name'] as String:
          db
                  .select(
                    'SELECT COUNT(*) AS n FROM ${quote(row['name'] as String)}',
                  )
                  .single['n']
              as int,
  };

  static Map<String, String> schema(Database db) => {
    for (final row in db.select(
      "SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'briskers_backup_restore_marker' ORDER BY name",
    ))
      row['name'] as String: row['sql'] as String,
  };

  static Map<String, String> schemaObjects(Database db, String type) {
    if (!const {'trigger', 'index', 'view'}.contains(type)) {
      throw ArgumentError.value(type);
    }
    return {
      for (final row in db.select(
        "SELECT name,sql FROM sqlite_master WHERE type=? AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
        [type],
      ))
        row['name'] as String: row['sql'] as String,
    };
  }

  static void checkDatabase(Database db) {
    if (db.select('PRAGMA integrity_check').single.values.single != 'ok') {
      throw StateError('Backup database failed its integrity check');
    }
    if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('Backup database has broken record links');
    }
  }

  /// Discover references in every table, including runtime payroll and JSON
  /// caches/outboxes. Unknown or unreadable originals become explicit warnings.
  static Set<String> referencesIn(dynamic data) {
    final result = <String>{};
    void visit(dynamic value) {
      if (value is String) {
        if (value.startsWith('content://') ||
            value.startsWith('file://') ||
            RegExp(r'^/(data|storage|sdcard|private|var|Users|home|tmp)/')
                .hasMatch(value)) {
          result.add(value);
        } else if (value.startsWith('{') || value.startsWith('[')) {
          try {
            visit(jsonDecode(value));
          } on FormatException {
            /* plain text */
          }
        }
      } else if (value is Map) {
        value.values.forEach(visit);
      } else if (value is List) {
        value.forEach(visit);
      }
    }

    visit(data);
    return result;
  }

  static Set<String> referencedFiles(Database db) {
    final result = <String>{};
    for (final table in schema(db).keys) {
      // Receipt/signature BLOBs can be large. Inspect text references without
      // materializing the image bytes of an entire table in memory.
      for (final column in db.select('PRAGMA table_info(${quote(table)})')) {
        final name = quote(column['name'] as String);
        for (final row in db.select(
          "SELECT DISTINCT $name AS value FROM ${quote(table)} WHERE typeof($name)='text'",
        )) {
          result.addAll(referencesIn(row['value']));
        }
      }
    }
    return result;
  }

  static Future<Map<String, dynamic>> seal(
    Directory folder, {
    required String businessId,
    required String appVersion,
    required Map<String, String> sourceFiles,
    required List<String> warnings,
  }) async {
    final files = <String, dynamic>{};
    await for (final entry in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File || entry.path.endsWith('/$manifestName')) continue;
      final relative = safeRelative(
        entry.path.substring(folder.path.length + 1),
      );
      files[relative] = {
        'bytes': await entry.length(),
        'sha256': await digest(entry),
      };
    }
    final db = sqlite3.open(
      '${folder.path}/Database/briskers_local.sqlite',
      mode: OpenMode.readOnly,
    );
    late Map<String, dynamic> manifest;
    try {
      checkDatabase(db);
      manifest = {
        'format': format,
        'business_id': businessId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'app_version': appVersion,
        'schema_version': db.userVersion,
        'table_counts': counts(db),
        'files': files,
        'source_files': sourceFiles,
        'warnings': warnings,
        'complete': warnings.isEmpty,
        'credentials_included': false,
      };
    } finally {
      db.close();
    }
    // The completion manifest is always written last.
    await File('${folder.path}/$manifestName')
        .writeAsString(jsonEncode(manifest), flush: true);
    return manifest;
  }

  static Future<Map<String, dynamic>> verify(
    Directory folder, {
    String? businessId,
  }) async {
    final root = await folder.resolveSymbolicLinks();
    final manifest = jsonDecode(
      await File('$root/$manifestName').readAsString(),
    ) as Map<String, dynamic>;
    if (manifest['format'] != format ||
        (businessId != null && manifest['business_id'] != businessId)) {
      throw StateError('Unsupported backup or different business');
    }
    final files = manifest['files'] as Map<String, dynamic>;
    if (!files.containsKey('Database/briskers_local.sqlite') ||
        !files.containsKey('Settings/preferences.json')) {
      throw StateError('Backup is missing its database or settings');
    }
    for (final entry in files.entries) {
      final relative = safeRelative(entry.key);
      final file = File('$root/$relative');
      if (!await file.exists()) {
        throw StateError('Backup is missing a required file: $relative');
      }
      final resolved = await file.resolveSymbolicLinks();
      if (!resolved.startsWith('$root/')) {
        throw StateError('Backup file escapes folder');
      }
      final expected = entry.value as Map;
      if (await file.length() != expected['bytes'] ||
          await digest(file) != expected['sha256']) {
        throw StateError(
          'Backup contains a missing or damaged file: $relative',
        );
      }
    }
    final sourceFiles = manifest['source_files'] as Map;
    for (final relative in sourceFiles.values) {
      safeRelative(relative as String);
      if (!files.containsKey(relative)) {
        throw StateError('Missing original in backup');
      }
    }
    final db = sqlite3.open(
      '$root/Database/briskers_local.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      checkDatabase(db);
      if (jsonEncode(counts(db)) != jsonEncode(manifest['table_counts']) ||
          db.userVersion != manifest['schema_version']) {
        throw StateError('Backup record counts or schema do not match');
      }
    } finally {
      db.close();
    }
    return manifest;
  }

  /// Restore only into a new, isolated folder. Paths inside nested JSON and
  /// pending outbox payloads follow the copied originals on another device.
  static Future<File> restoreTo(
    Directory source,
    Directory target, {
    required String businessId,
  }) async {
    final manifest = await verify(source, businessId: businessId);
    if (await target.exists()) {
      throw StateError('Restore destination already exists');
    }
    await target.create(recursive: true);
    try {
      for (final relative in (manifest['files'] as Map).keys.cast<String>()) {
        final destination = File('${target.path}/${safeRelative(relative)}');
        await destination.parent.create(recursive: true);
        await File('${source.path}/$relative').copy(destination.path);
      }
      await File('${source.path}/$manifestName')
          .copy('${target.path}/$manifestName');
      final replacements = (manifest['source_files'] as Map)
          .map<String, String>((key, value) {
            final original = key as String;
            final path = '${target.path}/$value';
            // ContentResolver/SAF readers need a URI. Preserve URI semantics
            // while replacing device-specific content grants with owned files.
            return MapEntry(
              original,
              original.startsWith('content://') ||
                      original.startsWith('file://')
                  ? Uri.file(path).toString()
                  : path,
            );
          });
      dynamic rewrite(dynamic value) {
        if (value is String) {
          if (replacements.containsKey(value)) return replacements[value];
          if (value.startsWith('{') || value.startsWith('[')) {
            try {
              final decoded = jsonDecode(value);
              final rewritten = rewrite(decoded);
              final encoded = jsonEncode(rewritten);
              return encoded == jsonEncode(decoded) ? value : encoded;
            } on FormatException {
              return value;
            }
          }
        } else if (value is Map) {
          return value.map((key, item) => MapEntry(key, rewrite(item)));
        } else if (value is List) {
          return value.map(rewrite).toList();
        }
        return value;
      }

      final settings = File('${target.path}/Settings/preferences.json');
      final settingsData = jsonDecode(await settings.readAsString());
      await settings.writeAsString(
        jsonEncode(rewrite(settingsData)),
        flush: true,
      );

      final result = File('${target.path}/Database/briskers_local.sqlite');
      final db = sqlite3.open(result.path);
      try {
        db.execute('BEGIN IMMEDIATE');
        final guards = schemaObjects(db, 'trigger');
        // This isolated copy is being relocated, not edited as business work.
        // Restore all guards before committing; rollback also restores them.
        for (final name in guards.keys) {
          db.execute('DROP TRIGGER ${quote(name)}');
        }
        for (final table in counts(db).keys) {
          final columns = db.select('PRAGMA table_info(${quote(table)})');
          for (final column in columns) {
            final name = column['name'] as String;
            final values = db.select(
              'SELECT DISTINCT ${quote(name)} AS value FROM ${quote(table)} WHERE typeof(${quote(name)})=\'text\'',
            );
            for (final row in values) {
              final old = row['value'] as String;
              final next = rewrite(old);
              if (next != old) {
                db.execute(
                  'UPDATE ${quote(table)} SET ${quote(name)}=? WHERE ${quote(name)}=?',
                  [next, old],
                );
              }
            }
          }
        }
        for (final sql in guards.values) {
          db.execute(sql);
        }
        checkDatabase(db);
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        db.close();
      }
      return result;
    } catch (_) {
      await target.delete(recursive: true);
      rethrow;
    }
  }
}
