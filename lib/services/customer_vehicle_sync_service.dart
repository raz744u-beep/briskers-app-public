import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class CustomerVehicleSyncService {
  CustomerVehicleSyncService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
  })  : _api = api,
        _database = database ?? localDatabase;

  static const _scope = 'customers_vehicles';

  final BriskersApi _api;
  final BriskersLocalDatabase _database;

  Future<void> pull(String businessId) async {
    int? cursor;
    var bootstrapped = false;

    final stateRows = await _database.customSelect(
      '''
      SELECT last_server_cursor, bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        const Variable<String>(_scope),
      ],
    ).get();

    if (stateRows.isNotEmpty) {
      cursor = stateRows.first.readNullable<int>('last_server_cursor');
      bootstrapped =
          stateRows.first.read<int>('bootstrapped') == 1;
    }

    try {
      final capabilities =
          await _api.customerVehicleCapabilities(businessId);
      await _writeCapabilities(
        businessId,
        capabilities,
      );
    } catch (_) {
      // Keep the last known permission snapshot when offline.
    }

    if (!bootstrapped) {
      await _bootstrap(businessId);
      return;
    }

    try {
      var pageCursor = cursor ?? 0;
      var hasMore = true;

      while (hasMore) {
        final response = await _api.syncPullCustomersVehicles(
          businessId,
          afterCursor: pageCursor,
        );

        if (response['revoke_all'] == true) {
          await _database.transaction(() async {
            await _clearAllCache(businessId);
            await _writeSyncState(
              businessId,
              cursor: null,
              bootstrapped: false,
              error: null,
            );
          });
          return;
        }

        final bundles = List<dynamic>.from(
          response['bundles'] ?? const <dynamic>[],
        );
        final revoked = List<dynamic>.from(
          response['revoked_customer_ids'] ??
              const <dynamic>[],
        ).map((value) => value.toString()).toList();

        final nextCursor =
            int.tryParse(response['next_cursor']?.toString() ?? '') ??
                pageCursor;
        hasMore = response['has_more'] == true;

        await _database.transaction(() async {
          for (final raw in bundles) {
            if (raw is! Map) continue;
            await _applyBundle(
              businessId,
              Map<String, dynamic>.from(raw),
            );
          }

          for (final customerId in revoked) {
            if (customerId.isEmpty) continue;
            await _removeCustomer(
              businessId,
              customerId,
            );
          }

          await _writeSyncState(
            businessId,
            cursor: nextCursor,
            bootstrapped: true,
            error: null,
          );
        });

        pageCursor = nextCursor;
      }
    } catch (error) {
      await _writeSyncState(
        businessId,
        cursor: cursor,
        bootstrapped: bootstrapped,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _bootstrap(String businessId) async {
    String? afterCustomerId;
    int? bootstrapCursor;
    var firstPage = true;
    var hasMore = true;

    try {
      while (hasMore) {
        final response = await _api.syncPullCustomersVehicles(
          businessId,
          afterCustomerId: afterCustomerId,
        );

        if (response['revoke_all'] == true) {
          await _database.transaction(() async {
            await _clearAllCache(businessId);
            await _writeSyncState(
              businessId,
              cursor: null,
              bootstrapped: false,
              error: null,
            );
          });
          return;
        }

        bootstrapCursor ??= int.tryParse(
          response['bootstrap_cursor']?.toString() ?? '',
        );

        final bundles = List<dynamic>.from(
          response['bundles'] ?? const <dynamic>[],
        );
        hasMore = response['has_more'] == true;
        final nextId =
            response['next_customer_id']?.toString();

        await _database.transaction(() async {
          if (firstPage) {
            await _clearSyncedCache(businessId);
          }

          for (final raw in bundles) {
            if (raw is! Map) continue;
            await _applyBundle(
              businessId,
              Map<String, dynamic>.from(raw),
            );
          }
        });

        firstPage = false;
        afterCustomerId =
            (nextId == null || nextId.isEmpty) ? null : nextId;

        if (hasMore && afterCustomerId == null) {
          throw StateError(
            'Customer bootstrap did not return a continuation ID.',
          );
        }
      }

      await _writeSyncState(
        businessId,
        cursor: bootstrapCursor ?? 0,
        bootstrapped: true,
        error: null,
      );
    } catch (error) {
      await _database.transaction(() async {
        await _clearCache(businessId);
        await _writeSyncState(
          businessId,
          cursor: null,
          bootstrapped: false,
          error: error.toString(),
        );
      });
      rethrow;
    }
  }

  Future<void> _applyBundle(
    String businessId,
    Map<String, dynamic> bundle,
  ) async {
    final rawCustomer = bundle['customer'];
    if (rawCustomer is! Map) return;

    final customer = Map<String, dynamic>.from(rawCustomer);
    final customerId = customer['id']?.toString() ?? '';
    if (customerId.isEmpty) return;

    final contacts = List<dynamic>.from(
      bundle['contacts'] ?? const <dynamic>[],
    );
    final vehicles = List<dynamic>.from(
      bundle['vehicles'] ?? const <dynamic>[],
    );

    final existingCustomer = await _database.customSelect(
      '''
      SELECT sync_state
      FROM local_customers
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();

    final preserveCustomer = existingCustomer.isNotEmpty &&
        const {'pending', 'conflict'}.contains(
          existingCustomer.first.read<String>('sync_state'),
        );

    if (!preserveCustomer) {
      await _database.customStatement(
        '''
        INSERT INTO local_customers (
          id, business_id, display_name, is_company,
          email, phone, list_email, list_phone,
          billing_address_json, taxable,
          problem_flag, problem_flag_note, contacts_json,
          server_updated_at, row_version, sync_state
        ) VALUES (
          ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced'
        )
        ON CONFLICT(id) DO UPDATE SET
          business_id=excluded.business_id,
          display_name=excluded.display_name,
          is_company=excluded.is_company,
          email=excluded.email,
          phone=excluded.phone,
          list_email=excluded.list_email,
          list_phone=excluded.list_phone,
          billing_address_json=excluded.billing_address_json,
          taxable=excluded.taxable,
          problem_flag=excluded.problem_flag,
          problem_flag_note=excluded.problem_flag_note,
          contacts_json=excluded.contacts_json,
          server_updated_at=excluded.server_updated_at,
          row_version=excluded.row_version,
          sync_state='synced'
        ''',
        [
          customerId,
          businessId,
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
          _unix(_date(customer['updated_at'])),
          _int(customer['row_version']),
        ],
      );
    }

    final existingRelations = await _database.customSelect(
      '''
      SELECT cv.vehicle_id, v.sync_state
      FROM local_customer_vehicles cv
      JOIN local_vehicles v
        ON v.business_id = cv.business_id
       AND v.id = cv.vehicle_id
      WHERE cv.business_id = ?
        AND cv.customer_id = ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();

    final dirtyVehicleIds = <String>{
      for (final row in existingRelations)
        if (const {'pending', 'conflict'}.contains(
          row.read<String>('sync_state'),
        ))
          row.read<String>('vehicle_id'),
    };

    final serverVehicleIds = <String>{};

    for (final raw in vehicles) {
      if (raw is! Map) continue;
      final vehicle = Map<String, dynamic>.from(raw);
      final vehicleId = vehicle['id']?.toString() ?? '';
      if (vehicleId.isEmpty) continue;
      serverVehicleIds.add(vehicleId);

      if (!dirtyVehicleIds.contains(vehicleId)) {
        await _database.customStatement(
          '''
          INSERT INTO local_vehicles (
            id, business_id, year, make, model, vin,
            license_plate, license_state, mileage, color,
            server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ON CONFLICT(id) DO UPDATE SET
            year=excluded.year,
            make=excluded.make,
            model=excluded.model,
            vin=excluded.vin,
            license_plate=excluded.license_plate,
            license_state=excluded.license_state,
            mileage=excluded.mileage,
            color=excluded.color,
            server_updated_at=excluded.server_updated_at,
            row_version=excluded.row_version,
            sync_state='synced'
          ''',
          [
            vehicleId,
            businessId,
            _int(vehicle['year']),
            _text(vehicle['make']),
            _text(vehicle['model']),
            _text(vehicle['vin']),
            _text(vehicle['license_plate']),
            _text(vehicle['license_state']),
            _double(vehicle['mileage']),
            _text(vehicle['color']),
            _unix(_date(vehicle['updated_at'])),
            _int(vehicle['row_version']),
          ],
        );
      }

      await _database.customStatement(
        '''
        INSERT OR REPLACE INTO local_customer_vehicles (
          business_id, customer_id, vehicle_id, is_primary
        ) VALUES (?, ?, ?, ?)
        ''',
        [
          businessId,
          customerId,
          vehicleId,
          vehicle['is_primary'] == false ? 0 : 1,
        ],
      );
    }

    for (final row in existingRelations) {
      final vehicleId = row.read<String>('vehicle_id');
      final dirty = const {'pending', 'conflict'}.contains(
        row.read<String>('sync_state'),
      );
      if (!dirty && !serverVehicleIds.contains(vehicleId)) {
        await _database.customStatement(
          '''
          DELETE FROM local_customer_vehicles
          WHERE business_id = ?
            AND customer_id = ?
            AND vehicle_id = ?
          ''',
          [businessId, customerId, vehicleId],
        );
      }
    }

    await _removeOrphanVehicles(businessId);
  }

  Future<void> _removeCustomer(
    String businessId,
    String customerId,
  ) async {
    final vehicleRows = await _database.customSelect(
      '''
      SELECT vehicle_id
      FROM local_customer_vehicles
      WHERE business_id = ? AND customer_id = ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();

    final vehicleIds = vehicleRows
        .map((row) => row.read<String>('vehicle_id'))
        .toList();

    await _database.customStatement(
      '''
      DELETE FROM sync_outbox
      WHERE business_id = ?
        AND entity_type IN ('customer_create','customer_update')
        AND entity_id = ?
      ''',
      [businessId, customerId],
    );

    for (final vehicleId in vehicleIds) {
      await _database.customStatement(
        '''
        DELETE FROM sync_outbox
        WHERE business_id = ?
          AND entity_type IN ('vehicle_create','vehicle_update')
          AND entity_id = ?
        ''',
        [businessId, vehicleId],
      );
    }

    await _database.customStatement(
      '''
      DELETE FROM local_customer_vehicles
      WHERE business_id = ? AND customer_id = ?
      ''',
      [businessId, customerId],
    );
    await _database.customStatement(
      '''
      DELETE FROM local_customers
      WHERE business_id = ? AND id = ?
      ''',
      [businessId, customerId],
    );

    for (final vehicleId in vehicleIds) {
      final relationCount = await _database.customSelect(
        '''
        SELECT COUNT(*) AS count
        FROM local_customer_vehicles
        WHERE business_id = ? AND vehicle_id = ?
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(vehicleId),
        ],
      ).getSingle();

      if (relationCount.read<int>('count') == 0) {
        await _database.customStatement(
          '''
          DELETE FROM local_vehicles
          WHERE business_id = ? AND id = ?
          ''',
          [businessId, vehicleId],
        );
      }
    }
  }

  Future<void> _removeOrphanVehicles(
    String businessId,
  ) async {
    await _database.customStatement(
      '''
      DELETE FROM local_vehicles
      WHERE business_id = ?
        AND sync_state = 'synced'
        AND NOT EXISTS (
          SELECT 1
          FROM local_customer_vehicles cv
          WHERE cv.business_id = local_vehicles.business_id
            AND cv.vehicle_id = local_vehicles.id
        )
      ''',
      [businessId],
    );
  }

  Future<void> _clearSyncedCache(String businessId) async {
    final removableCustomers = await _database.customSelect(
      '''
      SELECT c.id
      FROM local_customers c
      WHERE c.business_id = ?
        AND c.sync_state = 'synced'
        AND NOT EXISTS (
          SELECT 1
          FROM local_customer_vehicles cv
          JOIN local_vehicles v
            ON v.business_id = cv.business_id
           AND v.id = cv.vehicle_id
          WHERE cv.business_id = c.business_id
            AND cv.customer_id = c.id
            AND v.sync_state IN ('pending','conflict')
        )
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    for (final row in removableCustomers) {
      final customerId = row.read<String>('id');
      await _database.customStatement(
        '''
        DELETE FROM local_customer_vehicles
        WHERE business_id = ? AND customer_id = ?
        ''',
        [businessId, customerId],
      );
      await _database.customStatement(
        '''
        DELETE FROM local_customers
        WHERE business_id = ? AND id = ?
        ''',
        [businessId, customerId],
      );
    }

    await _removeOrphanVehicles(businessId);
  }

  Future<void> _clearAllCache(String businessId) async {
    await _database.customStatement(
      '''
      DELETE FROM sync_outbox
      WHERE business_id = ?
        AND entity_type IN (
          'customer_create','customer_update',
          'vehicle_create','vehicle_update'
        )
      ''',
      [businessId],
    );
    await _database.customStatement(
      'DELETE FROM local_customer_vehicles WHERE business_id = ?',
      [businessId],
    );
    await _database.customStatement(
      'DELETE FROM local_vehicles WHERE business_id = ?',
      [businessId],
    );
    await _database.customStatement(
      'DELETE FROM local_customers WHERE business_id = ?',
      [businessId],
    );
  }

  Future<void> _writeCapabilities(
    String businessId,
    Map<String, dynamic> capabilities,
  ) async {
    await _database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, metadata_json, bootstrapped
      ) VALUES (?, ?, ?, 0)
      ON CONFLICT(business_id, scope) DO UPDATE SET
        metadata_json=excluded.metadata_json
      ''',
      [
        businessId,
        _scope,
        jsonEncode(capabilities),
      ],
    );
  }

  Future<void> _writeSyncState(
    String businessId, {
    required int? cursor,
    required bool bootstrapped,
    required String? error,
  }) async {
    await _database.customStatement(
      '''
      INSERT INTO local_sync_states (
        business_id, scope, last_server_cursor, last_pull_at,
        last_push_at, last_error, bootstrapped
      ) VALUES (?, ?, ?, ?, NULL, ?, ?)
      ON CONFLICT(business_id, scope) DO UPDATE SET
        last_server_cursor=excluded.last_server_cursor,
        last_pull_at=excluded.last_pull_at,
        last_error=excluded.last_error,
        bootstrapped=excluded.bootstrapped
      ''',
      [
        businessId,
        _scope,
        cursor,
        _unix(DateTime.now().toUtc()),
        error,
        bootstrapped ? 1 : 0,
      ],
    );
  }

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  int? _int(Object? value) =>
      int.tryParse(value?.toString() ?? '');

  double? _double(Object? value) =>
      double.tryParse(value?.toString() ?? '');

  DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  int? _unix(DateTime? value) =>
      value == null
          ? null
          : value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
