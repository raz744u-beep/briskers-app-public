import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class OfflineCustomerVehicleService {
  OfflineCustomerVehicleService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final Random _random = Random.secure();

  Future<String> createLocalCustomer(
    String businessId, {
    required String name,
    String? email,
    String? phone,
  }) async {
    await _requireCapability(
      businessId,
      'customers_create',
      'Connect once with customer-create permission before adding customers offline.',
    );

    final cleanName = name.trim();
    final cleanEmail = _nullIfBlank(email)?.toLowerCase();
    final cleanPhone = _phoneDigits(phone);

    if (cleanName.isEmpty) {
      throw StateError('Customer name is required.');
    }
    if (cleanPhone != null && cleanPhone.length != 10) {
      throw StateError('Phone number must contain 10 digits.');
    }

    final customerId = _uuidV4();
    final operationId = 'customer-create-${_uuidV4()}';
    final contacts = _contactsFor(
      const <dynamic>[],
      email: cleanEmail,
      phone: cleanPhone,
    );

    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO local_customers (
          id, business_id, display_name, is_company,
          email, phone, list_email, list_phone,
          billing_address_json, taxable,
          problem_flag, problem_flag_note, contacts_json,
          server_updated_at, row_version, sync_state
        ) VALUES (
          ?, ?, ?, 0, ?, ?, ?, ?,
          '{}', 1, 0, NULL, ?, NULL, NULL, 'pending'
        )
        ''',
        [
          customerId,
          businessId,
          cleanName,
          cleanEmail,
          cleanPhone,
          cleanEmail,
          cleanPhone,
          jsonEncode(contacts),
        ],
      );

      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'customer_create', ?, 'create', ?, NULL,
          'pending', 0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          customerId,
          jsonEncode({
            'operation_id': operationId,
            'customer_id': customerId,
            'name': cleanName,
            'email': cleanEmail,
            'phone': cleanPhone,
            'problem_flag': false,
            'problem_flag_note': null,
          }),
          _unix(DateTime.now().toUtc()),
        ],
      );
    });

    return customerId;
  }

  Future<Map<String, dynamic>> updateLocalCustomer(
    String businessId,
    String customerId, {
    required String name,
    String? email,
    String? phone,
  }) async {
    await _requireCapability(
      businessId,
      'customers_edit',
      'Customer editing is not available for this account offline.',
    );

    final cleanName = name.trim();
    final cleanEmail = _nullIfBlank(email)?.toLowerCase();
    final cleanPhone = _phoneDigits(phone);

    if (cleanName.isEmpty) {
      throw StateError('Customer name is required.');
    }
    if (cleanPhone != null && cleanPhone.length != 10) {
      throw StateError('Phone number must contain 10 digits.');
    }

    await _database.transaction(() async {
      final row = await _customerRow(businessId, customerId);
      if (row == null) {
        throw StateError('Customer is not available in the local cache.');
      }
      if (row.read<String>('sync_state') == 'conflict') {
        throw StateError(
          'This customer has a sync conflict. The local copy is preserved until it is resolved.',
        );
      }

      final contacts = _contactsFor(
        _jsonList(row.read<String>('contacts_json')),
        email: cleanEmail,
        phone: cleanPhone,
      );

      await _database.customStatement(
        '''
        UPDATE local_customers
        SET display_name = ?,
            email = ?,
            phone = ?,
            list_email = ?,
            list_phone = ?,
            contacts_json = ?,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          cleanName,
          cleanEmail,
          cleanPhone,
          _preferredContact(contacts, 'email'),
          _preferredContact(contacts, 'phone'),
          jsonEncode(contacts),
          businessId,
          customerId,
        ],
      );

      await _queueCustomerMutation(
        businessId,
        customerId,
      );
    });

    return (await _customerMap(businessId, customerId))!;
  }

  Future<Map<String, dynamic>> setLocalProblemFlag(
    String businessId,
    String customerId, {
    required bool flagged,
    String? note,
  }) async {
    await _requireCapability(
      businessId,
      'customers_edit',
      'Customer editing is not available for this account offline.',
    );

    await _database.transaction(() async {
      final row = await _customerRow(businessId, customerId);
      if (row == null) {
        throw StateError('Customer is not available in the local cache.');
      }
      if (row.read<String>('sync_state') == 'conflict') {
        throw StateError(
          'This customer has a sync conflict. The local copy is preserved until it is resolved.',
        );
      }

      final existingNote =
          row.readNullable<String>('problem_flag_note');
      final nextNote = flagged
          ? (_nullIfBlank(note) ?? existingNote)
          : existingNote;

      await _database.customStatement(
        '''
        UPDATE local_customers
        SET problem_flag = ?,
            problem_flag_note = ?,
            sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          flagged ? 1 : 0,
          nextNote,
          businessId,
          customerId,
        ],
      );

      await _queueCustomerMutation(
        businessId,
        customerId,
      );
    });

    return (await _customerMap(businessId, customerId))!;
  }

  Future<String> createLocalVehicle(
    String businessId,
    String customerId, {
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) async {
    await _requireCapability(
      businessId,
      'vehicles_create',
      'Vehicle creation is not available for this account offline.',
    );

    if (await _customerRow(businessId, customerId) == null) {
      throw StateError('Customer is not available in the local cache.');
    }

    final fields = _vehicleFields(
      make: make,
      model: model,
      year: year,
      vin: vin,
      licensePlate: licensePlate,
      licenseState: licenseState,
      mileage: mileage,
      color: color,
    );

    final vehicleId = _uuidV4();
    final operationId = 'vehicle-create-${_uuidV4()}';

    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO local_vehicles (
          id, business_id, year, make, model, vin,
          license_plate, license_state, mileage, color,
          server_updated_at, row_version, sync_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 'pending')
        ''',
        [
          vehicleId,
          businessId,
          fields['year'],
          fields['make'],
          fields['model'],
          fields['vin'],
          fields['license_plate'],
          fields['license_state'],
          fields['mileage'],
          fields['color'],
        ],
      );

      await _database.customStatement(
        '''
        INSERT OR REPLACE INTO local_customer_vehicles (
          business_id, customer_id, vehicle_id, is_primary
        ) VALUES (?, ?, ?, 1)
        ''',
        [businessId, customerId, vehicleId],
      );

      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'vehicle_create', ?, 'create', ?, NULL,
          'pending', 0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          vehicleId,
          jsonEncode({
            'operation_id': operationId,
            'customer_id': customerId,
            'vehicle_id': vehicleId,
            ...fields,
          }),
          _unix(DateTime.now().toUtc()),
        ],
      );
    });

    return vehicleId;
  }

  Future<Map<String, dynamic>> updateLocalVehicle(
    String businessId,
    String vehicleId, {
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) async {
    await _requireCapability(
      businessId,
      'vehicles_edit',
      'Vehicle editing is not available for this account offline.',
    );

    final fields = _vehicleFields(
      make: make,
      model: model,
      year: year,
      vin: vin,
      licensePlate: licensePlate,
      licenseState: licenseState,
      mileage: mileage,
      color: color,
    );

    await _database.transaction(() async {
      final row = await _vehicleRow(businessId, vehicleId);
      if (row == null) {
        throw StateError('Vehicle is not available in the local cache.');
      }
      if (row.read<String>('sync_state') == 'conflict') {
        throw StateError(
          'This vehicle has a sync conflict. The local copy is preserved until it is resolved.',
        );
      }

      await _database.customStatement(
        '''
        UPDATE local_vehicles
        SET year = ?, make = ?, model = ?, vin = ?,
            license_plate = ?, license_state = ?,
            mileage = ?, color = ?, sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [
          fields['year'],
          fields['make'],
          fields['model'],
          fields['vin'],
          fields['license_plate'],
          fields['license_state'],
          fields['mileage'],
          fields['color'],
          businessId,
          vehicleId,
        ],
      );

      final rowVersion = row.readNullable<int>('row_version');
      if (rowVersion == null) {
        await _updateQueuedCreate(
          businessId,
          'vehicle_create',
          vehicleId,
          fields,
        );
      } else {
        await _upsertVehicleUpdate(
          businessId,
          vehicleId,
          baseRowVersion: rowVersion,
          fields: fields,
        );
      }
    });

    return (await _vehicleMap(businessId, vehicleId))!;
  }

  Future<void> flush(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT id
      FROM sync_outbox
      WHERE business_id = ? AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    var pushedAny = false;

    for (final queued in rows) {
      final fresh = await _database.customSelect(
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

      if (fresh.isEmpty) continue;
      final row = fresh.first;
      final type = row.read<String>('entity_type');

      try {
        bool handled = true;
        if (type == 'customer_create') {
          await _flushCustomerCreate(row);
        } else if (type == 'customer_update') {
          if (!await _flushCustomerUpdate(row)) break;
        } else if (type == 'vehicle_create') {
          await _flushVehicleCreate(row);
        } else if (type == 'vehicle_update') {
          if (!await _flushVehicleUpdate(row)) break;
        } else {
          handled = false;
        }

        if (handled) pushedAny = true;
      } catch (error) {
        await _markFailure(row.read<int>('id'), error);
        break;
      }
    }

    if (pushedAny) {
      await _database.customStatement(
        '''
        UPDATE local_sync_states
        SET last_push_at = ?, last_error = NULL
        WHERE business_id = ?
          AND scope = 'customers_vehicles'
        ''',
        [_unix(DateTime.now().toUtc()), businessId],
      );
    }
  }

  Future<void> _queueCustomerMutation(
    String businessId,
    String customerId,
  ) async {
    final row = await _customerRow(businessId, customerId);
    if (row == null) return;

    final rowVersion = row.readNullable<int>('row_version');
    final payloadFields = _customerPayload(row);

    if (rowVersion == null) {
      await _updateQueuedCreate(
        businessId,
        'customer_create',
        customerId,
        payloadFields,
      );
      return;
    }

    final existing = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'customer_update'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();

    final operationId = existing.isEmpty
        ? 'customer-update-${_uuidV4()}'
        : _operationIdFrom(existing.first) ??
            'customer-update-${_uuidV4()}';

    final payload = jsonEncode({
      'operation_id': operationId,
      'customer_id': customerId,
      ...payloadFields,
    });

    if (existing.isEmpty) {
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'customer_update', ?, 'update', ?, ?,
          'pending', 0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          customerId,
          payload,
          rowVersion,
          _unix(DateTime.now().toUtc()),
        ],
      );
    } else {
      await _database.customStatement(
        '''
        UPDATE sync_outbox
        SET payload_json = ?,
            base_row_version = ?,
            attempt_count = 0,
            last_attempt_at = NULL,
            last_error = NULL
        WHERE id = ?
        ''',
        [
          payload,
          rowVersion,
          existing.first.read<int>('id'),
        ],
      );
    }
  }

  Future<void> _upsertVehicleUpdate(
    String businessId,
    String vehicleId, {
    required int baseRowVersion,
    required Map<String, dynamic> fields,
  }) async {
    final existing = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'vehicle_update'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(vehicleId),
      ],
    ).get();

    final operationId = existing.isEmpty
        ? 'vehicle-update-${_uuidV4()}'
        : _operationIdFrom(existing.first) ??
            'vehicle-update-${_uuidV4()}';

    final payload = jsonEncode({
      'operation_id': operationId,
      'vehicle_id': vehicleId,
      ...fields,
    });

    if (existing.isEmpty) {
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'vehicle_update', ?, 'update', ?, ?,
          'pending', 0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          vehicleId,
          payload,
          baseRowVersion,
          _unix(DateTime.now().toUtc()),
        ],
      );
    } else {
      await _database.customStatement(
        '''
        UPDATE sync_outbox
        SET payload_json = ?,
            base_row_version = ?,
            attempt_count = 0,
            last_attempt_at = NULL,
            last_error = NULL
        WHERE id = ?
        ''',
        [
          payload,
          baseRowVersion,
          existing.first.read<int>('id'),
        ],
      );
    }
  }

  Future<void> _updateQueuedCreate(
    String businessId,
    String entityType,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = ?
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(entityType),
        Variable<String>(entityId),
      ],
    ).get();

    if (rows.isEmpty) {
      throw StateError('Queued create operation is missing.');
    }

    final row = rows.first;
    final payload = Map<String, dynamic>.from(
      jsonDecode(row.read<String>('payload_json')) as Map,
    );
    payload.addAll(fields);

    await _database.customStatement(
      '''
      UPDATE sync_outbox
      SET payload_json = ?,
          attempt_count = 0,
          last_attempt_at = NULL,
          last_error = NULL
      WHERE id = ?
      ''',
      [jsonEncode(payload), row.read<int>('id')],
    );
  }

  Future<void> _flushCustomerCreate(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final customerId = payload['customer_id']?.toString() ?? '';

    final response = await _api.syncCreateCustomerWrite(
      businessId,
      customerId: customerId,
      operationId: payload['operation_id']?.toString() ?? '',
      name: payload['name']?.toString() ?? '',
      email: _text(payload['email']),
      phone: _text(payload['phone']),
      problemFlag: payload['problem_flag'] == true,
      problemFlagNote: _text(payload['problem_flag_note']),
    );

    final customer = response['customer'];
    if (customer is! Map) {
      throw StateError('Server did not return the created customer.');
    }

    await _database.transaction(() async {
      await _reconcileCustomer(
        businessId,
        Map<String, dynamic>.from(customer),
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
  }

  Future<bool> _flushCustomerUpdate(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final customerId = payload['customer_id']?.toString() ?? '';

    final response = await _api.syncUpdateCustomerWrite(
      businessId,
      customerId,
      operationId: payload['operation_id']?.toString() ?? '',
      expectedRowVersion:
          row.readNullable<int>('base_row_version'),
      name: payload['name']?.toString() ?? '',
      email: _text(payload['email']),
      phone: _text(payload['phone']),
      problemFlag: payload['problem_flag'] == true,
      problemFlagNote: _text(payload['problem_flag_note']),
    );

    if (response['status']?.toString() == 'conflict') {
      await _database.transaction(() async {
        await _database.customStatement(
          '''
          UPDATE local_customers
          SET sync_state = 'conflict'
          WHERE business_id = ? AND id = ?
          ''',
          [businessId, customerId],
        );
        await _markConflict(
          row.read<int>('id'),
          response,
        );
      });
      return false;
    }

    final customer = response['customer'];
    if (customer is! Map) {
      throw StateError('Server did not return the updated customer.');
    }

    await _database.transaction(() async {
      await _reconcileCustomer(
        businessId,
        Map<String, dynamic>.from(customer),
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
    return true;
  }

  Future<void> _flushVehicleCreate(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final customerId = payload['customer_id']?.toString() ?? '';
    final vehicleId = payload['vehicle_id']?.toString() ?? '';

    final customer = await _customerRow(businessId, customerId);
    if (customer == null ||
        customer.readNullable<int>('row_version') == null) {
      throw StateError(
        'Vehicle is waiting for its customer to sync first.',
      );
    }

    final response = await _api.syncCreateVehicleWrite(
      businessId,
      customerId,
      vehicleId: vehicleId,
      operationId: payload['operation_id']?.toString() ?? '',
      make: payload['make']?.toString() ?? '',
      model: payload['model']?.toString() ?? '',
      year: _int(payload['year']),
      vin: _text(payload['vin']),
      licensePlate: _text(payload['license_plate']),
      licenseState: _text(payload['license_state']),
      mileage: _double(payload['mileage']),
      color: _text(payload['color']),
    );

    final vehicle = response['vehicle'];
    if (vehicle is! Map) {
      throw StateError('Server did not return the created vehicle.');
    }

    await _database.transaction(() async {
      await _reconcileVehicle(
        businessId,
        Map<String, dynamic>.from(vehicle),
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
  }

  Future<bool> _flushVehicleUpdate(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final vehicleId = payload['vehicle_id']?.toString() ?? '';

    final response = await _api.syncUpdateVehicleWrite(
      businessId,
      vehicleId,
      operationId: payload['operation_id']?.toString() ?? '',
      expectedRowVersion:
          row.readNullable<int>('base_row_version'),
      make: payload['make']?.toString() ?? '',
      model: payload['model']?.toString() ?? '',
      year: _int(payload['year']),
      vin: _text(payload['vin']),
      licensePlate: _text(payload['license_plate']),
      licenseState: _text(payload['license_state']),
      mileage: _double(payload['mileage']),
      color: _text(payload['color']),
    );

    if (response['status']?.toString() == 'conflict') {
      await _database.transaction(() async {
        await _database.customStatement(
          '''
          UPDATE local_vehicles
          SET sync_state = 'conflict'
          WHERE business_id = ? AND id = ?
          ''',
          [businessId, vehicleId],
        );
        await _markConflict(
          row.read<int>('id'),
          response,
        );
      });
      return false;
    }

    final vehicle = response['vehicle'];
    if (vehicle is! Map) {
      throw StateError('Server did not return the updated vehicle.');
    }

    await _database.transaction(() async {
      await _reconcileVehicle(
        businessId,
        Map<String, dynamic>.from(vehicle),
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
    return true;
  }

  Future<void> _reconcileCustomer(
    String businessId,
    Map<String, dynamic> customer,
  ) async {
    final customerId = customer['id']?.toString() ?? '';
    if (customerId.isEmpty) {
      throw StateError('Server customer is missing its ID.');
    }

    final contacts = List<dynamic>.from(
      customer['contacts'] ?? const <dynamic>[],
    );

    await _database.customStatement(
      '''
      UPDATE local_customers
      SET display_name = ?,
          is_company = ?,
          email = ?,
          phone = ?,
          list_email = ?,
          list_phone = ?,
          billing_address_json = ?,
          taxable = ?,
          problem_flag = ?,
          problem_flag_note = ?,
          contacts_json = ?,
          server_updated_at = ?,
          row_version = ?,
          sync_state = 'synced'
      WHERE business_id = ? AND id = ?
      ''',
      [
        customer['name']?.toString() ??
            customer['display_name']?.toString() ??
            'Customer',
        customer['is_company'] == true ? 1 : 0,
        _text(customer['email']),
        _text(customer['phone']),
        _text(customer['list_email']),
        _text(customer['list_phone']),
        jsonEncode(
          customer['billing_address'] ??
              const <String, dynamic>{},
        ),
        customer['taxable'] == false ? 0 : 1,
        customer['problem_flag'] == true ? 1 : 0,
        _text(customer['problem_flag_note']),
        jsonEncode(contacts),
        _unixNullable(_date(customer['updated_at'])),
        _int(customer['row_version']),
        businessId,
        customerId,
      ],
    );
  }

  Future<void> _reconcileVehicle(
    String businessId,
    Map<String, dynamic> vehicle,
  ) async {
    final vehicleId = vehicle['id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      throw StateError('Server vehicle is missing its ID.');
    }

    await _database.customStatement(
      '''
      UPDATE local_vehicles
      SET year = ?, make = ?, model = ?, vin = ?,
          license_plate = ?, license_state = ?,
          mileage = ?, color = ?,
          server_updated_at = ?, row_version = ?,
          sync_state = 'synced'
      WHERE business_id = ? AND id = ?
      ''',
      [
        _int(vehicle['year']),
        _text(vehicle['make']),
        _text(vehicle['model']),
        _text(vehicle['vin']),
        _text(vehicle['license_plate']),
        _text(vehicle['license_state']),
        _double(vehicle['mileage']),
        _text(vehicle['color']),
        _unixNullable(_date(vehicle['updated_at'])),
        _int(vehicle['row_version']),
        businessId,
        vehicleId,
      ],
    );
  }

  Future<QueryRow?> _customerRow(
    String businessId,
    String customerId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_customers
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> _vehicleRow(
    String businessId,
    String vehicleId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_vehicles
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(vehicleId),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> _customerMap(
    String businessId,
    String customerId,
  ) async {
    final row = await _customerRow(businessId, customerId);
    if (row == null) return null;
    return {
      'id': customerId,
      'name': row.read<String>('display_name'),
      'email': row.readNullable<String>('email'),
      'phone': row.readNullable<String>('phone'),
      'problem_flag': row.read<int>('problem_flag') == 1,
      'problem_flag_note':
          row.readNullable<String>('problem_flag_note') ?? '',
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
    };
  }

  Future<Map<String, dynamic>?> _vehicleMap(
    String businessId,
    String vehicleId,
  ) async {
    final row = await _vehicleRow(businessId, vehicleId);
    if (row == null) return null;
    return {
      'id': vehicleId,
      'year': row.readNullable<int>('year'),
      'make': row.readNullable<String>('make'),
      'model': row.readNullable<String>('model'),
      'vin': row.readNullable<String>('vin'),
      'license_plate':
          row.readNullable<String>('license_plate'),
      'license_state':
          row.readNullable<String>('license_state'),
      'mileage': row.data['mileage'],
      'color': row.readNullable<String>('color'),
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
    };
  }

  Future<void> _requireCapability(
    String businessId,
    String capability,
    String message,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT metadata_json
      FROM local_sync_states
      WHERE business_id = ?
        AND scope = 'customers_vehicles'
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    if (rows.isEmpty) {
      throw StateError(
        'Connect Briskers once before using customer or vehicle editing offline.',
      );
    }

    Map<String, dynamic> capabilities;
    try {
      capabilities = Map<String, dynamic>.from(
        jsonDecode(
          rows.first.read<String>('metadata_json'),
        ) as Map,
      );
    } catch (_) {
      capabilities = <String, dynamic>{};
    }

    if (capabilities['customers_read'] != true ||
        capabilities[capability] != true) {
      throw StateError(message);
    }
  }

  Future<void> _markFailure(int id, Object error) async {
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
        id,
      ],
    );
  }

  Future<void> _markConflict(
    int id,
    Map<String, dynamic> response,
  ) async {
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
        id,
      ],
    );
  }

  Map<String, dynamic> _customerPayload(QueryRow row) => {
        'name': row.read<String>('display_name'),
        'email': row.readNullable<String>('email'),
        'phone': row.readNullable<String>('phone'),
        'problem_flag': row.read<int>('problem_flag') == 1,
        'problem_flag_note':
            row.readNullable<String>('problem_flag_note'),
      };

  Map<String, dynamic> _vehicleFields({
    required String make,
    required String model,
    int? year,
    String? vin,
    String? licensePlate,
    String? licenseState,
    num? mileage,
    String? color,
  }) {
    final cleanMake = make.trim();
    final cleanModel = model.trim();
    if (cleanMake.isEmpty || cleanModel.isEmpty) {
      throw StateError('Make and model are required.');
    }

    return {
      'make': cleanMake,
      'model': cleanModel,
      'year': year,
      'vin': _normalizeVin(vin),
      'license_plate':
          _nullIfBlank(licensePlate)?.toUpperCase(),
      'license_state':
          _nullIfBlank(licenseState)?.toUpperCase(),
      'mileage': mileage,
      'color': _nullIfBlank(color),
    };
  }

  List<dynamic> _contactsFor(
    List<dynamic> existing, {
    required String? email,
    required String? phone,
  }) {
    final contacts = existing
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();

    void updateKind(String kind, String? value) {
      final index = contacts.indexWhere(
        (item) => item['kind']?.toString() == kind,
      );
      if (value == null) {
        if (index >= 0) contacts.removeAt(index);
        return;
      }
      if (index >= 0) {
        contacts[index] = {
          ...contacts[index],
          'value': value,
          'primary': true,
        };
      } else {
        contacts.add({
          'kind': kind,
          'label': kind == 'phone' ? 'Mobile' : 'Email',
          'value': value,
          'primary': true,
        });
      }
    }

    updateKind('email', email);
    updateKind('phone', phone);
    return contacts;
  }

  String? _preferredContact(
    List<dynamic> contacts,
    String kind,
  ) {
    for (final raw in contacts.whereType<Map>()) {
      if (raw['kind']?.toString() == kind) {
        return _text(raw['value']);
      }
    }
    return null;
  }

  Map<String, dynamic> _payload(QueryRow row) =>
      Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );

  String? _operationIdFrom(QueryRow row) {
    try {
      return _payload(row)['operation_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  List<dynamic> _jsonList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  String? _phoneDigits(String? value) {
    final digits =
        value?.replaceAll(RegExp(r'\D'), '') ?? '';
    return digits.isEmpty ? null : digits;
  }

  String? _normalizeVin(String? value) {
    final cleaned = value
        ?.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    return _nullIfBlank(cleaned);
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  int? _int(Object? value) =>
      int.tryParse(value?.toString() ?? '');

  double? _double(Object? value) =>
      double.tryParse(value?.toString() ?? '');

  DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  int _unix(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;

  int? _unixNullable(DateTime? value) =>
      value == null ? null : _unix(value);

  String _uuidV4() {
    final bytes = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
