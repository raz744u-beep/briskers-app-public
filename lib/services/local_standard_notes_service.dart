import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'briskers_api.dart';

/// Local-first standard note templates. Pending templates are kept until a
/// subsequent online session verifies the server copy by name and body.
class LocalStandardNotesService {
  LocalStandardNotesService({BriskersApi api = const BriskersApi()}) : _api = api;
  final BriskersApi _api;
  final Random _random = Random.secure();

  String _key(String businessId) => 'briskers_standard_note_templates_$businessId';

  Future<List<Map<String, dynamic>>> cached(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(String businessId, List<Map<String, dynamic>> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), jsonEncode(notes));
  }

  Future<List<Map<String, dynamic>>> available(
    String businessId, {required bool offline}
  ) async {
    final local = await cached(businessId);
    if (offline) return local;
    try {
      final remote = await _api.documentNoteTemplates(businessId);
      final pending = local.where((note) => note['pending_sync'] == true).toList();
      final names = remote.map((note) =>
          note['name']?.toString().trim().toLowerCase()).toSet();
      final combined = [...remote, ...pending.where((note) =>
          !names.contains(note['name']?.toString().trim().toLowerCase()))];
      await _persist(businessId, combined);
      return combined;
    } catch (_) {
      return local;
    }
  }

  Future<Map<String, dynamic>> saveOffline(
    String businessId, {required String name, required String body}
  ) async {
    final notes = await cached(businessId);
    final normalized = name.trim().toLowerCase();
    if (notes.any((note) =>
        note['name']?.toString().trim().toLowerCase() == normalized)) {
      throw StateError('A standard note already has this name.');
    }
    final note = <String, dynamic>{
      'id': 'local-standard-note-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}',
      'name': name.trim(),
      'body': body.trim(),
      'pending_sync': true,
    };
    await _persist(businessId, [...notes, note]);
    return note;
  }

  Future<void> flushPending(String businessId) async {
    final notes = await cached(businessId);
    if (!notes.any((note) => note['pending_sync'] == true)) return;
    final remote = await _api.documentNoteTemplates(businessId);
    final pending = <Map<String, dynamic>>[];
    for (final note in notes) {
      if (note['pending_sync'] != true) continue;
      final name = note['name']?.toString().trim() ?? '';
      final body = note['body']?.toString().trim() ?? '';
      Map<String, dynamic>? match;
      for (final candidate in remote) {
        if (candidate['name']?.toString().trim().toLowerCase() ==
            name.toLowerCase()) {
          match = candidate;
          break;
        }
      }
      if (match != null && match['body']?.toString().trim() != body) {
        throw StateError('Standard note "$name" conflicts with a saved server note.');
      }
      if (match == null) {
        await _api.saveDocumentNoteTemplate(
          businessId, name: name, body: body);
        // If the response was interrupted, a retry first looks for the name,
        // avoiding another create for a successfully committed template.
      }
      pending.add(note);
    }
    final refreshed = await _api.documentNoteTemplates(businessId);
    final untouched = notes.where((note) => note['pending_sync'] != true);
    await _persist(businessId, [...refreshed, ...untouched.where((note) =>
      !refreshed.any((r) => r['name']?.toString().trim().toLowerCase() ==
        note['name']?.toString().trim().toLowerCase()))]);
  }
}
