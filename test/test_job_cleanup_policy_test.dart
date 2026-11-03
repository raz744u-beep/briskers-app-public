import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/test_job_cleanup_policy.dart';

Map<String, dynamic> cleanupPreview({String jobNumber = 'J-8'}) => {
  'schema_version': 1, 'business_id': 'shop', 'job_id': 'job',
  'job_number': jobNumber, 'rollout_enabled': true,
  'can_delete': true, 'blocked_reasons': <String>[],
  'documents': <Map<String, dynamic>>[], 'dependencies': <String, int>{},
  'fingerprint': 'verified-test-fingerprint',
};

void main() {
  final now = DateTime.utc(2026, 10, 13);
  TestJobCleanupPlan parse(Map<String, dynamic> value) =>
      TestJobCleanupPlan.fromJson(value, businessId: 'shop', jobId: 'job', receivedAt: now);

  test('owner exact confirmation and fresh authoritative preview required', () {
    final plan = parse(cleanupPreview());
    expect(plan.canDelete, isTrue);
    expect(() => TestJobCleanupPolicy.requireExecutable(plan,
      roleCode: 'owner', confirmation: 'DELETE TEST J-8', now: now), returnsNormally);
    for (final role in ['office', 'manager', 'mechanic', '', 'Owner']) {
      expect(() => TestJobCleanupPolicy.requireExecutable(plan,
        roleCode: role, confirmation: plan.confirmationText, now: now), throwsStateError);
    }
    expect(() => TestJobCleanupPolicy.requireExecutable(plan,
      roleCode: 'owner', confirmation: 'DELETE TEST J-9', now: now), throwsStateError);
    expect(() => TestJobCleanupPolicy.requireExecutable(plan,
      roleCode: 'owner', confirmation: plan.confirmationText,
      now: now.add(const Duration(minutes: 3))), throwsStateError);
    expect(() => TestJobCleanupPolicy.requireExecutable(plan,
      roleCode: 'owner', confirmation: plan.confirmationText,
      now: now.subtract(const Duration(seconds: 1))), throwsStateError);
  });

  test('real protected records never become cleanup candidates', () {
    for (final number in ['J7', 'J-007', 'J11', 'J-12']) {
      expect(parse(cleanupPreview(jobNumber: number)).canDelete, isFalse);
    }
    for (final number in ['6331', 'I-6332', '6334', '1997']) {
      final value = cleanupPreview();
      value['documents'] = [{
        'id': 'document', 'kind': number == '1997' ? 'estimate' : 'invoice',
        'number': number, 'status': 'draft', 'total': 0,
      }];
      expect(parse(value).canDelete, isFalse);
    }
  });

  test('missing or disabled rollout fails closed', () {
    expect(() => parse(cleanupPreview()..remove('rollout_enabled')), throwsFormatException);
    final plan = parse(cleanupPreview()..['rollout_enabled'] = false);
    expect(plan.canDelete, isFalse);
    expect(plan.blockedReasons.join(), contains('rollout'));
  });

  test('wrong scope, unknown schema, malformed lists and duplicate IDs reject', () {
    for (final pair in <String, dynamic>{
      'schema_version': 2, 'business_id': 'other', 'job_id': 'other',
      'can_delete': 'true', 'documents': null, 'blocked_reasons': [null],
      'dependencies': {'payments': null}, 'fingerprint': '',
    }.entries) {
      expect(() => parse(cleanupPreview()..[pair.key] = pair.value), throwsFormatException,
        reason: pair.key);
    }
    final doc = {'id': 'd', 'kind': 'estimate', 'number': null, 'status': 'draft', 'total': 137.19};
    expect(() => parse(cleanupPreview()..['documents'] = [doc, doc]), throwsFormatException);
  });

  test('server refusal and local blockers cannot be cleared by caller', () {
    final blocked = parse(cleanupPreview()..['can_delete'] = false);
    expect(blocked.canDelete, isFalse);
    expect(blocked.blockedReasons, isNotEmpty);
    final local = parse(cleanupPreview()).withLocalBlockers(['Payment queued']);
    expect(local.withLocalBlockers([]).canDelete, isFalse);
    expect(() => local.blockedReasons.clear(), throwsUnsupportedError);
  });

  test('deletion feed rejects malformed or wrong business evidence', () {
    final value = {'schema_version': 1, 'business_id': 'shop',
      'deleted_job_ids': ['job'], 'deleted_document_ids': ['doc']};
    expect(TestJobCleanupTombstones.fromJson(value, 'shop').jobIds, {'job'});
    expect(() => TestJobCleanupTombstones.fromJson(value, 'other'), throwsFormatException);
    expect(() => TestJobCleanupTombstones.fromJson({...value, 'deleted_document_ids': null}, 'shop'),
      throwsFormatException);
  });
}
