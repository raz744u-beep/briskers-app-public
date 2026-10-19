import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/services/owner_job_deletion_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

// Audit history is a distinct UUID identity. Accepting its identity from a
// verified server receipt is NOT permission to delete or fabricate one locally.
// The server still rejects audited payments until a reviewed backend overlay
// supports exact ownership and full atomic graph removal.
const business = '00000000-0000-4000-8000-000000000001';
const job = '00000000-0000-4000-8000-000000000002';
const actor = '00000000-0000-4000-8000-000000000003';
const audit = '00000000-0000-4000-8000-000000000004';
const payment = '00000000-0000-4000-8000-000000000005';
const nonce = '00000000-0000-4000-8000-000000000006';
const hash = '1111111111111111111111111111111111111111111111111111111111111111';

Map<String, dynamic> auditedPreview() {
  final ids = [
    {'entity_kind': 'job', 'entity_id': job},
    {'entity_kind': 'payment', 'entity_id': payment},
    {'entity_kind': 'payment_edit_audit', 'entity_id': audit},
  ];
  return {
    'schema_version': 3,
    'protocol_version': ownerDeletionV3Protocol,
    'business_id': business,
    'job_id': job,
    'actor_id': actor,
    'job_number': 'TEST-1',
    'inventory_complete': true,
    'write_fences_verified': true,
    'can_delete': true,
    'blocked_reasons': [],
    'graph_hash': hash,
    'deleted_entities': ids,
    'invoices': [],
    'estimates': [],
    'payments': [
      {
        'entity_kind': 'payment',
        'entity_id': payment,
        'display_label': 'Cash payment',
        'amount': '25.00',
        'currency': 'USD',
        'method_label': 'Cash',
        'version': 'payment-row-hash',
      }
    ],
    'related_records': [
      {
        'entity_kind': 'payment_edit_audit',
        'entity_id': audit,
        'display_label': 'Payment edit audit record',
        'version': 'audit-row-hash',
      }
    ],
    'confirmation': {
      'schema_version': 3,
      'protocol_version': ownerDeletionV3Protocol,
      'scope': 'permanent-full-job',
      'business_id': business,
      'job_id': job,
      'actor_id': actor,
      'preview_id': nonce,
      'graph_hash': hash,
      'issued_at': '2026-10-18T12:00:00.000Z',
      'expires_at': '2026-10-18T13:00:00.000Z',
      'deleted_entities': ids,
    },
  };
}

void main() {
  test('payment edit audit has its own exact UUID kind, never a payment alias', () {
    expect(validDeletionV3Entity('payment_edit_audit', audit, business), isTrue);
    expect(validDeletionV3Entity('payment_edit_audit', 'unverified-row', business), isFalse);
    expect(LocalJobDeletionV3.entityKinds, contains('payment_edit_audit'));
    expect(LocalJobDeletionV3.entityKinds, contains('payment'));
    validateDeletionV3Preview(auditedPreview(), business, job, actor);
  });

  test('audit must appear explicitly in the owner confirmation itemization', () {
    final preview = auditedPreview();
    (preview['related_records'] as List).clear();
    expect(() => validateDeletionV3Preview(preview, business, job, actor),
      throwsFormatException);
  });

  test('audit cannot be hidden as payment or counted twice', () {
    final miscategorized = auditedPreview();
    final record = (miscategorized['related_records'] as List).removeLast();
    (miscategorized['payments'] as List).add(record);
    expect(() => validateDeletionV3Preview(miscategorized, business, job, actor),
      throwsFormatException);
    final duplicated = auditedPreview();
    (duplicated['related_records'] as List).add(
      Map<String, dynamic>.from((duplicated['related_records'] as List).first),
    );
    expect(() => validateDeletionV3Preview(duplicated, business, job, actor),
      throwsFormatException);
  });

  test('changing just audit identity breaks exact confirmation matching', () {
    final preview = auditedPreview();
    (preview['related_records'] as List).first['entity_id'] = nonce;
    expect(() => validateDeletionV3Preview(preview, business, job, actor),
      throwsFormatException);
  });

  test('existing server audit blocker remains non-deletable', () {
    final blocked = auditedPreview();
    blocked['can_delete'] = false;
    blocked['inventory_complete'] = false;
    blocked['confirmation'] = null;
    blocked['blocked_reasons'] = [
      {
        'code': 'unclassified_soft_reference',
        'relation': 'invoice_pending_payment_edit_audit',
        'display_message': 'Payment edit history needs review.',
      },
    ];
    validateDeletionV3Preview(blocked, business, job, actor);
    expect(JobDeletionV3Preview(blocked).canDelete, isFalse);
  });
}
