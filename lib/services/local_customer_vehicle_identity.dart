import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';

class LocalCustomerVehicleIdentity {
  const LocalCustomerVehicleIdentity(this.database);

  final BriskersLocalDatabase database;

  Future<void> _ensure() => database.customStatement('''
    CREATE TABLE IF NOT EXISTS local_customer_vehicle_create_ids (
      business_id TEXT NOT NULL,
      local_id TEXT NOT NULL,
      server_id TEXT NOT NULL,
      PRIMARY KEY (business_id, local_id)
    )
  ''');

  Future<String?> resolve(String business, String? id) async {
    if (id == null ||
        !(id.startsWith('local-vehicle-') ||
            id.startsWith('local-customer-'))) {
      return id;
    }
    await _ensure();
    final row = await database
        .customSelect(
          'SELECT server_id FROM local_customer_vehicle_create_ids WHERE business_id=? AND local_id=?',
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    return row?.read<String>('server_id') ?? id;
  }

  Future<void> save(String business, String localId, String serverId) async {
    await _ensure();
    await database.customStatement(
      'INSERT OR REPLACE INTO local_customer_vehicle_create_ids VALUES (?,?,?)',
      [business, localId, serverId],
    );
  }
}
