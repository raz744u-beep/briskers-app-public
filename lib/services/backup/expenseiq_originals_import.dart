import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/services.dart';

import '../../local/briskers_local_database.dart';
import 'backup_archive.dart';

class ExpenseIqOriginalsImport {
  ExpenseIqOriginalsImport(
    this.database,
    this.media,
    this.scratch,
    this.channel,
  );

  final BriskersLocalDatabase database;
  final Directory media;
  final Directory scratch;
  final MethodChannel channel;

  static String? _legacyPath(String? address) {
    final uri = address == null ? null : Uri.tryParse(address);
    if (uri == null ||
        uri.scheme != 'content' ||
        uri.host != 'com.android.externalstorage.documents' ||
        uri.pathSegments.isEmpty) {
      return null;
    }
    final document = uri.pathSegments.last;
    const root = 'primary:expenseiq/photos/';
    if (!document.toLowerCase().startsWith(root)) return null;
    return document.substring(root.length);
  }

  Future<
    ({
      int scanned,
      int copied,
      int reused,
      int unreadable,
      int linked,
      int outstanding,
    })
  >
  run(String businessId, String tree, void Function(String) progress) async {
    progress('Counting Expense IQ photos');
    final files = await channel.invokeListMethod<Map<Object?, Object?>>(
      'listExpenseIqOriginals',
      {'tree': tree},
    );
    if (files == null || files.isEmpty) {
      throw StateError(
        'No photos found. Select Internal storage / ExpenseIQ / photos.',
      );
    }
    final records = await database
        .customSelect(
          'SELECT transaction_id, filename, source_uri FROM local_expense_iq_photos '
          'WHERE business_id = ?',
          variables: [Variable(businessId)],
        )
        .get();
    final legacyLinks =
        <String, List<({String id, String filename, String uri})>>{};
    for (final row in records) {
      final uri = row.readNullable<String>('source_uri');
      final path = _legacyPath(uri);
      if (path == null || uri == null) continue;
      final filename = row.read<String>('filename');
      if (path.split('/').last != filename) continue;
      (legacyLinks[path] ??= []).add((
        id: row.read<String>('transaction_id'),
        filename: filename,
        uri: uri,
      ));
    }
    await media.create(recursive: true);
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS local_expense_iq_imported_files (
        business_id TEXT NOT NULL, relative_path TEXT NOT NULL,
        digest TEXT NOT NULL, file_uri TEXT NOT NULL,
        source_size INTEGER, source_modified INTEGER,
        PRIMARY KEY (business_id, relative_path, digest)
      )
    ''');
    final imported = await database
        .customSelect(
          'SELECT relative_path, digest, file_uri, source_size, source_modified '
          'FROM local_expense_iq_imported_files WHERE business_id = ?',
          variables: [Variable(businessId)],
        )
        .get();
    final byPath = <String, List<Map<String, dynamic>>>{};
    for (final row in imported) {
      (byPath[row.read<String>('relative_path')] ??= []).add(row.data);
    }
    var copied = 0, reused = 0, unreadable = 0, linked = 0, processed = 0;
    for (final entry in files) {
      final path = entry['path'] as String;
      final uri = entry['uri'] as String;
      final size = entry['size'] as int?;
      final modified = entry['modified'] as int?;
      progress('Importing Expense IQ photo ${++processed} of ${files.length}');
      final staged = File('${scratch.path}/original.part');
      String? hash;
      File? destination;
      var addedFile = false;
      try {
        // Most retries can reuse a read-back-verified file. Without both
        // pieces of source metadata we read the original again.
        if (size != null && size > 0 && modified != null && modified > 0) {
          for (final prior in byPath[path] ?? const []) {
            if (prior['source_size'] != size ||
                prior['source_modified'] != modified)
              continue;
            final file = File.fromUri(Uri.parse(prior['file_uri'] as String));
            if (await file.exists() &&
                await file.length() == size &&
                await BackupArchive.digest(file) == prior['digest']) {
              destination = file;
              hash = prior['digest'] as String;
              break;
            }
          }
        }
        if (destination == null) {
          final sourceHash = await channel.invokeMethod<String>(
            'copyExpenseIqOriginal',
            {'uri': uri, 'destination': staged.path},
          );
          if (sourceHash == null ||
              !(await staged.exists()) ||
              await staged.length() == 0 ||
              await BackupArchive.digest(staged) != sourceHash) {
            throw const FileSystemException('Photo copy failed verification');
          }
          hash = sourceHash;
          final output = File('${media.path}/$hash.img');
          if (await output.exists()) {
            if (await BackupArchive.digest(output) != hash) {
              throw const FileSystemException(
                'An existing imported photo failed verification',
              );
            }
          } else {
            await staged.rename(output.path);
            addedFile = true;
          }
          destination = output;
        }
      } on PlatformException {
        unreadable++;
        continue;
      } on FileSystemException {
        unreadable++;
        continue;
      } finally {
        if (await staged.exists()) await staged.delete();
      }
      final savedUri = Uri.file(destination.path).toString();
      final matching = _legacyPath(uri) == path ? legacyLinks[path] : null;
      final updated = await database.transaction(() async {
        await database.customStatement(
          'INSERT OR REPLACE INTO local_expense_iq_imported_files '
          '(business_id, relative_path, digest, file_uri, source_size, source_modified) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [businessId, path, hash, savedUri, size, modified],
        );
        var count = 0;
        for (final link
            in matching ??
                const <({String id, String filename, String uri})>[]) {
          count += await database.customUpdate(
            'UPDATE local_expense_iq_photos SET source_uri = ? '
            'WHERE business_id = ? AND transaction_id = ? AND filename = ? AND source_uri = ?',
            variables: [
              Variable(savedUri),
              Variable(businessId),
              Variable(link.id),
              Variable(link.filename),
              Variable(link.uri),
            ],
          );
        }
        return count;
      });
      linked += updated;
      if (addedFile) {
        copied++;
      } else {
        reused++;
      }
    }
    final remaining = await database
        .customSelect(
          'SELECT source_uri FROM local_expense_iq_photos WHERE business_id = ?',
          variables: [Variable(businessId)],
        )
        .get();
    final outstanding = remaining.where((row) {
      final uri = row.readNullable<String>('source_uri');
      return uri == null || uri.isEmpty || _legacyPath(uri) != null;
    }).length;
    return (
      scanned: files.length,
      copied: copied,
      reused: reused,
      unreadable: unreadable,
      linked: linked,
      outstanding: outstanding,
    );
  }
}
