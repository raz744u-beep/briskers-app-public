import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'lan_record_inventory.dart';

class LanCustomerVehicleCopy {
  const LanCustomerVehicleCopy(this.db);

  final BriskersLocalDatabase db;

  Future<int?> _cursor(String business) async {
    final state =
        await (db.select(db.localSyncStates)..where(
              (row) =>
                  row.businessId.equals(business) &
                  row.scope.equals('customers_vehicles'),
            ))
            .getSingleOrNull();
    return state?.bootstrapped == true ? state?.lastServerCursor : null;
  }

  Future<Set<String>> _queuedIds(String business) async {
    final rows = await db
        .customSelect(
          "SELECT entity_id FROM sync_outbox WHERE business_id=? AND state<>'done' "
          "AND entity_type IN ('customer_create','customer_profile','customer_flag','vehicle_create','vehicle_update')",
          variables: [Variable(business)],
        )
        .get();
    return {for (final row in rows) row.read<String>('entity_id')};
  }

  Future<Map<String, dynamic>> share(String business) =>
      db.transaction(() async {
        final cursor = await _cursor(business);
        if (cursor == null)
          throw StateError(
            'This phone has no verified customer and vehicle sync history.',
          );
        final queued = await _queuedIds(business);
        final customers =
            await (db.select(db.localCustomers)..where(
                  (row) =>
                      row.businessId.equals(business) &
                      row.syncState.equals('synced'),
                ))
                .get();
        final vehicles =
            await (db.select(db.localVehicles)..where(
                  (row) =>
                      row.businessId.equals(business) &
                      row.syncState.equals('synced'),
                ))
                .get();
        final links = await (db.select(
          db.localCustomerVehicles,
        )..where((row) => row.businessId.equals(business))).get();
        return {
          'version': 1,
          'cursor': cursor,
          'customers': [
            for (final row in customers)
              if (_savedId(row.id) && !queued.contains(row.id)) row.toJson(),
          ],
          'vehicles': [
            for (final row in vehicles)
              if (_savedId(row.id) &&
                  !queued.contains(row.id) &&
                  (row.keyPassword?.isEmpty ?? true))
                row.toJson(),
          ],
          'links': [for (final row in links) row.toJson()],
        };
      });

  Future<({int customers, int vehicles})> copyMissing({
    required String business,
    required Map<String, dynamic> bundle,
    required Set<String> approvedIdentities,
  }) => db.transaction(() async {
    final sourceCursor = bundle['cursor'];
    final here = await _cursor(business);
    if (bundle['version'] != 1 ||
        sourceCursor is! int ||
        here == null ||
        here < 0 ||
        sourceCursor < here) {
      throw StateError(
        'This receiver has newer or unverified customer and vehicle sync history. Review both phones.',
      );
    }

    final sourceCustomers = _index(
      bundle['customers'],
      LocalCustomer.fromJson,
      (row) => row.id,
    );
    final sourceVehicles = _index(
      bundle['vehicles'],
      LocalVehicle.fromJson,
      (row) => row.id,
    );
    final sourceLinks = _rows(bundle['links'], LocalCustomerVehicle.fromJson);
    if (sourceCustomers.values.any(
          (row) =>
              row.businessId != business ||
              row.syncState != 'synced' ||
              !_savedId(row.id),
        ) ||
        sourceVehicles.values.any(
          (row) =>
              row.businessId != business ||
              row.syncState != 'synced' ||
              !_savedId(row.id) ||
              (row.keyPassword?.isNotEmpty ?? false),
        ) ||
        sourceLinks.any((row) => row.businessId != business)) {
      throw const FormatException(
        'Customer and vehicle copy data is invalid for this shop.',
      );
    }

    final queued = await _queuedIds(business);
    // IDs are primary keys across all locally stored businesses.
    final customerRows = await db.select(db.localCustomers).get();
    final vehicleRows = await db.select(db.localVehicles).get();
    final customerById = {for (final row in customerRows) row.id: row};
    final vehicleById = {for (final row in vehicleRows) row.id: row};
    final localCustomerKeys = {
      for (final row in customerRows)
        if (row.businessId == business) ..._customerKeys(row),
    };
    final localVins = {
      for (final row in vehicleRows)
        if (row.businessId == business && _normalized(row.vin).isNotEmpty)
          _normalized(row.vin),
    };
    final sourceCustomerKeyCounts = <String, int>{};
    for (final row in sourceCustomers.values) {
      for (final key in _customerKeys(row)) {
        sourceCustomerKeyCounts.update(
          key,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final sourceVinCounts = <String, int>{};
    for (final row in sourceVehicles.values) {
      sourceVinCounts.update(
        _normalized(row.vin),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    bool approved(String kind, String id) =>
        !queued.contains(id) &&
        approvedIdentities.contains(
          LanRecordInventory.recordIdentity(business, kind, id),
        );

    final customerCandidates = {
      for (final row in sourceCustomers.values)
        if (approved('customer', row.id) &&
            !customerById.containsKey(row.id) &&
            row.displayName.trim().isNotEmpty &&
            _customerKeys(row).every(
              (key) =>
                  !localCustomerKeys.contains(key) &&
                  sourceCustomerKeyCounts[key] == 1,
            ))
          row.id,
    };

    final linksByVehicle = <String, List<LocalCustomerVehicle>>{};
    final linksByCustomer = <String, List<LocalCustomerVehicle>>{};
    for (final link in sourceLinks) {
      (linksByVehicle[link.vehicleId] ??= []).add(link);
      (linksByCustomer[link.customerId] ??= []).add(link);
    }

    final vehicleCandidates = {
      for (final row in sourceVehicles.values)
        if (approved('vehicle', row.id) &&
            !vehicleById.containsKey(row.id) &&
            _normalized(row.vin).length == 17 &&
            !localVins.contains(_normalized(row.vin)) &&
            sourceVinCounts[_normalized(row.vin)] == 1 &&
            linksByVehicle[row.id]?.length == 1)
          row.id,
    };

    // A new customer is copied only when every saved vehicle and ownership
    // link can go with it. Shared vehicles and ambiguous owners stay for review.
    customerCandidates.removeWhere(
      (id) => (linksByCustomer[id] ?? const []).any(
        (link) => !vehicleCandidates.contains(link.vehicleId),
      ),
    );
    vehicleCandidates.removeWhere((id) {
      final owner = linksByVehicle[id]!.single.customerId;
      final original = sourceCustomers[owner];
      return !customerCandidates.contains(owner) &&
          (original == null ||
              queued.contains(owner) ||
              customerById[owner] != original);
    });

    for (final id in customerCandidates) {
      await db.into(db.localCustomers).insert(sourceCustomers[id]!);
    }
    for (final id in vehicleCandidates) {
      await db.into(db.localVehicles).insert(sourceVehicles[id]!);
      await db
          .into(db.localCustomerVehicles)
          .insert(linksByVehicle[id]!.single);
    }
    return (
      customers: customerCandidates.length,
      vehicles: vehicleCandidates.length,
    );
  });

  static bool _savedId(String id) => id.isNotEmpty && !id.startsWith('local-');
  static String _normalized(String? value) =>
      (value ?? '').trim().toLowerCase();

  static Set<String> _customerKeys(LocalCustomer row) {
    final name = _normalized(row.displayName).replaceAll(RegExp(r'\s+'), ' ');
    final email = _normalized(row.email ?? row.listEmail);
    final phone = (row.phone ?? row.listPhone ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return {
      if (name.isNotEmpty) 'name:$name',
      if (email.isNotEmpty) 'email:$email',
      if (phone.length >= 7)
        'phone:${phone.length > 10 ? phone.substring(phone.length - 10) : phone}',
    };
  }

  static List<T> _rows<T>(
    Object? raw,
    T Function(Map<String, dynamic>) decode,
  ) {
    if (raw is! List) throw const FormatException('Invalid LAN copy records.');
    return [
      for (final row in raw)
        if (row is Map<String, dynamic>)
          decode(row)
        else
          throw const FormatException('Invalid LAN copy record.'),
    ];
  }

  static Map<String, T> _index<T>(
    Object? raw,
    T Function(Map<String, dynamic>) decode,
    String Function(T) id,
  ) {
    final rows = _rows(raw, decode);
    final indexed = {for (final row in rows) id(row): row};
    if (indexed.length != rows.length)
      throw const FormatException('Duplicate LAN copy record.');
    return indexed;
  }
}
