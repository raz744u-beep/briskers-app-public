import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class KioskRegistrationService {
  KioskRegistrationService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final Random _random = Random.secure();

  Future<Map<String, dynamic>?> refreshSettings(
    String businessId,
  ) async {
    final response = await _api.kioskSettings(businessId);
    final raw = response['disclaimer'];

    await _database.transaction(() async {
      await _database.customStatement(
        'DELETE FROM local_kiosk_settings WHERE business_id = ?',
        [businessId],
      );

      if (raw is Map) {
        final disclaimer = Map<String, dynamic>.from(raw);
        await _database.customStatement(
          '''
          INSERT INTO local_kiosk_settings (
            business_id, disclaimer_id, disclaimer_version,
            disclaimer_text, server_updated_at
          ) VALUES (?, ?, ?, ?, ?)
          ''',
          [
            businessId,
            disclaimer['id']?.toString(),
            int.tryParse(disclaimer['version']?.toString() ?? ''),
            disclaimer['text']?.toString(),
            _unix(
              DateTime.tryParse(
                disclaimer['created_at']?.toString() ?? '',
              ),
            ),
          ],
        );
      }
    });

    return loadDisclaimer(businessId);
  }

  Future<Map<String, dynamic>?> loadDisclaimer(
    String businessId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_kiosk_settings
      WHERE business_id = ?
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    if (rows.isEmpty) return null;
    final row = rows.first;
    final id = row.readNullable<String>('disclaimer_id');
    final version = row.readNullable<int>('disclaimer_version');
    final text = row.readNullable<String>('disclaimer_text');

    if (id == null ||
        id.isEmpty ||
        version == null ||
        text == null ||
        text.trim().isEmpty) {
      return null;
    }

    return <String, dynamic>{
      'id': id,
      'version': version,
      'text': text,
      'created_at': _isoFromDb(row.data['server_updated_at']),
    };
  }

  Future<String> queueWalkIn(
    String businessId, {
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
    required String disclaimerText,
    required DateTime acceptedAtDevice,
  }) async {
    final operationId = _operationId('kiosk-walkin');

    await _database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, base_row_version, state, attempt_count,
        created_at, last_attempt_at, last_error
      ) VALUES (
        ?, 'kiosk_walkin_registration', ?, 'register',
        ?, NULL, 'pending', 0, ?, NULL, NULL
      )
      ''',
      [
        businessId,
        operationId,
        jsonEncode({
          'operation_id': operationId,
          'name': name.trim(),
          'phone': phone,
          'email': email.trim(),
          'vehicle_year': vehicleYear,
          'vehicle_make': vehicleMake.trim(),
          'vehicle_model': vehicleModel.trim(),
          'reason': reason.trim(),
          'create_online_account': createOnlineAccount,
          'disclaimer_id': disclaimerId,
          'disclaimer_version': disclaimerVersion,
          'disclaimer_text_snapshot': disclaimerText,
          'accepted_at_device':
              acceptedAtDevice.toUtc().toIso8601String(),
        }),
        _unix(DateTime.now().toUtc()),
      ],
    );

    return operationId;
  }

  Future<Map<String, Map<String, dynamic>>> flush(
    String businessId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'kiosk_walkin_registration'
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    final results = <String, Map<String, dynamic>>{};

    for (final queued in rows) {
      final freshRows = await _database.customSelect(
        '''
        SELECT *
        FROM sync_outbox
        WHERE id = ? AND state = 'pending'
        LIMIT 1
        ''',
        variables: [
          Variable<int>(queued.read<int>('id')),
        ],
      ).get();

      if (freshRows.isEmpty) continue;
      final row = freshRows.first;

      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      final operationId =
          payload['operation_id']?.toString() ?? '';

      try {
        final acceptedAt = DateTime.tryParse(
          payload['accepted_at_device']?.toString() ?? '',
        );
        if (acceptedAt == null) {
          throw StateError('Queued registration is missing acceptance time.');
        }

        final response = await _api.kioskRegisterWalkIn(
          businessId,
          operationId: operationId,
          name: payload['name']?.toString() ?? '',
          phone: payload['phone']?.toString() ?? '',
          email: payload['email']?.toString() ?? '',
          vehicleYear: int.tryParse(
                payload['vehicle_year']?.toString() ?? '',
              ) ??
              0,
          vehicleMake: payload['vehicle_make']?.toString() ?? '',
          vehicleModel: payload['vehicle_model']?.toString() ?? '',
          reason: payload['reason']?.toString() ?? '',
          createOnlineAccount:
              payload['create_online_account'] == true,
          disclaimerId:
              payload['disclaimer_id']?.toString() ?? '',
          disclaimerVersion: int.tryParse(
                payload['disclaimer_version']?.toString() ?? '',
              ) ??
              0,
          acceptedAtDevice: acceptedAt,
        );

        results[operationId] = response;

        if (response['status']?.toString() == 'conflict') {
          await _database.customStatement(
            '''
            UPDATE sync_outbox
            SET state = 'conflict',
                attempt_count = attempt_count + 1,
                last_attempt_at = ?,
                last_error = ?
            WHERE id = ?
            ''',
            [
              _unix(DateTime.now().toUtc()),
              jsonEncode(response),
              row.read<int>('id'),
            ],
          );
          break;
        }

        await _database.customStatement(
          'DELETE FROM sync_outbox WHERE id = ?',
          [row.read<int>('id')],
        );
      } catch (error) {
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [
            _unix(DateTime.now().toUtc()),
            error.toString(),
            row.read<int>('id'),
          ],
        );
        break;
      }
    }

    return results;
  }

  String _operationId(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final a = _random.nextInt(0x7fffffff).toRadixString(16);
    final b = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-$micros-$a-$b';
  }

  int? _unix(DateTime? value) =>
      value == null
          ? null
          : value.toUtc().millisecondsSinceEpoch ~/ 1000;

  String? _isoFromDb(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return DateTime.tryParse(value.toString())
        ?.toUtc()
        .toIso8601String();
  }
}
