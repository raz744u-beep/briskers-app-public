import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import 'briskers_api.dart';
import 'local_owner_authorization.dart';
import 'secure_employee_details_cache.dart';

class EmployeeDetailsConflict implements Exception {
  EmployeeDetailsConflict(this.fields);
  final List<String> fields;
  String get message =>
      'Changes to ${fields.join(', ')} conflict with another device. Your local edits are saved; no server fields were overwritten. Review these fields before syncing.';
}

class LocalEmployeeDetails {
  const LocalEmployeeDetails();
  static const cache = SecureEmployeeDetailsCache();
  Future<void> sync(String shop, String employee, LocalOwnerGrant grant) async {
    grant.assertValid(shop, grant.actorId);
    BriskersConnectionModeController.instance.ensureNetworkAllowed();
    final saved = await cache.read(shop, employee, grant);
    final pending = Map<String, dynamic>.from(saved?['pending'] as Map? ?? {});
    if (pending.isNotEmpty) {
      final result = await networkSupabase
          .rpc(
            'briskers_patch_employee_details_v1',
            params: {
              'p_business_id': shop,
              'p_employee_id': employee,
              'p_base': {
                for (final key in pending.keys)
                  key: (saved!['base'] as Map)[key],
              },
              'p_patch': pending,
            },
          )
          .timeout(const Duration(seconds: 10));
      grant.assertValid(shop, grant.actorId);
      final value = Map<String, dynamic>.from(result as Map);
      if (value['conflict'] == true) {
        throw EmployeeDetailsConflict(
          List<String>.from(value['fields'] as List),
        );
      }
      await cache.acknowledge(
        shop,
        employee,
        pending,
        Map<String, dynamic>.from(value['details'] as Map),
        grant,
      );
    } else {
      final remote = await const BriskersApi()
          .employeeSettingsDetail(shop, employee)
          .timeout(const Duration(seconds: 10));
      grant.assertValid(shop, grant.actorId);
      try {
        final positions = await const BriskersApi()
            .employeePositions(shop)
            .timeout(const Duration(seconds: 5));
        remote['positions'] = [
          for (final position in positions)
            {'id': position['id'], 'name': position['name']},
        ];
      } catch (_) {
        /* Preserve previously saved options when unavailable. */
      }
      await cache.save(shop, employee, remote, grant);
    }
  }
}
