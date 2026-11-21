import 'dart:convert';
import 'dart:io';

import '../../local/local_database_provider.dart';
import 'backup_archive.dart';

/// Cache object names are deterministic; honor restored originals even when
/// Android gives the replacement device a different private-storage prefix.
class RestoredAttachmentLookup {
  static String? _loadedTarget;
  static Map<String, String> _paths = {};

  static Future<Map<String, File>> originals() async {
    try {
      final exists = await localDatabase
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='briskers_backup_restore_marker'",
          )
          .get();
      if (exists.isEmpty) return {};
      final markers = await localDatabase
          .customSelect(
            'SELECT target FROM briskers_backup_restore_marker LIMIT 1',
          )
          .get();
      if (markers.isEmpty) return {};
      final target = markers.single.read<String>('target');
      if (_loadedTarget != target) {
        final manifest =
            jsonDecode(
                  await File(
                    '$target/${BackupArchive.manifestName}',
                  ).readAsString(),
                )
                as Map;
        _paths = (manifest['source_files'] as Map).cast<String, String>();
        _loadedTarget = target;
      }
      return {
        for (final entry in _paths.entries)
          entry.key: File('$target/${BackupArchive.safeRelative(entry.value)}'),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<File?> find(String relative) async {
    final files = await originals();
    for (final entry in files.entries) {
      if (!entry.key.endsWith('/$relative')) continue;
      if (await entry.value.exists() && await entry.value.length() > 0) {
        return entry.value;
      }
    }
    return null;
  }
}
