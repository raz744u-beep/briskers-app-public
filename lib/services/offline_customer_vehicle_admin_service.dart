import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class OfflineCustomerVehicleAdminService {
  OfflineCustomerVehicleAdminService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;

  Future<Map<String, dynamic>> queueCustomerProfile(
    String businessId,
    String customerId, {
    required String name,
    String? phone,
    String? email,
    required Map<String, dynamic> billingAddress,
  }) async {
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        UPDATE local_customers
        SET display_name = ?, phone = ?, list_phone = ?,
            email = ?, list_email = ?, billing_address_json = ?,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [name, phone, phone, email, email, jsonEncode(billingAddress), businessId, customerId],
      );
      await _database.customStatement(
        'UPDATE local_jobs SET customer_name = ? WHERE business_id = ? AND customer_id = ?',
        [name, businessId, customerId],
      );
      await _mergeOutbox(businessId, 'customer_profile', customerId, {
        'name': name,
        'phone': phone,
        'email': email,
        'billing_address': billingAddress,
      });
    });
    return {
      'id': customerId,
      'name': name,
      'phone': phone,
      'email': email,
      'billing_address': billingAddress,
      '_local_snapshot': true,
    };
  }

  Future<void> queueProblemFlag(
    String businessId,
    String customerId, {
    required bool flagged,
    String? note,
  }) async {
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        UPDATE local_customers
        SET problem_flag = ?, problem_flag_note = ?, sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [flagged ? 1 : 0, note, businessId, customerId],
      );
      await _database.customStatement(
        '''
        UPDATE local_jobs
        SET customer_problem_flag = ?, customer_problem_flag_note = ?
        WHERE business_id = ? AND customer_id = ?
        ''',
        [flagged ? 1 : 0, note, businessId, customerId],
      );
      await _mergeOutbox(businessId, 'customer_flag', customerId, {
        'flagged': flagged,
        'note': note,
      });
    });
  }

  Future<String> queueVehicle(
    String businessId,
    String customerId, {
    String? vehicleId,
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
    String? keyPassword,
  }) async {
    final creating = vehicleId == null || vehicleId.isEmpty;
    final id = creating
        ? 'local-vehicle-${DateTime.now().microsecondsSinceEpoch}'
        : vehicleId;

    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO local_vehicles (
          id, business_id, year, make, model, vin, license_plate,
          license_state, mileage, color, key_password, sync_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
        ON CONFLICT(id) DO UPDATE SET
          year=excluded.year, make=excluded.make, model=excluded.model,
          vin=excluded.vin, license_plate=excluded.license_plate,
          license_state=excluded.license_state, mileage=excluded.mileage,
          color=excluded.color, key_password=excluded.key_password,
          sync_state='pending'
        ''',
        [id, businessId, year, make, model, vin, licensePlate, licenseState, mileage?.toDouble(), color, keyPassword],
      );
      if (creating) {
        await _database.customStatement(
          '''
          INSERT OR REPLACE INTO local_customer_vehicles
            (business_id, customer_id, vehicle_id, is_primary)
          VALUES (?, ?, ?, 0)
          ''',
          [businessId, customerId, id],
        );
      }
      await _mergeOutbox(
        businessId,
        creating ? 'vehicle_create' : 'vehicle_update',
        id,
        {
          'customer_id': customerId,
          'make': make,
          'model': model,
          'year': year,
          'vin': vin,
          'license_plate': licensePlate,
          'license_state': licenseState,
          'mileage': mileage,
          'color': color,
          'key_password': keyPassword,
        },
      );
    });
    return id;
  }

  Future<void> _mergeOutbox(
    String businessId,
    String entityType,
    String entityId,
    Map<String, dynamic> payload,
  ) async {
    final existing = await _database.customSelect(
      '''
      SELECT id FROM sync_outbox
      WHERE business_id = ? AND entity_type = ? AND entity_id = ?
        AND state = 'pending'
      ORDER BY id DESC LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(entityType),
        Variable<String>(entityId),
      ],
    ).get();

    if (existing.isNotEmpty) {
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json = ?, last_error = NULL WHERE id = ?',
        [jsonEncode(payload), existing.first.read<int>('id')],
      );
    } else {
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, state, attempt_count, created_at
        ) VALUES (?, ?, ?, 'update', ?, 'pending', 0, ?)
        ''',
        [businessId, entityType, entityId, jsonEncode(payload), DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000],
      );
    }
  }

  Future<void> flush(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, entity_type, entity_id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type IN ('customer_profile','customer_flag','vehicle_create','vehicle_update')
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in rows) {
      final outboxId = row.read<int>('id');
      final type = row.read<String>('entity_type');
      final entityId = row.read<String>('entity_id');
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      try {
        if (type == 'customer_profile') {
          await _api.updateCustomerProfile(
            businessId,
            entityId,
            name: payload['name']?.toString() ?? '',
            phone: payload['phone']?.toString(),
            email: payload['email']?.toString(),
            billingAddress: Map<String, dynamic>.from(
              payload['billing_address'] as Map? ?? const {},
            ),
          );
          await _database.customStatement(
            "UPDATE local_customers SET sync_state = 'synced' WHERE business_id = ? AND id = ?",
            [businessId, entityId],
          );
        } else if (type == 'customer_flag') {
          await _api.setCustomerProblemFlag(
            businessId,
            entityId,
            flagged: payload['flagged'] == true,
            note: payload['note']?.toString(),
          );
        } else if (type == 'vehicle_update') {
          await _api.updateVehicle(
            businessId,
            entityId,
            make: payload['make']?.toString() ?? '',
            model: payload['model']?.toString() ?? '',
            year: int.tryParse(payload['year']?.toString() ?? ''),
            vin: payload['vin']?.toString(),
            licensePlate: payload['license_plate']?.toString(),
            licenseState: payload['license_state']?.toString(),
            mileage: num.tryParse(payload['mileage']?.toString() ?? ''),
            color: payload['color']?.toString(),
            keyPassword: payload['key_password']?.toString(),
          );
          await _database.customStatement(
            "UPDATE local_vehicles SET sync_state = 'synced' WHERE business_id = ? AND id = ?",
            [businessId, entityId],
          );
        } else if (type == 'vehicle_create') {
          final serverId = await _api.createVehicle(
            businessId,
            payload['customer_id']?.toString() ?? '',
            make: payload['make']?.toString() ?? '',
            model: payload['model']?.toString() ?? '',
            year: int.tryParse(payload['year']?.toString() ?? ''),
            vin: payload['vin']?.toString(),
            licensePlate: payload['license_plate']?.toString(),
            licenseState: payload['license_state']?.toString(),
            mileage: num.tryParse(payload['mileage']?.toString() ?? ''),
            color: payload['color']?.toString(),
            keyPassword: payload['key_password']?.toString(),
          );
          await _database.customStatement(
            'UPDATE local_customer_vehicles SET vehicle_id = ? WHERE business_id = ? AND vehicle_id = ?',
            [serverId, businessId, entityId],
          );
          await _database.customStatement(
            "UPDATE local_vehicles SET id = ?, sync_state = 'synced' WHERE business_id = ? AND id = ?",
            [serverId, businessId, entityId],
          );
        }
        await _database.customStatement(
          'DELETE FROM sync_outbox WHERE id = ?',
          [outboxId],
        );
      } catch (error) {
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?, last_error = ?
          WHERE id = ?
          ''',
          [DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000, error.toString(), outboxId],
        );
        rethrow;
      }
    }
  }
}
