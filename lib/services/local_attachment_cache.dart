import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'briskers_api.dart';

class LocalAttachmentCache {
  LocalAttachmentCache({BriskersApi api = const BriskersApi()}) : _api = api;

  final BriskersApi _api;

  static final Map<String, Future<File?>> _inFlight = {};

  Future<File?> getOrDownload(
    String bucket,
    String key,
  ) async {
    if (bucket.isEmpty || key.isEmpty) return null;

    final file = await _cacheFile(bucket, key);
    if (await _isUsable(file)) return file;

    final cacheKey = '$bucket::$key';
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final future = _download(bucket, key, file);
    _inFlight[cacheKey] = future;

    try {
      return await future;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<File?> existing(
    String bucket,
    String key,
  ) async {
    if (bucket.isEmpty || key.isEmpty) return null;
    final file = await _cacheFile(bucket, key);
    return await _isUsable(file) ? file : null;
  }

  Future<void> remove(
    String bucket,
    String key,
  ) async {
    if (bucket.isEmpty || key.isEmpty) return;
    final file = await _cacheFile(bucket, key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File?> _download(
    String bucket,
    String key,
    File target,
  ) async {
    HttpClient? client;

    try {
      final url = await _api.signedAttachmentUrl(bucket, key);
      client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }

      await target.parent.create(recursive: true);
      final temp = File('${target.path}.part');
      if (await temp.exists()) {
        await temp.delete();
      }

      final sink = temp.openWrite();
      await response.pipe(sink);

      if (!await _isUsable(temp)) {
        if (await temp.exists()) await temp.delete();
        return null;
      }

      if (await target.exists()) {
        await target.delete();
      }
      return await temp.rename(target.path);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<File> _cacheFile(
    String bucket,
    String key,
  ) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}/attachment_cache/findings',
    );

    final extension = _extensionFromKey(key);
    final hash = _stableHash('$bucket::$key');

    return File('${directory.path}/$hash$extension');
  }

  Future<bool> _isUsable(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  String _extensionFromKey(String key) {
    final clean = key.split('?').first;
    final slash = clean.lastIndexOf('/');
    final dot = clean.lastIndexOf('.');
    if (dot <= slash || dot < 0) return '.img';

    final extension = clean.substring(dot).toLowerCase();
    if (extension.length > 6) return '.img';
    return extension;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
