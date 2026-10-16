import 'owner_job_deletion_v3_contract.dart';

/// A separate, role-filtered companion proves local aliases; ordinary UUID
/// tombstones never imply that a similarly named draft belongs to that Job.
Map<String, Map<String,dynamic>> validateLocalDeletionOrigins(
    Map<String,dynamic> value, {required String businessId, required String actorId,
    required String visibilityScope, required List<Map<String,dynamic>> operations}) {
  const envelopeKeys = {'schema_version','protocol_version','business_id','actor_id','visibility_scope','origins'};
  if (value.length != envelopeKeys.length || !envelopeKeys.every(value.containsKey) ||
      value['schema_version'] != 1 || value['protocol_version'] != 'owner-local-cancellation-1.0' ||
      value['business_id'] != businessId || value['actor_id'] != actorId ||
      value['visibility_scope'] != visibilityScope || value['origins'] is! List) {
    throw const FormatException('Unverified local deletion origin scope.');
  }
  final requested = {for(final op in operations) op['operation_id'] as String:op['job_id']};
  if (requested.length != operations.length || operations.length > 200) throw const FormatException('Duplicate deletion operations.');
  final result = <String,Map<String,dynamic>>{};
  for(final raw in value['origins'] as List) {
    const keys = {'operation_id','job_id','root_origin','local_aliases'};
    if(raw is! Map || raw.length != keys.length || !keys.every(raw.containsKey) ||
        !requested.containsKey(raw['operation_id']) || requested[raw['operation_id']] != raw['job_id'] ||
        !const [null,'job_create','quick_invoice','standalone_estimate_conversion'].contains(raw['root_origin']) ||
        raw['local_aliases'] is! List || result.containsKey(raw['operation_id'])) {
      throw const FormatException('Unverified local deletion origin.');
    }
    final aliases = raw['local_aliases'] as List;
    final root = raw['root_origin'];
    final job = raw['job_id'];
    if ((root == null || root == 'job_create') && aliases.isNotEmpty || aliases.length > 3) {
      throw const FormatException('Unexpected local aliases.');
    }
    final kinds = <String>{};
    for(final alias in aliases) {
      if(alias is! Map || alias.length != 2 || !alias.containsKey('entity_kind') ||
          !alias.containsKey('entity_id') || alias['entity_id'] is! String ||
          !const ['job','invoice','estimate'].contains(alias['entity_kind']) ||
          !kinds.add(alias['entity_kind'] as String)) throw const FormatException('Invalid local alias identity.');
      final kind = alias['entity_kind'];
      final id = alias['entity_id'] as String;
      final valid = kind == 'job'
        ? id == (root == 'quick_invoice' ? 'local-job-$job' : 'local-conversion-job-$job')
        : kind == 'invoice' ? id == 'local-invoice-$job'
        : root == 'standalone_estimate_conversion' && id.startsWith('local-estimate-') && isDeletionV3Id(id.substring('local-estimate-'.length));
      if(!valid) throw const FormatException('Local alias does not match verified origin.');
    }
    if ((root == 'quick_invoice' || root == 'standalone_estimate_conversion') && !kinds.contains('job')) {
      throw const FormatException('Missing local root alias.');
    }
    result[raw['operation_id'] as String] = Map<String,dynamic>.from(raw);
  }
  if(result.length != requested.length) throw const FormatException('Incomplete local deletion origins.');
  return result;
}
