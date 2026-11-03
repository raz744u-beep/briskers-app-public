import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// Only synthetic notes live here. Never substitute production business data.
String lanLabRandomHex(int bytes) {
  final random = Random.secure();
  return List<int>.generate(bytes, (_) => random.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

class LanLabNote {
  const LanLabNote({
    required this.id,
    required this.origin,
    required this.text,
    required this.createdAt,
    required this.digest,
  });

  final String id;
  final String origin;
  final String text;
  final String createdAt;
  final String digest;

  static final RegExp _idPattern = RegExp(r'^[a-f0-9]{32}$');

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'origin': origin,
    'text': text,
    'createdAt': createdAt,
    'digest': digest,
  };

  static Future<String> _computeDigest({
    required String id,
    required String origin,
    required String text,
    required String createdAt,
  }) async {
    final bytes = utf8.encode(jsonEncode(<String, String>{
      'id': id,
      'origin': origin,
      'text': text,
      'createdAt': createdAt,
    }));
    final hash = await Sha256().hash(bytes);
    return hash.bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<LanLabNote> create(String origin, String text) async {
    final id = lanLabRandomHex(16);
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final digest = await _computeDigest(
      id: id, origin: origin, text: text, createdAt: createdAt,
    );
    return LanLabNote(
      id: id, origin: origin, text: text, createdAt: createdAt, digest: digest,
    );
  }

  static Future<LanLabNote> fromJson(Map<String, dynamic> json) async {
    final id = json['id']?.toString() ?? '';
    final origin = json['origin']?.toString() ?? '';
    final text = json['text']?.toString() ?? '';
    final createdAt = json['createdAt']?.toString() ?? '';
    final digest = json['digest']?.toString() ?? '';
    if (!_idPattern.hasMatch(id) || !_idPattern.hasMatch(origin) ||
        text.trim().isEmpty || text.length > 200 ||
        DateTime.tryParse(createdAt) == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid synthetic LAN note');
    }
    final actual = await _computeDigest(
      id: id, origin: origin, text: text, createdAt: createdAt,
    );
    if (actual != digest) {
      throw const FormatException('Synthetic LAN note integrity failure');
    }
    return LanLabNote(
      id: id, origin: origin, text: text,
      createdAt: createdAt, digest: digest,
    );
  }
}

/// Isolated file-per-operation journal.
///
/// One note is written to a temporary file, flushed, then atomically renamed.
/// A lost ACK can therefore be retried without duplicating the note.
/// This is a synthetic demo store, NOT the production SQLite outbox.
class LanLabStore {
  LanLabStore(this.directory);

  final Directory directory;
  Future<void> _pending = Future<void>.value();

  static Future<LanLabStore> open() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(root.path + '/briskers_lan_synthetic_v1');
    await directory.create(recursive: true);
    return LanLabStore(directory);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<bool> save(LanLabNote note) => _exclusive(() async {
    // Always validate at the storage boundary, including local creations.
    final validated = await LanLabNote.fromJson(note.toJson());
    final dest = File(directory.path + '/' + validated.id + '.json');
    if (await dest.exists()) {
      final old = await LanLabNote.fromJson(
        Map<String, dynamic>.from(jsonDecode(await dest.readAsString()) as Map),
      );
      if (old.digest != validated.digest) {
        throw StateError('Conflicting operation ID: ' + validated.id);
      }
      return false;
    }
    await directory.create(recursive: true);
    final temp = File(directory.path + '/' + validated.id +
        '.' + lanLabRandomHex(8) + '.tmp');
    try {
      await temp.writeAsString(jsonEncode(validated.toJson()), flush: true);
      await temp.rename(dest.path);
      return true;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  });

  Future<int> saveAll(Iterable<LanLabNote> notes) async {
    var inserted = 0;
    for (final note in notes) {
      if (await save(note)) inserted++;
    }
    return inserted;
  }

  Future<List<LanLabNote>> all() async {
    await directory.create(recursive: true);
    final files = await directory.list().where(
      (entry) => entry is File && entry.path.endsWith('.json'),
    ).cast<File>().toList();
    if (files.length > 50) {
      throw StateError('Synthetic test limit reached (50 notes)');
    }
    final notes = <LanLabNote>[];
    for (final file in files) {
      final payload = jsonDecode(await file.readAsString());
      notes.add(await LanLabNote.fromJson(
        Map<String, dynamic>.from(payload as Map),
      ));
    }
    notes.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return List<LanLabNote>.unmodifiable(notes);
  }
}
