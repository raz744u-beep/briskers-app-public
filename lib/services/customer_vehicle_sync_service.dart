import 'dart:async';
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
  static final StreamController<String> _syncEvents =
      StreamController<String>.broadcast();

  static Stream<String> get syncEvents => _syncEvents.stream;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;

  /// Remove only server-absent, already-synced records after a *complete*
  /// authoritative server snapshot has been verified by the repair service.
  /// This is intentionally not part of ordinary incremental sync.
  Future<int> pruneObsoleteCache(
    String businessId,
    Set<String> serverCustomerIds,
  ) async {
    final rows = await _database.customSelect(
      'SELECT id FROM local_customers WHERE business_id = ?',
      variables: [Variable<String>(businessId)],
    ).get();
    final obsolete = rows
        .map((row) => row.read<String>('id'))
        .where((id) => !serverCustomerIds.contains(id))
        .toList();
    await _database.transaction(() async {
      for (final id in obsolete) {
        await _removeCustomer(businessId, id);
      }
    });
    if (obsolete.isNotEmpty) _syncEvents.add(businessId);
    return obsolete.length;
  }

  Future<void> refreshCustomer(
    String businessId,
    String customerId, {
    Map<String, dynamic>? fetchedDetail,
  }) async {
    // Reuse the customer detail already fetched by the screen; do not make
    // a second identical network request on each customer-page visit.
    final detail = fetchedDetail ?? await _api.customerDetail(
      businessId,
      customerId,
    );
    await _database.transaction(() async {
      await _applyBundle(
        businessId,
        detail,
      );
    });
    _syncEvents.add(businessId);
  }

  // Multiple screens can request a customer pull during module navigation.
  // Share one in-flight transfer per database/business instead of restarting a
  // destructive bootstrap from each caller.
  static final Expando<Map<String, Future<void>>> _activePulls = Expando();

  Future<void> pull(String businessId) async {
    final active = _activePulls[_database] ??= {};
    final existing = active[businessId];
    if (existing != null) return existing;
    final current = _pullUnshared(businessId);
    active[businessId] = current;
    try {
      await current;
    } finally {
      if (identical(active[businessId], current)) active.remove(businessId);
    }
  }

  Future<void> _pullUnshared(String businessId) async {
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

    if (!bootstrapped) {
      await _bootstrap(businessId);
      _syncEvents.add(businessId);
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
            await _clearCache(businessId);
            await _writeSyncState(
              businessId,
              cursor: null,
              bootstrapped: false,
              error: null,
            );
          });
          _syncEvents.add(businessId);
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
      _syncEvents.add(businessId);
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

  // Short 401/42501 failures were observed between otherwise successful
  // authorized customer pages on the second device. Retry transient RPC
  // errors; never grant access or modify Supabase permissions from the client.
  Future<Map<String, dynamic>> _bootstrapPage(
    String businessId,
    String? afterCustomerId,
  ) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await _api.syncPullCustomersVehicles(
          businessId,
          afterCustomerId: afterCustomerId,
        );
      } catch (error) {
        final message = error.toString().toLowerCase();
        final retryable = message.contains('42501') ||
            message.contains('401') ||
            message.contains('timeout') ||
            message.contains('57014');
        if (!retryable || attempt == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw StateError('Customer sync retry limit exceeded.');
  }

  Future<void> _bootstrap(String businessId) async {
    String? afterCustomerId;
    int? bootstrapCursor;
    var hasMore = true;
    final authoritative = <String, Map<String, dynamic>>{};

    try {
      // Download every page before touching the active local customer cache.
      // A 401, timeout, malformed cursor, or failed page must not erase the
      // previously available customers or expose a half-built directory.
      while (hasMore) {
        final response = await _bootstrapPage(businessId, afterCustomerId);

        if (response['revoke_all'] == true) {
          // Explicit verified server revocation is the sole exception: access
          // must be revoked immediately, regardless of cached/offline state.
          await _database.transaction(() async {
            await _clearCache(businessId);
            await _writeSyncState(
              businessId, cursor: null, bootstrapped: false, error: null);
          });
          return;
        }

        bootstrapCursor ??= int.tryParse(
          response['bootstrap_cursor']?.toString() ?? '');
        if (bootstrapCursor == null) {
          throw StateError('Customer bootstrap has no valid server cursor.');
        }
        final bundles = List<dynamic>.from(
          response['bundles'] ?? const <dynamic>[]);
        hasMore = response['has_more'] == true;
        final nextId = response['next_customer_id']?.toString();
        for (final raw in bundles) {
          if (raw is! Map) continue;
          final bundle = Map<String, dynamic>.from(raw);
          final customer = bundle['customer'];
          if (customer is! Map) continue;
          final id = customer['id']?.toString() ?? '';
          if (id.isNotEmpty) authoritative[id] = bundle;
        }
        if (hasMore && (nextId == null || nextId.isEmpty ||
            nextId == afterCustomerId)) {
          throw StateError(
            'Customer bootstrap did not return a valid continuation ID.');
        }
        afterCustomerId = hasMore ? nextId : null;
      }

      // One atomic commit: all customers/vehicles appear together, or the
      // old verified directory survives unchanged after rollback.
      await _database.transaction(() async {
        final local = await _database.customSelect(
          "SELECT id FROM local_customers "
          "WHERE business_id=? AND sync_state='synced'",
          variables: [Variable<String>(businessId)],
        ).get();
        for (final row in local) {
          final id = row.read<String>('id');
          if (!authoritative.containsKey(id)) {
            await _removeCustomer(businessId, id, pruneOrphans: false);
          }
        }
        for (final bundle in authoritative.values) {
          await _applyBundle(businessId, bundle, pruneOrphans: false);
        }
        // A single orphan scan after the complete snapshot avoids repeating
        // a full vehicle-table pass for each of ~2,800 customer bundles.
        await _removeOrphanVehicles(businessId);
        await _writeSyncState(
          businessId,
          cursor: bootstrapCursor,
          bootstrapped: true,
          error: null,
        );
        // The baseline is updated only when the whole page sequence commits.
        await _database.customStatement(
          "INSERT INTO local_sync_states "
          "(business_id,scope,last_server_cursor,bootstrapped) "
          "VALUES (?,'customer_notification_baseline',?,1) "
          "ON CONFLICT(business_id,scope) DO UPDATE "
          "SET last_server_cursor=excluded.last_server_cursor",
          [businessId, DateTime.now().toUtc().microsecondsSinceEpoch],
        );
      });
    } catch (error) {
      // Preserve the previous local snapshot and all queued customer work.
      // No customer/vehicle table cleanup on an incomplete download.
      await _writeSyncState(
        businessId,
        cursor: null,
        bootstrapped: false,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _applyBundle(
    String businessId,
    Map<String, dynamic> bundle, {
    bool pruneOrphans = true,
  }) async {
    final rawCustomer = bundle['customer'];
    if (rawCustomer is! Map) return;

    final customer =
        Map<String, dynamic>.from(rawCustomer);
    final customerId =
        customer['id']?.toString() ?? '';
    if (customerId.isEmpty) return;
    final localState = await _database.customSelect(
      'SELECT sync_state FROM local_customers WHERE business_id=? AND id=?',
      variables: [Variable<String>(businessId), Variable<String>(customerId)],
    ).getSingleOrNull();
    if (localState != null && localState.read<String>('sync_state') != 'synced') {
      // Pending offline edits and their vehicle associations must win over
      // any server snapshot until the durable outbox has synchronized.
      return;
    }

    final contacts = List<dynamic>.from(
      bundle['contacts'] ?? const <dynamic>[],
    );
    final vehicles = List<dynamic>.from(
      bundle['vehicles'] ?? const <dynamic>[],
    );

    await _database.customStatement(
      '''
      INSERT INTO local_customers (
        id, business_id, display_name, is_company,
        email, phone, list_email, list_phone,
        billing_address_json, taxable,
        problem_flag, problem_flag_note, contacts_json,
        created_at, server_updated_at, row_version, sync_state
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced'
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
        created_at=coalesce(local_customers.created_at, excluded.created_at),
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='synced'
      WHERE local_customers.sync_state='synced'
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
          customer['billing_address'] ?? const <String, dynamic>{},
        ),
        customer['taxable'] == false ? 0 : 1,
        customer['problem_flag'] == true ? 1 : 0,
        _text(customer['problem_flag_note']),
        jsonEncode(contacts),
        _unix(_date(customer['created_at'])),
        _unix(_date(customer['updated_at'])),
        _int(customer['row_version']),
      ],
    );

    await _database.customStatement(
      '''
      DELETE FROM local_customer_vehicles
      WHERE business_id = ? AND customer_id = ?
        AND vehicle_id NOT IN (
          SELECT id FROM local_vehicles
          WHERE business_id = ? AND sync_state <> 'synced'
        )
      ''',
      [businessId, customerId, businessId],
    );

    for (final raw in vehicles) {
      if (raw is! Map) continue;
      final vehicle = Map<String, dynamic>.from(raw);
      final vehicleId =
          vehicle['id']?.toString() ?? '';
      if (vehicleId.isEmpty) continue;

      await _database.customStatement(
        '''
        INSERT INTO local_vehicles (
          id, business_id, year, make, model, vin,
          license_plate, license_state, mileage, color, key_password,
          mileage_recorded_date, mileage_source_invoice_id,
          server_updated_at, row_version, sync_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
        ON CONFLICT(id) DO UPDATE SET
          year=excluded.year,
          make=excluded.make,
          model=excluded.model,
          vin=excluded.vin,
          license_plate=excluded.license_plate,
          license_state=excluded.license_state,
          mileage=excluded.mileage,
          mileage_recorded_date=excluded.mileage_recorded_date,
          mileage_source_invoice_id=excluded.mileage_source_invoice_id,
          color=excluded.color,
          key_password=excluded.key_password,
          server_updated_at=excluded.server_updated_at,
          row_version=excluded.row_version,
          sync_state='synced'
        WHERE local_vehicles.sync_state='synced'
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
          _text(vehicle['key_password']),
          _text(vehicle['mileage_recorded_date']),
          _text(vehicle['mileage_source_invoice_id']),
          _unix(_date(vehicle['updated_at'])),
          _int(vehicle['row_version']),
        ],
      );

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

    if (pruneOrphans) await _removeOrphanVehicles(businessId);
  }

  Future<void> _removeCustomer(
    String businessId,
    String customerId, {
    bool pruneOrphans = true,
  }) async {
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
    if (pruneOrphans) await _removeOrphanVehicles(businessId);
  }

  Future<void> _removeOrphanVehicles(
    String businessId,
  ) async {
    await _database.customStatement(
      '''
      DELETE FROM local_vehicles
      WHERE business_id = ?
        AND local_vehicles.sync_state='synced'
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

  Future<void> _clearCache(String businessId) async {
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
        last_pull_at=COALESCE(excluded.last_pull_at, local_sync_states.last_pull_at),
        last_error=excluded.last_error,
        bootstrapped=excluded.bootstrapped
      ''',
      [
        businessId,
        _scope,
        cursor,
        bootstrapped && error == null ? _unix(DateTime.now().toUtc()) : null,
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
