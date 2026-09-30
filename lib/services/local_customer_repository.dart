import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalCustomerRepository {
  LocalCustomerRepository({
    BriskersLocalDatabase? database,
  }) : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<bool> hasBootstrap(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'customers_vehicles'
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    return rows.isNotEmpty &&
        rows.first.read<int>('bootstrapped') == 1;
  }

  Future<Map<String, dynamic>> capabilities(
    String businessId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT metadata_json
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'customers_vehicles'
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    if (rows.isEmpty) return <String, dynamic>{};
    return _jsonMap(
      rows.first.read<String>('metadata_json'),
    );
  }

  Future<int> customerTotal(String businessId) async {
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_customers
      WHERE business_id = ?
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();

    return row.read<int>('count');
  }

  Future<List<Map<String, dynamic>>> customers(
    String businessId, {
    String? search,
  }) async {
    final query = search?.trim() ?? '';
    final rows = await _database.customSelect(
      query.isEmpty
          ? '''
            SELECT c.*,
              (
                SELECT COUNT(*)
                FROM local_customer_vehicles cv
                WHERE cv.business_id = c.business_id
                  AND cv.customer_id = c.id
              ) AS vehicle_count
            FROM local_customers c
            WHERE c.business_id = ?
            ORDER BY lower(c.display_name), c.id
            '''
          : '''
            SELECT c.*,
              (
                SELECT COUNT(*)
                FROM local_customer_vehicles cv
                WHERE cv.business_id = c.business_id
                  AND cv.customer_id = c.id
              ) AS vehicle_count
            FROM local_customers c
            WHERE c.business_id = ?
              AND lower(c.display_name) LIKE ?
            ORDER BY lower(c.display_name), c.id
            ''',
      variables: query.isEmpty
          ? [Variable<String>(businessId)]
          : [
              Variable<String>(businessId),
              Variable<String>('%${query.toLowerCase()}%'),
            ],
    ).get();

    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row.read<String>('id'),
            'display_name': row.read<String>('display_name'),
            'email': row.readNullable<String>('list_email') ??
                row.readNullable<String>('email'),
            'phone': row.readNullable<String>('list_phone') ??
                row.readNullable<String>('phone'),
            'problem_flag':
                row.read<int>('problem_flag') == 1,
            'problem_flag_note':
                row.readNullable<String>('problem_flag_note') ?? '',
            'vehicle_count': row.read<int>('vehicle_count'),
            'sync_state': row.read<String>('sync_state'),
            '_local_snapshot': true,
          },
        )
        .toList();
  }

  Future<Map<String, dynamic>?> customerDetail(
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

    if (rows.isEmpty) return null;
    final row = rows.first;

    final vehicleRows = await _database.customSelect(
      '''
      SELECT v.*, cv.is_primary
      FROM local_customer_vehicles cv
      JOIN local_vehicles v
        ON v.business_id = cv.business_id
       AND v.id = cv.vehicle_id
      WHERE cv.business_id = ?
        AND cv.customer_id = ?
      ORDER BY v.year DESC, lower(v.make), lower(v.model), v.id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(customerId),
      ],
    ).get();

    final contacts = _jsonList(
      row.read<String>('contacts_json'),
    );
    final billingAddress = _jsonMap(
      row.read<String>('billing_address_json'),
    );

    return <String, dynamic>{
      'customer': <String, dynamic>{
        'id': row.read<String>('id'),
        'name': row.read<String>('display_name'),
        'is_company': row.read<int>('is_company') == 1,
        'email': row.readNullable<String>('email'),
        'phone': row.readNullable<String>('phone'),
        'billing_address': billingAddress,
        'taxable': row.read<int>('taxable') == 1,
        'problem_flag': row.read<int>('problem_flag') == 1,
        'problem_flag_note':
            row.readNullable<String>('problem_flag_note') ?? '',
        'updated_at':
            _isoFromDb(row.data['server_updated_at']),
        'row_version': row.readNullable<int>('row_version'),
        'sync_state': row.read<String>('sync_state'),
      },
      'contacts': contacts,
      'vehicles': vehicleRows
          .map(
            (vehicle) => <String, dynamic>{
              'id': vehicle.read<String>('id'),
              'year': vehicle.readNullable<int>('year'),
              'make': vehicle.readNullable<String>('make'),
              'model': vehicle.readNullable<String>('model'),
              'vin': vehicle.readNullable<String>('vin'),
              'license_plate':
                  vehicle.readNullable<String>('license_plate'),
              'license_state':
                  vehicle.readNullable<String>('license_state'),
              'mileage': vehicle.data['mileage'],
              'color': vehicle.readNullable<String>('color'),
              'updated_at':
                  _isoFromDb(vehicle.data['server_updated_at']),
              'row_version':
                  vehicle.readNullable<int>('row_version'),
              'sync_state': vehicle.read<String>('sync_state'),
              'is_primary':
                  vehicle.read<int>('is_primary') == 1,
              '_local_snapshot': true,
            },
          )
          .toList(),
      '_local_snapshot': true,
    };
  }

  List<dynamic> _jsonList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  Map<String, dynamic> _jsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

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
