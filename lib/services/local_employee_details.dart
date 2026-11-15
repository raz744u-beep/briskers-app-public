import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import 'briskers_api.dart';
import 'employee_nickname_store.dart';
import 'local_owner_authorization.dart';
import 'secure_employee_details_cache.dart';

class EmployeeDetailsConflict implements Exception {
  EmployeeDetailsConflict(this.fields);
  final List<String> fields;
  String get message =>
      'Changes to ${fields.join(', ')} conflict with another device. Your local edits are saved; no server fields were overwritten. Review these fields before syncing.';
}

class LocalEmployeeDetails {
  const LocalEmployeeDetails({
    this.readProfile,
    this.readMetadata,
    this.patchProfile,
    this.patchMetadata,
    this.nicknameStore,
  });
  final Future<Map<String, dynamic>> Function(String, String)? readProfile;
  final Future<Map<String, dynamic>> Function(String, String)? readMetadata;
  final Future<Map<String, dynamic>> Function(
    String, String, Map<String, dynamic>, Map<String, dynamic>
  )? patchProfile;
  final Future<Map<String, dynamic>> Function(
    String, String, Map<String, dynamic>, Map<String, dynamic>
  )? patchMetadata;
  final EmployeeNicknameStore? nicknameStore;
  static const cache = SecureEmployeeDetailsCache();
  static const metadataKeys = {'nickname', 'default_payment_method'};

  Future<Map<String, dynamic>> _profile(String shop, String employee) =>
      readProfile?.call(shop, employee) ??
      const BriskersApi().employeeSettingsDetail(shop, employee);

  Future<Map<String, dynamic>> _metadata(String shop, String employee) async {
    if (readMetadata != null) return readMetadata!(shop, employee);
    final result = await networkSupabase.rpc(
      'briskers_employee_profile_metadata_v1',
      params: {'p_business_id': shop, 'p_employee_id': employee},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> _patch(
    String shop, String employee, Map<String, dynamic> base,
    Map<String, dynamic> patch, {required bool metadata},
  ) async {
    final injected = metadata ? patchMetadata : patchProfile;
    if (injected != null) return injected(shop, employee, base, patch);
    final result = await networkSupabase.rpc(
      metadata
          ? 'briskers_patch_employee_profile_metadata_v1'
          : 'briskers_patch_employee_details_v1',
      params: {
        'p_business_id': shop,
        'p_employee_id': employee,
        'p_base': base,
        'p_patch': patch,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> _sendPending(
    String shop, String employee, LocalOwnerGrant grant,
  ) async {
    for (final metadata in [false, true]) {
      final saved = await cache.read(shop, employee, grant);
      final queued = Map<String, dynamic>.from(saved?['pending'] as Map? ?? {});
      final pending = {
        for (final entry in queued.entries)
          if (metadataKeys.contains(entry.key) == metadata) entry.key: entry.value,
      };
      if (pending.isEmpty) continue;
      final baseline = Map<String, dynamic>.from(saved!['base'] as Map);
      final result = await _patch(
        shop, employee,
        {for (final key in pending.keys) key: baseline[key]},
        pending,
        metadata: metadata,
      ).timeout(const Duration(seconds: 10));
      grant.assertValid(shop, grant.actorId);
      if (result['conflict'] == true) {
        throw EmployeeDetailsConflict(List<String>.from(result['fields'] as List));
      }
      await cache.acknowledge(
        shop, employee, pending,
        Map<String, dynamic>.from(result['details'] as Map), grant,
      );
    }
  }

  /// The two optional metadata fields are synchronized independently from
  /// employment/compensation. A failed endpoint cannot erase a saved profile.
  Future<void> sync(String shop, String employee, LocalOwnerGrant grant) async {
    grant.assertValid(shop, grant.actorId);
    BriskersConnectionModeController.instance.ensureNetworkAllowed();
    final remote = await _profile(shop, employee)
        .timeout(const Duration(seconds: 10));
    grant.assertValid(shop, grant.actorId);
    if (remote['id'] != employee) throw StateError('Employee identity differs.');
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
    // Persist the actual server details first. If the metadata endpoint is
    // unavailable, existing contact, compensation and last-four still load.
    await cache.save(shop, employee, remote, grant);
    await _sendPending(shop, employee, grant);
    final beforeMetadata = await cache.read(shop, employee, grant);
    final metadataWasKnown =
        (beforeMetadata?['details'] as Map?)?.containsKey('nickname') == true;
    final previouslySyncedAlias =
        (beforeMetadata?['details'] as Map?)?['nickname']?.toString() ?? '';
    final meta = await _metadata(shop, employee)
        .timeout(const Duration(seconds: 10));
    grant.assertValid(shop, grant.actorId);
    if (meta['id'] != employee ||
        !meta.containsKey('nickname') ||
        !meta.containsKey('default_payment_method')) {
      throw StateError('Incomplete employee metadata; saved details retained.');
    }
    await cache.save(shop, employee, meta, grant);

    final aliases = nicknameStore ?? EmployeeNicknameStore();
    final local = (await aliases.get(shop, employee))?.trim() ?? '';
    grant.assertValid(shop, grant.actorId);
    final cloud = (meta['nickname'] as String?)?.trim() ?? '';
    if (local.isNotEmpty && local != cloud &&
        (!metadataWasKnown || local != previouslySyncedAlias)) {
      await cache.edit(shop, employee, {'nickname': local}, grant);
      if (cloud.isNotEmpty) {
        throw EmployeeDetailsConflict(const ['nickname']);
      }
      await _sendPending(shop, employee, grant);
    } else if (cloud != local) {
      grant.assertValid(shop, grant.actorId);
      await aliases.save(shop, employee, cloud);
    }
  }

  Future<Map<String, dynamic>> remoteDetail(
    String shop, String employee, LocalOwnerGrant grant,
  ) async {
    grant.assertValid(shop, grant.actorId);
    BriskersConnectionModeController.instance.ensureNetworkAllowed();
    final profile = await _profile(shop, employee)
        .timeout(const Duration(seconds: 10));
    final metadata = await _metadata(shop, employee)
        .timeout(const Duration(seconds: 10));
    grant.assertValid(shop, grant.actorId);
    if (profile['id'] != employee || metadata['id'] != employee) {
      throw StateError('Employee identity differs.');
    }
    return {...profile, ...metadata};
  }
}
