import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/standard_note_rules.dart';
import 'briskers_api.dart';

/// Local-first templates. Pending field patches survive interrupted requests,
/// stale server reads, and other service instances refreshing the same business.
class LocalStandardNotesService {
  LocalStandardNotesService({BriskersApi api = const BriskersApi()}) : _api = api;
  final BriskersApi _api;
  final Random _random = Random.secure();
  static final _queues = <String, Future<void>>{};
  static const _editableFields = ['name', 'body', 'color_hex', 'sort_order'];

  String _key(String businessId) => 'briskers_standard_note_templates_$businessId';

  Future<T> _serialized<T>(String businessId, Future<T> Function() work) async {
    final previous = _queues[businessId] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[businessId] = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[businessId], done.future)) {
        _queues.remove(businessId);
      }
    }
  }

  Future<List<Map<String, dynamic>>> cached(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return [];
    try {
      return orderStandardNotes((jsonDecode(raw) as List).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)));
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(String businessId, List<Map<String, dynamic>> notes) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key(businessId), jsonEncode(orderStandardNotes(notes)))) {
      throw StateError('Could not save standard notes on this device.');
    }
  }

  String _name(Map<String, dynamic> note) =>
      note['name']?.toString().trim().toLowerCase() ?? '';
  bool _local(Map<String, dynamic> note) =>
      note['id']?.toString().startsWith('local-standard-note-') == true;

  Object? _value(Map<String, dynamic> note, String field) {
    if (field == 'color_hex') return standardNoteColorHex(note[field]);
    if (field == 'sort_order') return standardNoteSortOrder(note);
    return note[field]?.toString().trim() ?? '';
  }

  Map<String, dynamic> _patch(Map<String, dynamic> note) =>
      note['_pending_patch'] is Map
          ? Map<String, dynamic>.from(note['_pending_patch'] as Map)
          : {for (final field in _editableFields) field: _value(note, field)};

  Map<String, dynamic> _base(Map<String, dynamic> note) =>
      note['_sync_base'] is Map
          ? Map<String, dynamic>.from(note['_sync_base'] as Map)
          : {};

  Map<String, dynamic> _withChanges(
      Map<String, dynamic> note, Map<String, dynamic> changes,
      {Map<String, dynamic>? original}) {
    final next = Map<String, dynamic>.from(note);
    final patch = note['pending_sync'] == true ? _patch(note) : <String, dynamic>{};
    final base = _base(note);
    for (final entry in changes.entries) {
      if (_value(note, entry.key) == entry.value) continue;
      base.putIfAbsent(entry.key, () => _value(original ?? note, entry.key));
      next[entry.key] = entry.value;
      patch[entry.key] = entry.value;
    }
    if (patch.isNotEmpty) {
      next['pending_sync'] = true;
      next['_pending_patch'] = patch;
      next['_sync_base'] = base;
      next.remove('sync_error');
    }
    return next;
  }

  /// Refresh keeps pending values over the matching server row. Never dedupe
  /// conflicting local templates by name: that would discard the user's text.
  List<Map<String, dynamic>> _merge(List<Map<String, dynamic>> remote,
      List<Map<String, dynamic>> local) {
    final aliases = {for (final note in local)
      if (note['_local_id'] != null) note['id']: note['_local_id']};
    final merged = remote.map((note) => <String, dynamic>{
      ...note,
      if (aliases.containsKey(note['id'])) '_local_id': aliases[note['id']],
    }).toList();
    for (final pending in local.where((note) => note['pending_sync'] == true)) {
      final index = merged.indexWhere((note) => note['id'] == pending['id']);
      if (index < 0) {
        merged.add(pending);
      } else {
        merged[index] = {...merged[index], ...pending};
      }
    }
    return orderStandardNotes(merged);
  }

  Future<List<Map<String, dynamic>>> available(
      String businessId, {required bool offline}) =>
      _serialized(businessId, () async {
        if (offline) return cached(businessId);
        try {
          await _flushPending(businessId);
          final remote = await _api.documentNoteTemplates(businessId);
          final combined = _merge(remote, await cached(businessId));
          await _persist(businessId, combined);
          return combined;
        } catch (_) {
          // _flushPending records an actionable conflict without dropping edits.
          return cached(businessId);
        }
      });

  /// Used for both online and offline saves; callers may flush after the durable
  /// write. Editing a template never modifies text already inserted in invoices.
  Future<Map<String, dynamic>> saveOffline(
    String businessId, {
    String? templateId,
    Map<String, dynamic>? original,
    required String name,
    required String body,
    String colorHex = standardNoteDefaultColor,
  }) => _serialized(businessId, () async {
    if (name.trim().isEmpty || body.trim().isEmpty) {
      throw StateError('A template name and note text are required.');
    }
    final notes = await cached(businessId);
    final index = templateId == null ? -1 :
        notes.indexWhere((note) => note['id']?.toString() == templateId ||
            note['_local_id']?.toString() == templateId);
    if (templateId != null && index < 0) {
      throw StateError('Standard note not found. Reopen the list and try again.');
    }
    final changes = <String, dynamic>{
      'name': name.trim(), 'body': body.trim(),
      'color_hex': standardNoteColorHex(colorHex),
    };
    if (index >= 0 && original != null) {
      // Only the fields actually changed in this editor are patches. A refresh
      // while the editor was open must not turn its stale values into edits.
      changes.removeWhere((field, value) => _value(original, field) == value);
    }
    final effectiveName = changes['name']?.toString() ??
        (index >= 0 ? notes[index]['name'].toString() : name.trim());
    final normalized = effectiveName.trim().toLowerCase();
    if (notes.any((note) => _name(note) == normalized &&
        (index < 0 || note['id'] != notes[index]['id']))) {
      throw StateError('A standard note already has this name.');
    }
    if (index >= 0 && isGeneralStandardNote(notes[index]) && normalized != 'general') {
      throw StateError('General must keep its name and stay last.');
    }
    late Map<String, dynamic> note;
    if (index >= 0) {
      note = _withChanges(notes[index], changes, original: original);
      notes[index] = note;
    } else {
      final ranks = notes.where((note) => !isGeneralStandardNote(note))
          .map(standardNoteSortOrder);
      final nextOrder = ranks.isEmpty ? 100 : ranks.reduce(max) + 10;
      note = {
        'id': 'local-standard-note-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}',
        ...changes,
        'sort_order': nextOrder,
        'pending_sync': true,
        '_pending_patch': {...changes, 'sort_order': nextOrder},
      };
      notes.add(note);
    }
    await _persist(businessId, notes);
    return Map<String, dynamic>.from(note);
  });

  Future<List<Map<String, dynamic>>> reorderOffline(
      String businessId, List<String> orderedIds) =>
      _serialized(businessId, () async {
        final notes = await cached(businessId);
        final byId = {for (final note in notes) note['id'].toString(): note};
        final seen = <String>{};
        final reordered = <Map<String, dynamic>>[];
        for (final id in orderedIds) {
          if (seen.add(id) && byId.containsKey(id)) reordered.add(byId[id]!);
        }
        reordered.addAll(notes.where((note) => !seen.contains(note['id'].toString())));
        final movable = reordered.where((note) => !isGeneralStandardNote(note)).toList();
        final pinned = reordered.where(isGeneralStandardNote).toList();
        final ordered = [...movable, ...pinned];
        final updated = <Map<String, dynamic>>[
          for (var i = 0; i < ordered.length; i++)
            _withChanges(ordered[i], {'sort_order': (i + 1) * 10}),
        ];
        await _persist(businessId, updated);
        return updated;
      });

  Future<void> flushPending(String businessId) =>
      _serialized(businessId, () => _flushPending(businessId));

  Map<String, dynamic> _acknowledgeCreate(Map<String, dynamic> note,
      String serverId, Map<String, dynamic> createPayload) {
    // The legacy create commits name/body/order, but always uses default color.
    // These acknowledged fields are not edits to replay after a later read:
    // another device may already have changed them between create and fetch.
    final baseline = {...createPayload, 'color_hex': standardNoteDefaultColor};
    final patch = _patch(note)
      ..removeWhere((field, value) => _value(baseline, field) == value);
    return {
      ...note, 'id': serverId, '_local_id': note['_local_id'] ?? note['id'],
      '_sync_base': baseline, '_pending_patch': patch,
    };
  }

  Future<void> _flushPending(String businessId) async {
    final notes = await cached(businessId);
    if (!notes.any((note) => note['pending_sync'] == true)) return;
    var remote = await _api.documentNoteTemplates(businessId, includeInactive: true);
    Object? firstError;
    for (var index = 0; index < notes.length; index++) {
      var note = notes[index];
      if (note['pending_sync'] != true) continue;
      try {
        final creating = _local(note);
        final createPayload = note['_create_payload'] is Map
            ? Map<String, dynamic>.from(note['_create_payload'] as Map)
            : {for (final field in _editableFields) field: _value(note, field)};
        if (creating) {
          // Keep the exact initial create request even if the response is lost
          // and the user edits/renames the local copy before the next retry.
          note = {...note, '_create_payload': createPayload};
          notes[index] = note;
          await _persist(businessId, notes);
        }
        var matches = remote.where((candidate) => creating
            ? _name(candidate) == _name(createPayload)
            : candidate['id'] == note['id']).toList();
        if (matches.length > 1) {
          throw StateError('More than one server note is named "${note['name']}".');
        }
        if (creating && matches.isNotEmpty &&
            _value(matches.single, 'body') != _value(createPayload, 'body')) {
          throw StateError('Standard note "${note['name']}" conflicts with a saved server note. Your version is saved on this device.');
        }
        if (creating && matches.isEmpty) {
          final id = await _api.saveDocumentNoteTemplate(businessId,
            name: createPayload['name'].toString(),
            body: createPayload['body'].toString(),
            sortOrder: standardNoteSortOrder(createPayload));
          // Save the acknowledged identity before another request can fail.
          note = _acknowledgeCreate(note, id, createPayload);
          notes[index] = note;
          await _persist(businessId, notes);
          remote = await _api.documentNoteTemplates(businessId, includeInactive: true);
          matches = remote.where((candidate) => candidate['id'] == id).toList();
        }
        if (matches.isEmpty) {
          throw StateError('Standard note "${note['name']}" is missing on the server. Your changes are saved on this device.');
        }
        var server = matches.single;
        if (creating && _local(note)) {
          note = _acknowledgeCreate(note, server['id'].toString(), createPayload);
          notes[index] = note;
          await _persist(businessId, notes);
        }
        if (server['active'] == false) {
          throw StateError('Standard note "${note['name']}" was made inactive on the server. Your version is saved on this device.');
        }
        final patch = _patch(note);
        final base = _base(note);
        for (final field in patch.keys.toList()) {
          if (_value(server, field) == patch[field]) {
            patch.remove(field); // Also acknowledges a previously lost response.
          } else if (base.containsKey(field) &&
              _value(server, field) != base[field]) {
            throw StateError('Standard note "${note['name']}" was changed elsewhere. Your version is saved on this device.');
          }
        }
        note = {...note, 'id': server['id'], '_pending_patch': patch,
          if (creating) '_local_id': note['_local_id'] ?? note['id']};
        notes[index] = note;
        await _persist(businessId, notes);
        if (patch.isNotEmpty) {
          final version = int.tryParse(server['row_version']?.toString() ?? '');
          if (version == null) {
            throw StateError('Standard note changes are waiting for server support.');
          }
          server = await _api.patchDocumentNoteTemplate(businessId,
            templateId: server['id'].toString(), expectedVersion: version,
            patch: patch);
          if (patch.entries.any((entry) => _value(server, entry.key) != entry.value)) {
            throw StateError('The server has not confirmed all standard note changes.');
          }
        }
        notes[index] = {...server,
          if (note['_local_id'] != null) '_local_id': note['_local_id']};
        remote = [for (final candidate in remote)
          candidate['id'] == server['id'] ? server : candidate];
        await _persist(businessId, notes);
      } catch (error) {
        notes[index] = {...notes[index], 'sync_error': error.toString()};
        await _persist(businessId, notes);
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }
}
