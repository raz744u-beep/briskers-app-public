import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_standard_notes_service.dart';

class _TemplatesApi extends BriskersApi {
  final server = <Map<String, dynamic>>[];
  int saves = 0;
  int patches = 0;
  bool simulateLostResponse = false;
  bool simulateLostPatchResponse = false;
  bool failPatches = false;
  void Function(Map<String, dynamic>)? afterCreate;
  Completer<void>? readBlock;
  Completer<void>? readStarted;

  @override
  Future<List<Map<String, dynamic>>> documentNoteTemplates(
    String businessId, {
    bool includeInactive = false,
  }) async {
    if (readBlock != null) {
      if (readStarted?.isCompleted == false) readStarted!.complete();
      await readBlock!.future;
    }
    return server.map((note) => Map<String, dynamic>.from(note)).toList();
  }

  @override
  Future<String> saveDocumentNoteTemplate(
    String businessId, {
    String? templateId,
    required String name,
    required String body,
    String templateType = 'standard',
    bool showInQuickList = true,
    bool active = true,
    int sortOrder = 100,
  }) async {
    saves++;
    final id = 'remote-$saves';
    server.add({
      'id': id,
      'name': name,
      'body': body,
      'sort_order': sortOrder,
      'color_hex': '#1565C0',
      'row_version': 1,
    });
    afterCreate?.call(server.last);
    if (simulateLostResponse) {
      simulateLostResponse = false;
      throw StateError('Simulated lost response after server commit');
    }
    return id;
  }

  @override
  Future<Map<String, dynamic>> patchDocumentNoteTemplate(
    String businessId, {
    required String templateId,
    required int expectedVersion,
    required Map<String, dynamic> patch,
  }) async {
    patches++;
    if (failPatches) throw StateError('Patch RPC not yet deployed');
    final index = server.indexWhere((note) => note['id'] == templateId);
    if (index < 0 || server[index]['row_version'] != expectedVersion) {
      throw StateError('Version conflict');
    }
    server[index] = {
      ...server[index],
      ...patch,
      'row_version': expectedVersion + 1,
    };
    if (simulateLostPatchResponse) {
      simulateLostPatchResponse = false;
      throw StateError('Simulated lost patch response');
    }
    return Map<String, dynamic>.from(server[index]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('standard templates can be created and retrieved offline', () async {
    final api = _TemplatesApi();
    final service = LocalStandardNotesService(api: api);
    final created = await service.saveOffline(
      'shop',
      name: 'Oil change note',
      body: 'Check oil level',
      colorHex: '#2E7D32',
    );
    expect(created['pending_sync'], isTrue);
    final offline = await service.available('shop', offline: true);
    expect(offline, hasLength(1));
    expect(offline.single['body'], 'Check oil level');
    expect(offline.single['color_hex'], '#2E7D32');
    expect(api.saves, 0);
    await expectLater(
      service.saveOffline('shop', name: 'oil CHANGE NOTE', body: 'Duplicate'),
      throwsStateError,
    );
  });

  test('server creation retries safely after interrupted response', () async {
    final api = _TemplatesApi()..simulateLostResponse = true;
    final service = LocalStandardNotesService(api: api);
    await service.saveOffline(
      'shop',
      name: 'Reminder',
      body: 'Inspect before release',
    );
    await expectLater(service.flushPending('shop'), throwsStateError);
    expect(api.server, hasLength(1));
    await service.flushPending('shop');
    expect(api.saves, 1);
    expect((await service.cached('shop')).single['pending_sync'], isNull);
  });

  test(
    'opening templates online replays pending templates exactly once',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline(
        'shop',
        name: 'Warranty reminder',
        body: 'Confirm authorization',
      );
      final first = await service.available('shop', offline: false);
      expect(first, hasLength(1));
      expect(api.saves, 1);
      expect(first.single['pending_sync'], isNull);
      expect(await service.available('shop', offline: false), hasLength(1));
      expect(api.saves, 1);
    },
  );

  test(
    'edit, color and order survive reopening and sync with General last',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      final general = await service.saveOffline(
        'shop',
        name: ' General ',
        body: 'General text',
      );
      final first = await service.saveOffline(
        'shop',
        name: 'First',
        body: 'First body',
      );
      final second = await service.saveOffline(
        'shop',
        name: 'Second',
        body: 'Second body',
      );
      await service.reorderOffline(
        'shop',
        [general['id'], second['id'], first['id']].cast<String>(),
      );
      await service.saveOffline(
        'shop',
        templateId: first['id'].toString(),
        name: 'First edited',
        body: 'Edited body',
        colorHex: '#C62828',
      );
      final reopened = LocalStandardNotesService(api: api);
      final offline = await reopened.cached('shop');
      expect(offline.map((note) => note['name']), [
        'Second',
        'First edited',
        'General',
      ]);
      final online = await reopened.available('shop', offline: false);
      expect(online.map((note) => note['name']), [
        'Second',
        'First edited',
        'General',
      ]);
      expect(online[1]['color_hex'], '#C62828');
      expect(online.any((note) => note['pending_sync'] == true), isFalse);
      await expectLater(
        reopened.saveOffline(
          'shop',
          templateId: online.last['id'].toString(),
          name: 'Other',
          body: 'General text',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'a remote edit between create and reread is never replayed over',
    () async {
      final api = _TemplatesApi()
        ..afterCreate = (note) {
          note['name'] = 'Renamed elsewhere';
          note['body'] = 'Remote text changed before create returned';
          note['sort_order'] = 999;
          note['row_version'] = 2;
        };
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline(
        'shop',
        name: 'Reminder',
        body: 'Original create body',
        colorHex: '#C62828',
      );
      final result = await service.available('shop', offline: false);
      expect(result.single['name'], 'Renamed elsewhere');
      expect(
        result.single['body'],
        'Remote text changed before create returned',
      );
      expect(result.single['sort_order'], 999);
      expect(result.single['color_hex'], '#C62828');
      expect(result.single['pending_sync'], isNull);
      expect(api.patches, 1); // Only the color absent from the legacy create.
      expect(
        api.server.single['body'],
        'Remote text changed before create returned',
      );
    },
  );

  test(
    'a remote color change immediately after creation conflicts safely',
    () async {
      final api = _TemplatesApi()
        ..afterCreate = (note) {
          note['body'] = 'Concurrent server body';
          note['color_hex'] = '#2E7D32';
          note['row_version'] = 2;
        };
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline(
        'shop',
        name: 'Reminder',
        body: 'Original create body',
        colorHex: '#C62828',
      );
      final result = await service.available('shop', offline: false);
      expect(result.single['color_hex'], '#C62828');
      expect(result.single['pending_sync'], isTrue);
      expect(result.single['sync_error'], contains('changed elsewhere'));
      expect(api.patches, 0);
      expect(api.server.single['body'], 'Concurrent server body');
      expect(api.server.single['color_hex'], '#2E7D32');
    },
  );

  test(
    'editing after a lost create response updates the original server row',
    () async {
      final api = _TemplatesApi()..simulateLostResponse = true;
      final service = LocalStandardNotesService(api: api);
      final note = await service.saveOffline(
        'shop',
        name: 'Original',
        body: 'Original body',
      );
      await expectLater(service.flushPending('shop'), throwsStateError);
      await service.saveOffline(
        'shop',
        templateId: note['id'].toString(),
        name: 'Renamed',
        body: 'Revised body',
        colorHex: '#00796B',
      );
      final synced = await service.available('shop', offline: false);
      expect(api.saves, 1);
      expect(api.server, hasLength(1));
      expect(synced.single['name'], 'Renamed');
      expect(synced.single['body'], 'Revised body');
      expect(synced.single['pending_sync'], isNull);
    },
  );

  test(
    'an editor with the previous local ID can save after background sync',
    () async {
      final service = LocalStandardNotesService(api: _TemplatesApi());
      final note = await service.saveOffline(
        'shop',
        name: 'Reminder',
        body: 'Original body',
      );
      await service.available('shop', offline: false);
      await service.available('shop', offline: false);
      final saved = await service.saveOffline(
        'shop',
        templateId: note['id'].toString(),
        name: 'Reminder',
        body: 'Edited while the server was syncing',
      );
      expect(saved['id'], startsWith('remote-'));
      expect(saved['body'], 'Edited while the server was syncing');
    },
  );

  test(
    'lost patch response is acknowledged without replaying an update',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline(
        'shop',
        name: 'Reminder',
        body: 'Original body',
      );
      final initial = await service.available('shop', offline: false);
      await service.saveOffline(
        'shop',
        templateId: initial.single['id'].toString(),
        name: 'Reminder',
        body: 'Updated body',
        colorHex: '#6A1B9A',
      );
      api.simulateLostPatchResponse = true;
      await expectLater(service.flushPending('shop'), throwsStateError);
      await service.flushPending('shop');
      expect(api.patches, 1);
      expect((await service.cached('shop')).single['pending_sync'], isNull);
    },
  );

  test('same-name conflict never drops local unsent text', () async {
    final api = _TemplatesApi();
    final service = LocalStandardNotesService(api: api);
    await service.saveOffline('shop', name: 'Reminder', body: 'My local text');
    api.server.add({
      'id': 'other',
      'name': 'Reminder',
      'body': 'Someone else text',
      'row_version': 1,
    });
    final result = await service.available('shop', offline: false);
    expect(result.single['body'], 'My local text');
    expect(result.single['pending_sync'], isTrue);
    expect(result.single['sync_error'], contains('conflicts'));
    expect(api.saves, 0);
  });

  test(
    'concurrent remote body edits conflict without losing either version',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline('shop', name: 'Reminder', body: 'Original');
      final initial = await service.available('shop', offline: false);
      await service.saveOffline(
        'shop',
        templateId: initial.single['id'].toString(),
        name: 'Reminder',
        body: 'My edit',
      );
      api.server.single['body'] = 'Remote edit';
      api.server.single['row_version'] = 2;
      final result = await service.available('shop', offline: false);
      expect(result.single['body'], 'My edit');
      expect(result.single['sync_error'], contains('changed elsewhere'));
      expect(api.server.single['body'], 'Remote edit');
      expect(api.patches, 0);
    },
  );

  test('order-only patches preserve newer remote text', () async {
    final api = _TemplatesApi();
    final service = LocalStandardNotesService(api: api);
    await service.saveOffline('shop', name: 'Reminder', body: 'Original');
    final initial = await service.available('shop', offline: false);
    await service.reorderOffline('shop', [initial.single['id'].toString()]);
    api.server.single['body'] = 'Remote edit';
    api.server.single['row_version'] = 2;
    final result = await service.available('shop', offline: false);
    expect(result.single['body'], 'Remote edit');
    expect(api.server.single['body'], 'Remote edit');
    expect(result.single['pending_sync'], isNull);
  });

  test(
    'missing backend patch support keeps color changes for a later retry',
    () async {
      final api = _TemplatesApi()..failPatches = true;
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline(
        'shop',
        name: 'Reminder',
        body: 'Body',
        colorHex: '#C62828',
      );
      final first = await service.available('shop', offline: false);
      expect(first.single['pending_sync'], isTrue);
      expect(first.single['color_hex'], '#C62828');
      expect(api.server, hasLength(1));
      api.failPatches = false;
      final synced = await service.available('shop', offline: false);
      expect(api.saves, 1);
      expect(synced.single['pending_sync'], isNull);
      expect(synced.single['color_hex'], '#C62828');
    },
  );

  test(
    'concurrent instances cannot overwrite a save with a stale refresh',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline('shop', name: 'Reminder', body: 'Original');
      final initial = await service.available('shop', offline: false);
      api.readBlock = Completer<void>();
      api.readStarted = Completer<void>();
      final refresh = service.available('shop', offline: false);
      await api.readStarted!.future;
      final other = LocalStandardNotesService(api: api);
      final edit = other.saveOffline(
        'shop',
        templateId: initial.single['id'].toString(),
        name: 'Reminder',
        body: 'Latest local edit',
        colorHex: '#2E7D32',
      );
      api.readBlock!.complete();
      await refresh;
      await edit;
      final stored = await service.cached('shop');
      expect(stored.single['body'], 'Latest local edit');
      expect(stored.single['pending_sync'], isTrue);
    },
  );

  test(
    'a refresh during editing keeps the editor original as conflict base',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline('shop', name: 'Reminder', body: 'Original');
      final original = (await service.available('shop', offline: false)).single;
      api.server.single['body'] = 'Remote edit while editor open';
      api.server.single['row_version'] = 2;
      await service.available('shop', offline: false);
      await service.saveOffline(
        'shop',
        templateId: original['id'].toString(),
        original: original,
        name: 'Reminder',
        body: 'My editor change',
      );
      final stored = await service.available('shop', offline: false);
      expect(stored.single['body'], 'My editor change');
      expect(stored.single['sync_error'], contains('changed elsewhere'));
      expect(api.server.single['body'], 'Remote edit while editor open');
      expect(api.patches, 0);
    },
  );

  test(
    'unchanged stale editor fields cannot overwrite newer remote values',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.saveOffline('shop', name: 'Reminder', body: 'Original');
      final original = (await service.available('shop', offline: false)).single;
      api.server.single['body'] = 'New remote text';
      api.server.single['row_version'] = 2;
      await service.available('shop', offline: false);
      await service.saveOffline(
        'shop',
        templateId: original['id'].toString(),
        original: original,
        name: 'Reminder',
        body: 'Original',
        colorHex: '#C62828',
      );
      final stored = await service.available('shop', offline: false);
      expect(stored.single['body'], 'New remote text');
      expect(stored.single['color_hex'], '#C62828');
      expect(stored.single['pending_sync'], isNull);
    },
  );

  test('business caches remain isolated', () async {
    final service = LocalStandardNotesService(api: _TemplatesApi());
    await service.saveOffline('shop-a', name: 'Private', body: 'Shop A');
    expect(await service.cached('shop-b'), isEmpty);
  });
  test(
    'category order including empty groups survives a fresh instance',
    () async {
      final api = _TemplatesApi();
      final service = LocalStandardNotesService(api: api);
      await service.reorderOffline(
        'shop',
        const [],
        categoryOrder: const [
          'advisory',
          'general',
          'inspection',
          'warranty',
          'service',
        ],
      );
      final reopened = LocalStandardNotesService(api: api);
      expect(await reopened.categoryOrder('shop'), [
        'advisory',
        'inspection',
        'warranty',
        'service',
        'general',
      ]);
      expect(await reopened.categoryOrder('other-shop'), isNull);
      await reopened.available('shop', offline: false);
      expect((await reopened.categoryOrder('shop'))!.first, 'advisory');
    },
  );

  test(
    'ordering accepts local identities after background synchronization',
    () async {
      final service = LocalStandardNotesService(api: _TemplatesApi());
      final first = await service.saveOffline(
        'shop',
        name: 'First',
        body: 'One',
      );
      final second = await service.saveOffline(
        'shop',
        name: 'Second',
        body: 'Two',
      );
      await service.available('shop', offline: false);
      await service.reorderOffline('shop', [
        second['id'].toString(),
        first['id'].toString(),
      ]);
      expect((await service.cached('shop')).map((note) => note['name']), [
        'Second',
        'First',
      ]);
    },
  );

  test('General Note and Thank You remain in the final category', () async {
    final service = LocalStandardNotesService(api: _TemplatesApi());
    for (final name in ['General Note', 'Thank You']) {
      final note = await service.saveOffline(
        'shop',
        name: name,
        body: '$name text',
        categoryKey: 'service',
      );
      expect(note['category_key'], 'general');
      await expectLater(
        service.saveOffline(
          'shop',
          templateId: note['id'].toString(),
          name: 'Renamed $name',
          body: '$name text',
        ),
        throwsStateError,
      );
    }
    await service.saveOffline(
      'shop',
      name: 'Service A',
      body: 'Service A original',
    );
    expect((await service.cached('shop')).first['name'], 'Service A');
  });

  test(
    'style and category edits preserve saved warranty and service bodies',
    () async {
      const warranty =
          'Warranty: 12 months / 12,000 miles.\n\nOriginal exclusions.';
      const service = 'Service A: original checklist.\nRetorque after service.';
      final api = _TemplatesApi()
        ..server.addAll([
          {
            'id': 'w',
            'name': 'Standard Warranty',
            'body': warranty,
            'row_version': 1,
            'category_key': 'warranty',
            'color_hex': '#1565C0',
            'sort_order': 100,
          },
          {
            'id': 's',
            'name': 'Service A',
            'body': service,
            'row_version': 1,
            'category_key': 'service',
            'color_hex': '#1565C0',
            'sort_order': 100,
          },
        ]);
      final notes = LocalStandardNotesService(api: api);
      final original = await notes.available('shop', offline: false);
      await notes.saveOffline(
        'shop',
        templateId: 'w',
        original: original.first,
        name: 'Standard Warranty',
        body: warranty,
        categoryKey: 'warranty',
        colorHex: '#2E7D32',
      );
      await notes.reorderOffline(
        'shop',
        ['s', 'w'],
        categoryOrder: ['service', 'warranty'],
      );
      await notes.available('shop', offline: false);
      expect(api.server.first['body'], warranty);
      expect(api.server.last['body'], service);
      expect(
        (await LocalStandardNotesService(api: api).cached('shop')).last['body'],
        warranty,
      );
    },
  );
}
