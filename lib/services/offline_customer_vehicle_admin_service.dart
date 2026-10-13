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

  Future<String> queueCustomerCreate(
    String businessId, {
    required String name,
    String? phone,
    String? email,
    Map<String,dynamic> billingAddress = const {},
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Customer name required.');
    final id='local-customer-${DateTime.now().microsecondsSinceEpoch}';
    await _database.transaction(() async {
      await _database.customStatement(
        """INSERT INTO local_customers
          (id,business_id,display_name,email,list_email,phone,list_phone,
           billing_address_json,sync_state)
           VALUES(?,?,?,?,?,?,?,?, 'pending')""",
        [id,businessId,name.trim(),email,email,phone,phone,
         jsonEncode(billingAddress)],
      );
      await _database.customStatement(
        """INSERT INTO sync_outbox
          (business_id,entity_type,entity_id,operation,payload_json,
           state,attempt_count,created_at)
           VALUES (?,'customer_create',?,'create',?,'pending',0,?)""",
        [businessId,id,jsonEncode({
          'operation_id':'customer-create-$id',
          'name':name.trim(),
          'phone':phone,'email':email,'billing_address':billingAddress,
        }),DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000],
      );
    });
    return id;
  }

  Future<Map<String, dynamic>> queueCustomerProfile(
    String businessId,
    String customerId, {
    required String name,
    String? phone,
    String? email,
    required Map<String, dynamic> billingAddress,
  }) async {
    await _database.transaction(() async {
      if (customerId.startsWith('local-customer-')) {
        final pending=await _database.customSelect(
          """SELECT id,payload_json,attempt_count,last_attempt_at
             FROM sync_outbox WHERE business_id=? AND entity_type='customer_create'
             AND entity_id=? AND state='pending' LIMIT 1""",
          variables:[Variable<String>(businessId),Variable<String>(customerId)],
        ).get();
        if (pending.length!=1 ||
            pending.single.read<int>('attempt_count')>0 ||
            pending.single.readNullable<int>('last_attempt_at')!=null) {
          throw StateError('Customer creation is synchronizing; reconcile first.');
        }
        final data=Map<String,dynamic>.from(
          jsonDecode(pending.single.read<String>('payload_json')) as Map);
        data['name']=name.trim();
        data['phone']=phone;
        data['email']=email;
        data['billing_address']=billingAddress;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [jsonEncode(data),pending.single.read<int>('id')],
        );
        await _database.customStatement(
          """UPDATE local_customers SET display_name=?,phone=?,list_phone=?,
             email=?,list_email=?,billing_address_json=?
             WHERE business_id=? AND id=?""",
          [name.trim(),phone,phone,email,email,jsonEncode(billingAddress),
           businessId,customerId],
        );
        return;
      }
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
    final creating = vehicleId == null ||
        vehicleId.isEmpty || vehicleId.startsWith('local-vehicle-');
    final id = vehicleId == null || vehicleId.isEmpty
        ? 'local-vehicle-${DateTime.now().microsecondsSinceEpoch}'
        : vehicleId;

    if (id.startsWith('local-vehicle-')) {
      final rows=await _database.customSelect(
        """SELECT attempt_count,last_attempt_at FROM sync_outbox
           WHERE business_id=? AND entity_type='vehicle_create'
             AND entity_id=? AND state='pending' LIMIT 1""",
        variables:[Variable<String>(businessId),Variable<String>(id)],
      ).get();
      if (rows.isNotEmpty &&
          (rows.single.read<int>('attempt_count') > 0 ||
           rows.single.readNullable<int>('last_attempt_at') != null)) {
        throw StateError('Vehicle creation is being reconciled; edit after sync.');
      }
    }
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
          if (creating) 'idempotent_v1': true,
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
      SELECT id, attempt_count, last_attempt_at FROM sync_outbox
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
      if (entityType == 'vehicle_create' &&
          (existing.first.read<int>('attempt_count') > 0 ||
           existing.first.readNullable<int>('last_attempt_at') != null)) {
        throw StateError('Vehicle upload already attempted; reconcile before editing.');
      }
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

  /// Atomic remapping after a vehicle receives its server identity.
  Future<void> reconcileCreatedVehicleId(
    String businessId,String entityId,String serverId,int outboxId,
  ) async {
    // Remap the new server vehicle ID everywhere atomically.
          // Appointment create payloads must never retain a local vehicle ID.
    await _database.transaction(() async {
            await _database.customStatement(
              'UPDATE local_customer_vehicles SET vehicle_id=? WHERE business_id=? AND vehicle_id=?',
              [serverId,businessId,entityId],
            );
            await _database.customStatement(
              'UPDATE local_appointments SET vehicle_id=? WHERE business_id=? AND vehicle_id=?',
              [serverId,businessId,entityId],
            );
            await _database.customStatement(
              'UPDATE local_jobs SET vehicle_id=? WHERE business_id=? AND vehicle_id=?',
              [serverId,businessId,entityId],
            );
            final jobCreates = await _database.customSelect(
              """SELECT id,payload_json FROM sync_outbox WHERE business_id=?
                 AND entity_type='job_create' AND state='pending'""",
              variables:[Variable<String>(businessId)],
            ).get();
            for (final pending in jobCreates) {
              final data=Map<String,dynamic>.from(
                jsonDecode(pending.read<String>('payload_json')) as Map);
              if (data['vehicle_id']?.toString()!=entityId) continue;
              data['vehicle_id']=serverId;
              await _database.customStatement(
                'UPDATE sync_outbox SET payload_json=? WHERE id=?',
                [jsonEncode(data),pending.read<int>('id')],
              );
            }
            // Re-key every dependent queued write, including document drafts
            // and edits against provisional Jobs. Otherwise an offline invoice
            // can repeatedly submit a local vehicle ID to a UUID RPC field.
            final dependentWrites = await _database.customSelect(
              """SELECT id,payload_json FROM sync_outbox WHERE business_id=?
                 AND state='pending' AND entity_type IN
                 ('document_draft_create','job_admin','job_create')""",
              variables:[Variable<String>(businessId)],
            ).get();
            for (final pending in dependentWrites) {
              final data=Map<String,dynamic>.from(
                jsonDecode(pending.read<String>('payload_json')) as Map);
              if (data['vehicle_id']?.toString()!=entityId) continue;
              data['vehicle_id']=serverId;
              await _database.customStatement(
                'UPDATE sync_outbox SET payload_json=?,last_error=NULL WHERE id=?',
                [jsonEncode(data),pending.read<int>('id')],
              );
            }
            final dependent = await _database.customSelect(
              """SELECT id,payload_json FROM sync_outbox WHERE business_id=?
                 AND entity_type='appointment_create' AND state='pending'""",
              variables:[Variable<String>(businessId)],
            ).get();
            for (final pending in dependent) {
              final data=Map<String,dynamic>.from(
                jsonDecode(pending.read<String>('payload_json')) as Map);
              if (data['vehicle_id']?.toString()!=entityId) continue;
              data['vehicle_id']=serverId;
              await _database.customStatement(
                'UPDATE sync_outbox SET payload_json=? WHERE id=?',
                [jsonEncode(data),pending.read<int>('id')],
              );
            }
            await _database.customStatement(
              "UPDATE local_vehicles SET id=?,sync_state='synced' WHERE business_id=? AND id=?",
              [serverId,businessId,entityId],
            );
            await _database.customStatement(
              'DELETE FROM sync_outbox WHERE id=?',[outboxId],
            );
          });
  }

  Future<void> reconcileCreatedCustomerId(
    String businessId,String localId,String serverId,int queueId,
  ) async {
    await _database.transaction(() async {
      await _database.customStatement(
        'UPDATE local_customer_vehicles SET customer_id=? WHERE business_id=? AND customer_id=?',
        [serverId,businessId,localId],
      );
      await _database.customStatement(
        'UPDATE local_appointments SET customer_id=? WHERE business_id=? AND customer_id=?',
        [serverId,businessId,localId],
      );
      await _database.customStatement(
        'UPDATE local_jobs SET customer_id=? WHERE business_id=? AND customer_id=?',
        [serverId,businessId,localId],
      );
      await _database.customStatement(
        'UPDATE local_documents SET customer_id=? WHERE business_id=? AND customer_id=?',
        [serverId,businessId,localId],
      );
      final rows=await _database.customSelect(
        """SELECT id,payload_json FROM sync_outbox WHERE business_id=?
           AND state='pending'""",
        variables:[Variable<String>(businessId)],
      ).get();
      for (final row in rows) {
        final payload=Map<String,dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map);
        if (payload['customer_id']?.toString()!=localId) continue;
        payload['customer_id']=serverId;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE id=?',
          [jsonEncode(payload),row.read<int>('id')],
        );
      }
      await _database.customStatement(
        "UPDATE local_customers SET id=?,sync_state='synced' WHERE business_id=? AND id=?",
        [serverId,businessId,localId],
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id=?',[queueId],
      );
    });
  }

  Future<void> flush(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, entity_type, entity_id, payload_json, attempt_count
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type IN ('customer_create','customer_profile','customer_flag','vehicle_create','vehicle_update')
        AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final queued in rows) {
      // Re-read after prior customer/vehicle rekeys: the original snapshot
      // contains stale temporary dependency IDs.
      final fresh = await _database.customSelect(
        'SELECT * FROM sync_outbox WHERE id=? AND state=? LIMIT 1',
        variables: [
          Variable<int>(queued.read<int>('id')),
          const Variable<String>('pending'),
        ],
      ).get();
      if (fresh.isEmpty) continue;
      final row = fresh.single;
      final outboxId = row.read<int>('id');
      final type = row.read<String>('entity_type');
      final entityId = row.read<String>('entity_id');
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
       if (type == 'vehicle_create' &&
          row.read<int>('attempt_count') > 0 &&
          payload['idempotent_v1'] != true) {
        await _database.customStatement(
          """UPDATE sync_outbox SET state='conflict',
             last_error='Legacy vehicle create may have succeeded. Reconcile manually.'
             WHERE id=?""",
          [outboxId],
        );
        continue;
      }
      try {
        if (type == 'customer_create') {
          final serverId=await _api.createCustomerOfflineIdempotent(
            businessId,
            operationId:payload['operation_id'].toString(),
            name:payload['name'].toString(),
            phone:payload['phone']?.toString(),
            email:payload['email']?.toString(),
            billingAddress:Map<String,dynamic>.from(
              payload['billing_address'] as Map? ?? const {}),
          );
          await reconcileCreatedCustomerId(
            businessId,entityId,serverId,outboxId,
          );
          continue;
        } else if (type == 'customer_profile') {
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
          final parentCustomer=payload['customer_id']?.toString() ?? '';
          if (parentCustomer.startsWith('local-')) {
            // A vehicle cannot upload before its new customer has a server ID.
            // Keep the existing operation untouched for a later sync pass.
            continue;
          }
          final serverId = await _api.createVehicleOfflineIdempotent(
            businessId,
            payload['customer_id']?.toString() ?? '',
            operationId: 'vehicle-create-$entityId',
            localVehicleId: entityId,
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
          await reconcileCreatedVehicleId(businessId,entityId,serverId,outboxId);
          continue;
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
