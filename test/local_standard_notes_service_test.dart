import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_standard_notes_service.dart';

class _TemplatesApi extends BriskersApi {
  final server = <Map<String, dynamic>>[];
  int saves = 0;
  bool simulateLostResponse = false;
  @override
  Future<List<Map<String, dynamic>>> documentNoteTemplates(
    String businessId, {bool includeInactive = false}
  ) async => server.map((note) => Map<String, dynamic>.from(note)).toList();

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
    server.add({'id': 'remote-1', 'name': name, 'body': body});
    if (simulateLostResponse) {
      simulateLostResponse = false;
      throw StateError('Simulated lost response after server commit');
    }
    return 'remote-1';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('standard templates can be created and retrieved offline', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _TemplatesApi();
    final service = LocalStandardNotesService(api: api);
    final created = await service.saveOffline('shop',
      name: 'Oil change note', body: 'Check oil level');
    expect(created['pending_sync'], isTrue);
    final offline = await service.available('shop', offline: true);
    expect(offline, hasLength(1));
    expect(offline.single['body'], 'Check oil level');
    expect(api.saves, 0);
    await expectLater(service.saveOffline('shop',
      name: 'oil CHANGE NOTE', body: 'Duplicate'), throwsStateError);
  });

  test('server template creation retries safely after interrupted response', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _TemplatesApi()..simulateLostResponse = true;
    final service = LocalStandardNotesService(api: api);
    await service.saveOffline('shop', name: 'Reminder',
      body: 'Inspect before release');
    await expectLater(service.flushPending('shop'), throwsStateError);
    expect(api.server, hasLength(1));
    await service.flushPending('shop');
    expect(api.saves, 1);
    expect((await service.cached('shop')).single['pending_sync'], isNull);
  });
}
