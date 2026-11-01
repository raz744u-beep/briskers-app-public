import 'package:briskers_app/services/local_deletion_origins_contract.dart';
import 'package:flutter_test/flutter_test.dart';
const business='10000000-0000-4000-8000-000000000001';
const actor='10000000-0000-4000-8000-000000000002';
const job='10000000-0000-4000-8000-000000000003';
const operation='10000000-0000-4000-8000-000000000004';
const source='10000000-0000-4000-8000-000000000005';
Map<String,dynamic> origin({String? kind='quick_invoice'}) => {'operation_id':operation,'job_id':job,'root_origin':kind,'local_aliases':kind==null?<dynamic>[]:[{'entity_kind':'job','entity_id':kind=='quick_invoice'?'local-job-$job':'local-conversion-job-$job'}]};
Map<String,dynamic> envelope(Map<String,dynamic> value) => {'schema_version':1,'protocol_version':'owner-local-cancellation-1.0','business_id':business,'actor_id':actor,'visibility_scope':'scope','origins':[value]};
Map<String,Map<String,dynamic>> check(Map<String,dynamic> value) => validateLocalDeletionOrigins(value,businessId:business,actorId:actor,visibilityScope:'scope',operations:[{'operation_id':operation,'job_id':job}]);
void main(){
 test('remote operation explicitly has no aliases',(){expect(check(envelope(origin(kind:null)))[operation]!['local_aliases'],isEmpty);});
 test('staff job-only alias allowed without financial identity',(){expect(check(envelope(origin()))[operation]!['local_aliases'],hasLength(1));});
 test('conversion source estimate must have exact typed UUID alias',(){final o=origin(kind:'standalone_estimate_conversion');(o['local_aliases'] as List).add({'entity_kind':'estimate','entity_id':'local-estimate-$source'});expect(check(envelope(o)),hasLength(1));});
 test('scope mismatch missing operation and wrong root alias fail closed',(){
  expect(()=>check(envelope(origin())..['actor_id']=source),throwsFormatException);
  expect(()=>check(envelope(origin())..['visibility_scope']='other'),throwsFormatException);
  expect(()=>check(envelope(origin())..['origins']=[]),throwsFormatException);
  final o=origin();o['local_aliases']=[{'entity_kind':'job','entity_id':'local-job-$source'}];expect(()=>check(envelope(o)),throwsFormatException);
 });
 test('remote graph never authorizes inferred local aliases',(){final o=origin(kind:null);o['local_aliases']=[{'entity_kind':'job','entity_id':'local-job-$job'}];expect(()=>check(envelope(o)),throwsFormatException);});
}
