import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/kiosk_registration_service.dart';

class _FakeKioskApi extends BriskersApi {
  _FakeKioskApi({this.conflict = false});

  final bool conflict;
  Map<String, dynamic>? lastRegistration;

  @override
  Future<Map<String, dynamic>> kioskSettings(
    String businessId,
  ) async {
    return {
      'disclaimer': {
        'id': 'disclaimer-1',
        'version': 4,
        'text': 'Test disclaimer text',
        'created_at': '2026-10-01T00:00:00Z',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> kioskRegisterWalkIn(
    String businessId, {
    required String operationId,
    required String name,
    required String phone,
    required String email,
    required int vehicleYear,
    required String vehicleMake,
    required String vehicleModel,
    required String reason,
    required bool createOnlineAccount,
    required String disclaimerId,
    required int disclaimerVersion,
    required DateTime acceptedAtDevice,
  }) async {
    lastRegistration = {
      'business_id': businessId,
      'operation_id': operationId,
      'name': name,
      'phone': phone,
      'email': email,
      'vehicle_year': vehicleYear,
      'vehicle_make': vehicleMake,
      'vehicle_model': vehicleModel,
      'reason': reason,
      'create_online_account': createOnlineAccount,
      'disclaimer_id': disclaimerId,
      'disclaimer_version': disclaimerVersion,
      'accepted_at_device': acceptedAtDevice.toUtc().toIso8601String(),
    };

    if (conflict) {
      return {
        'status': 'conflict',
        'reason': 'multiple_customer_phone_matches',
      };
    }

    return {
      'status': 'applied',
      'customer_id': 'customer-1',
      'vehicle_id': 'vehicle-1',
      'job_id': 'job-1',
      'customer_created': true,
      'vehicle_created': true,
      'account_request_status': 'pending',
      'disclaimer_version': disclaimerVersion,
    };
  }
}

void main() {
  test('kiosk settings cache preserves disclaimer version and text', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = KioskRegistrationService(
      api: _FakeKioskApi(),
      database: database,
    );

    final disclaimer = await service.refreshSettings('business-1');

    expect(disclaimer, isNotNull);
    expect(disclaimer!['id'], 'disclaimer-1');
    expect(disclaimer['version'], 4);
    expect(disclaimer['text'], 'Test disclaimer text');

    final cached = await service.loadDisclaimer('business-1');
    expect(cached!['version'], 4);
    expect(cached['text'], 'Test disclaimer text');

    await database.close();
  });

  test('walk-in queues locally then flushes idempotent payload', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeKioskApi();
    final service = KioskRegistrationService(
      api: api,
      database: database,
    );

    final disclaimer = await service.refreshSettings('business-1');
    final acceptedAt = DateTime.utc(2026, 10, 1, 1, 2, 3);

    final operationId = await service.queueWalkIn(
      'business-1',
      name: 'Jane Customer',
      phone: '5045551234',
      email: 'jane@example.com',
      vehicleYear: 2020,
      vehicleMake: 'BMW',
      vehicleModel: 'X5',
      reason: 'Brake noise',
      createOnlineAccount: true,
      disclaimerId: disclaimer!['id'].toString(),
      disclaimerVersion: disclaimer['version'] as int,
      disclaimerText: disclaimer['text'].toString(),
      acceptedAtDevice: acceptedAt,
    );

    final queued = await database.customSelect(
      '''
      SELECT payload_json, state
      FROM sync_outbox
      WHERE entity_type = 'kiosk_walkin_registration'
      ''',
    ).getSingle();

    expect(queued.read<String>('state'), 'pending');
    final payload = Map<String, dynamic>.from(
      jsonDecode(queued.read<String>('payload_json')) as Map,
    );
    expect(payload['operation_id'], operationId);
    expect(payload['disclaimer_version'], 4);
    expect(payload['disclaimer_text_snapshot'], 'Test disclaimer text');
    expect(payload['accepted_at_device'], acceptedAt.toIso8601String());

    final results = await service.flush('business-1');

    expect(results[operationId]!['status'], 'applied');
    expect(api.lastRegistration!['name'], 'Jane Customer');
    expect(api.lastRegistration!['vehicle_make'], 'BMW');
    expect(api.lastRegistration!['create_online_account'], true);
    expect(api.lastRegistration!['disclaimer_version'], 4);

    final outbox = await database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE entity_type = 'kiosk_walkin_registration'
      ''',
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    await database.close();
  });

  test('duplicate-phone conflict remains preserved in outbox', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = KioskRegistrationService(
      api: _FakeKioskApi(conflict: true),
      database: database,
    );

    final disclaimer = await service.refreshSettings('business-1');
    final operationId = await service.queueWalkIn(
      'business-1',
      name: 'Jane Customer',
      phone: '5045551234',
      email: 'jane@example.com',
      vehicleYear: 2020,
      vehicleMake: 'BMW',
      vehicleModel: 'X5',
      reason: 'Brake noise',
      createOnlineAccount: false,
      disclaimerId: disclaimer!['id'].toString(),
      disclaimerVersion: disclaimer['version'] as int,
      disclaimerText: disclaimer['text'].toString(),
      acceptedAtDevice: DateTime.utc(2026, 10, 1, 1, 2, 3),
    );

    final results = await service.flush('business-1');
    expect(
      results[operationId]!['reason'],
      'multiple_customer_phone_matches',
    );

    final outbox = await database.customSelect(
      '''
      SELECT state, last_error
      FROM sync_outbox
      WHERE entity_type = 'kiosk_walkin_registration'
      ''',
    ).getSingle();

    expect(outbox.read<String>('state'), 'conflict');
    expect(
      outbox.read<String>('last_error'),
      contains('multiple_customer_phone_matches'),
    );

    await database.close();
  });
}
