import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalAppointmentRepository {
  LocalAppointmentRepository({
    BriskersLocalDatabase? database,
  }) : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<bool> hasBootstrap(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'appointments'
      LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    return rows.isNotEmpty &&
        rows.first.read<int>('bootstrapped') == 1;
  }

  Future<List<Map<String, dynamic>>> appointments(
    String businessId, {
    String filter = 'all',
    String? search,
    int pastLimit = 30,
  }) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final where = <String>['a.business_id = ?'];
    final variables = <Variable<Object>>[Variable<String>(businessId)];

    if (filter == 'today') {
      where.add('a.starts_at >= ? AND a.starts_at < ?');
      variables.add(Variable<DateTime>(today));
      variables.add(Variable<DateTime>(tomorrow));
    } else if (filter == 'upcoming') {
      where.add('a.starts_at >= ?');
      variables.add(Variable<DateTime>(tomorrow));
    } else if (filter == 'past') {
      where.add('a.starts_at < ?');
      variables.add(Variable<DateTime>(today));
    }

    final query = search?.trim().toLowerCase() ?? '';
    if (query.isNotEmpty) {
      where.add('''
        (lower(COALESCE(a.customer_name, '')) LIKE ?
         OR lower(COALESCE(a.customer_phone_norm, '')) LIKE ?
         OR lower(COALESCE(a.vehicle_label, '')) LIKE ?
         OR lower(COALESCE(a.vehicle_make, '')) LIKE ?
         OR lower(COALESCE(a.vehicle_model, '')) LIKE ?
         OR lower(COALESCE(a.title, '')) LIKE ?
         OR lower(COALESCE(a.description, '')) LIKE ?
         OR EXISTS (
           SELECT 1 FROM local_customers c
           WHERE c.business_id=a.business_id AND c.id=a.customer_id
             AND lower(COALESCE(c.email, '')) LIKE ?
         ))
      ''');
      final like = '%$query%';
      for (var i = 0; i < 8; i++) {
        variables.add(Variable<String>(like));
      }
    }

    final order = filter == 'past'
        ? 'a.starts_at DESC, a.id'
        : 'a.starts_at, a.id';
    final limit = filter == 'past' && query.isEmpty ? 'LIMIT $pastLimit' : '';

    final rows = await _database.customSelect(
      '''
      SELECT a.*
      FROM local_appointments a
      WHERE ${where.join(' AND ')}
      ORDER BY $order
      $limit
      ''',
      variables: variables,
    ).get();
    return rows.map(_mapRow).toList();
  }

  Future<int> confirmedTodayCount(String businessId) async {
    final now = DateTime.now();
    final startLocal = DateTime(now.year, now.month, now.day);
    final endLocal = startLocal.add(const Duration(days: 1));
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_appointments
      WHERE business_id = ?
        AND status = 'confirmed'
        AND starts_at >= ?
        AND starts_at < ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<DateTime>(startLocal.toUtc()),
        Variable<DateTime>(endLocal.toUtc()),
      ],
    ).getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchConfirmedTodayCount(String businessId) {
    final now = DateTime.now();
    final startLocal = DateTime(now.year, now.month, now.day);
    final endLocal = startLocal.add(const Duration(days: 1));
    return _database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM local_appointments
          WHERE business_id = ?
            AND status = 'confirmed'
            AND starts_at >= ?
            AND starts_at < ?
          ''',
          variables: [
            Variable<String>(businessId),
            Variable<DateTime>(startLocal.toUtc()),
            Variable<DateTime>(endLocal.toUtc()),
          ],
          readsFrom: {_database.localAppointments},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
  }

  Future<List<Map<String, dynamic>>> appointmentsForPhone(
    String businessId,
    String phoneDigits,
  ) async {
    final normalized = phoneDigits.replaceAll(RegExp(r'\D'), '');
    final lastTen = normalized.length > 10
        ? normalized.substring(normalized.length - 10)
        : normalized;
    if (lastTen.length != 10) return const [];

    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_appointments
      WHERE business_id = ?
        AND customer_phone_norm = ?
        AND can_check_in = 1
        AND job_id IS NULL
        AND status NOT IN ('cancelled','no_show')
      ORDER BY starts_at, id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(lastTen),
      ],
    ).get();

    return rows.map(_mapRow).toList();
  }

  Future<Map<String, dynamic>?> appointment(
    String businessId,
    String appointmentId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_appointments
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(appointmentId),
      ],
    ).get();

    return rows.isEmpty ? null : _mapRow(rows.first);
  }

  Map<String, dynamic> _mapRow(QueryRow row) {
    return <String, dynamic>{
      'id': row.read<String>('id'),
      'customer_id': row.read<String>('customer_id'),
      'vehicle_id': row.readNullable<String>('vehicle_id'),
      'employee_id': row.readNullable<String>('employee_id'),
      'job_id': row.readNullable<String>('job_id'),
      'request_id': row.readNullable<String>('request_id'),
      'starts_at': _isoFromDb(row.data['starts_at']),
      'ends_at': _isoFromDb(row.data['ends_at']),
      'status': row.read<String>('status'),
      'title': row.read<String>('title'),
      'description': row.readNullable<String>('description'),
      'customer': row.readNullable<String>('customer_name'),
      'vehicle_year': row.readNullable<int>('vehicle_year'),
      'vehicle_make': row.readNullable<String>('vehicle_make'),
      'vehicle_model': row.readNullable<String>('vehicle_model'),
      'vehicle': row.readNullable<String>('vehicle_label'),
      'mechanic': row.readNullable<String>('mechanic_name'),
      'can_check_in': row.read<int>('can_check_in') == 1,
      'updated_at':
          _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
      '_local_snapshot': true,
    };
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
