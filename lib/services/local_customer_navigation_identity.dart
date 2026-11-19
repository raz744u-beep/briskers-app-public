import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_customer_vehicle_identity.dart';

/// Resolve saved links by exact IDs, never by customer name or printed number.
class LocalCustomerNavigationIdentity {
  const LocalCustomerNavigationIdentity(this.db);
  final BriskersLocalDatabase db;

  Future<String> customer(String business, String id, {String? localJobId}) async {
    if (localJobId != null && localJobId.isNotEmpty) {
      final job = await db.customSelect(
        'SELECT customer_id FROM local_jobs WHERE business_id=? AND id=?',
        variables: [Variable(business), Variable(localJobId)],
      ).getSingleOrNull();
      final current = job?.readNullable<String>('customer_id');
      if (current != null && current.isNotEmpty) id = current;
    }
    return await LocalCustomerVehicleIdentity(db).resolve(business, id) ?? id;
  }

  Future<Map<String, dynamic>?> detail(String business, String expected,
      Map<String, dynamic> saved) async {
    final rawCustomer = saved['customer'];
    if (rawCustomer is! Map) return null;
    final id = rawCustomer['id']?.toString() ?? '';
    if (id.isEmpty || await customer(business, id) != expected) return null;
    final identities = LocalCustomerVehicleIdentity(db);
    final vehicles = <Map<String, dynamic>>[];
    for (final raw in (saved['vehicles'] as List? ?? const []).whereType<Map>()) {
      vehicles.add({...Map<String, dynamic>.from(raw),
        'id': await identities.resolve(business, raw['id']?.toString())});
    }
    return {...saved, 'customer': {...rawCustomer, 'id': expected},
      'vehicles': vehicles};
  }
}
