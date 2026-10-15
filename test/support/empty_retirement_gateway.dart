import 'package:briskers_app/services/owner_job_retirement_service.dart';

/// Verified empty v2 feed for synthetic legacy sync fixtures.
class EmptyRetirementGateway extends OwnerJobRetirementGateway {
  const EmptyRetirementGateway();
  @override
  void assertActor(String expectedActorId) {}
  @override
  Future<Map<String, dynamic>> tombstones(
    String businessId, {
    required int afterCursor,
    int limit = 200,
  }) async => {
    'schema_version': 2,
    'business_id': businessId,
    'cursor': afterCursor,
    'has_more': false,
    'actor_id': '00000000-0000-4000-8000-000000000003',
    'reader_scope': 'staff',
    'visibility_scope':
        '1111111111111111111111111111111111111111111111111111111111111111',
    'tombstones': <dynamic>[],
  };
}
