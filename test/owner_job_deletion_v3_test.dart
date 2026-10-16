import 'dart:async';
import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/owner_job_deletion_service_v3.dart';
import 'package:briskers_app/services/owner_job_deletion_v3_contract.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:briskers_app/screens/jobs/owner_job_delete_v3_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const business = '00000000-0000-4000-8000-000000000001';
const job = '00000000-0000-4000-8000-000000000002';
const actor = '00000000-0000-4000-8000-000000000003';
const nonce = '00000000-0000-4000-8000-000000000004';
const payment = '00000000-0000-4000-8000-000000000005';
const hash = '1111111111111111111111111111111111111111111111111111111111111111';
final now = DateTime.utc(2026, 10, 16, 1);
Map<String, dynamic> fixture() {
  final entities = [
    {'entity_kind': 'job', 'entity_id': job},
    {'entity_kind': 'payment', 'entity_id': payment},
  ];
  final confirmation = <String, dynamic>{
    'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
    'scope': 'permanent-full-job', 'business_id': business, 'job_id': job,
    'actor_id': actor, 'preview_id': nonce, 'graph_hash': hash,
    'issued_at': now.toIso8601String(),
    'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
    'deleted_entities': entities,
  };
  return {
    'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
    'business_id': business, 'job_id': job, 'actor_id': actor,
    'job_number': 'TEST-1', 'inventory_complete': true,
    'write_fences_verified': true, 'can_delete': true,
    'blocked_reasons': [], 'graph_hash': hash, 'deleted_entities': entities,
    'invoices': [], 'estimates': [], 'related_records': [],
    'payments': [{
      'entity_kind': 'payment', 'entity_id': payment,
      'display_label': 'Payment TEST-P1', 'version': 'v1',
      'amount': '12.34', 'currency': 'USD', 'method_label': 'Cash',
    }],
    'confirmation': confirmation,
  };
}

class Gateway extends JobDeletionV3Gateway {
  String signedInActor = actor;
  Object? previewError;
  Future<Map<String, dynamic>> Function(String)? onStatus;
  final calls = <String>[];
  final feedCalls = <int>[];
  Future<Map<String, dynamic>> Function(int)? onFeed;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? onExecute;
  @override
  void assertActor(String expected) {
    if (signedInActor != expected) throw StateError('Session changed');
  }
  @override
  Future<Map<String, dynamic>> preview(String business, String job) async {
    if (previewError != null) throw previewError!;
    return fixture();
  }
  @override
  Future<Map<String, dynamic>> status(String business, String operation) async => onStatus!(operation);
  @override
  Future<Map<String, dynamic>> tombstones(String business, int cursor) async {
    feedCalls.add(cursor);
    if (onFeed != null) return onFeed!(cursor);
    return {'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
      'business_id': business, 'actor_id': actor, 'reader_scope': 'staff',
      'visibility_scope': hash, 'cursor': cursor, 'has_more': false, 'tombstones': []};
  }
  @override
  Future<Map<String, dynamic>> execute(String b, String j, String op,
      Map<String, dynamic> confirmation) async {
    calls.add(op);
    if (onExecute != null) return onExecute!(op, confirmation);
    throw TimeoutException('simulated lost response');
  }
}

Map<String, dynamic> receipt(String op, Map<String, dynamic> confirmation) => {
  'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
  'business_id': business, 'job_id': job, 'actor_id': actor,
  'operation_id': op, 'graph_hash': hash,
  'deleted_entities': confirmation['deleted_entities'],
  'status': 'deleted', 'storage_cleanup': 'not_required', 'status_version': 1,
  'committed_at': now.toIso8601String(), 'cleanup_completed_at': now.toIso8601String(),
};

void main() {
  test('v3 exact itemized inventory and defensive consent copies', () {
    final value = fixture();
    validateDeletionV3Preview(value, business, job, actor);
    final preview = JobDeletionV3Preview(value);
    (preview.snapshot['payments'] as List).clear();
    expect(preview.snapshot['payments'], hasLength(1));
    final broken = fixture();
    broken['payments'] = [];
    expect(() => validateDeletionV3Preview(broken, business, job, actor), throwsFormatException);
  });
  test('old retirement consent never authorizes v3 purge', () {
    for (final key in ['schema_version', 'protocol_version', 'scope', 'preview_id']) {
      final value = fixture();
      (value['confirmation'] as Map)[key] = 'old';
      expect(() => validateDeletionV3Preview(value, business, job, actor), throwsFormatException);
    }
  });
  test('payment method and amount cannot disappear from confirmation', () {
    for (final key in ['amount', 'method_label']) {
      final value = fixture();
      ((value['payments'] as List).single as Map).remove(key);
      expect(() => validateDeletionV3Preview(value, business, job, actor), throwsFormatException);
    }
  });
  test('blocked preview has no usable confirmation', () {
    final value = fixture()..['can_delete'] = false..['confirmation'] = null;
    value['blocked_reasons'] = [{'display_message': 'Shared record'}];
    validateDeletionV3Preview(value, business, job, actor);
    expect(JobDeletionV3Preview(value).canDelete, isFalse);
  });

  test('nonce lifetime and minimal confirmation fields are enforced', () {
    final value = fixture();
    (value['confirmation'] as Map)['expires_at'] = now.add(const Duration(days: 2)).toIso8601String();
    expect(() => validateDeletionV3Preview(value, business, job, actor), throwsFormatException);
    final extra = fixture();
    (extra['confirmation'] as Map)['payment_original'] = {'amount': '12.34'};
    expect(() => validateDeletionV3Preview(extra, business, job, actor), throwsFormatException);
  });
  test('known operation namespaces and composite keys only', () {
    expect(validDeletionV3Entity('operation', 'standalone_estimate/offline-key', business), isTrue);
    expect(validDeletionV3Entity('operation', 'financial_transaction/offline-key', business), isTrue);
    expect(validDeletionV3Entity('operation', 'unknown/offline-key', business), isFalse);
    expect(validDeletionV3Entity('receipt_detail',
      '{"business_id": "$business", "transaction_id": "$payment"}', business), isTrue);
    expect(validDeletionV3Entity('receipt_detail',
      '{"business_id": "$actor", "transaction_id": "$payment"}', business), isFalse);
  });
  test('numberless draft is explicitly labeled and still identity-bound', () {
    final value = fixture();
    final item = {'entity_kind': 'estimate', 'entity_id': nonce,
      'number': null, 'status': 'draft', 'display_label': 'Unnumbered estimate', 'version': 'v1'};
    (value['estimates'] as List).add(item);
    (value['deleted_entities'] as List).add({'entity_kind': 'estimate', 'entity_id': nonce});
    validateDeletionV3Preview(value, business, job, actor);
    item['display_label'] = 'Unknown';
    expect(() => validateDeletionV3Preview(value, business, job, actor), throwsFormatException);
  });
  test('transaction cannot evade payment details through related category', () {
    final value = fixture();
    value['related_records'] = value['payments'];
    value['payments'] = [];
    expect(() => validateDeletionV3Preview(value, business, job, actor), throwsFormatException);
  });
  test('unavailable and state errors never show technical Bad state prefix', () {
    expect(deletionV3FailureMessage(const JobDeletionV3Unavailable()),
      'Job deletion is temporarily unavailable. Nothing has been deleted.');
    expect(deletionV3FailureMessage(StateError('Connect to review records.')),
      'Connect to review records.');
  });

  testWidgets('one irreversible confirmation itemizes payment and cancellation sends nothing', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        confirmed = await showOwnerJobDeleteV3Confirmation(context,
          preview: JobDeletionV3Preview(fixture()));
      }, child: const Text('Open deletion')),
    ))));
    await tester.tap(find.text('Open deletion'));
    await tester.pumpAndSettle();
    expect(find.text('Permanently delete Job TEST-1?'), findsOneWidget);
    expect(find.text('Payment TEST-P1 · USD 12.34 · Cash'), findsOneWidget);
    expect(find.text('Permanently delete these records'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });

  test('receipt cannot claim deletion while storage remains pending', () {
    final confirmation = Map<String, dynamic>.from(fixture()['confirmation'] as Map);
    final receipt = <String, dynamic>{
      'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
      'business_id': business, 'job_id': job, 'actor_id': actor,
      'operation_id': nonce, 'graph_hash': hash,
      'deleted_entities': confirmation['deleted_entities'],
      'status': 'deleted', 'storage_cleanup': 'not_required', 'status_version': 1,
      'committed_at': now.toIso8601String(), 'cleanup_completed_at': now.toIso8601String(),
    };
    validateDeletionV3Receipt(receipt, confirmation, nonce);
    receipt['storage_cleanup'] = 'pending';
    expect(() => validateDeletionV3Receipt(receipt, confirmation, nonce), throwsFormatException);
    receipt['status'] = 'purging';
    receipt['cleanup_completed_at'] = null;
    validateDeletionV3Receipt(receipt, confirmation, nonce);
    receipt['original_invoice'] = {'number': 'TEST-1'};
    expect(() => validateDeletionV3Receipt(receipt, confirmation, nonce), throwsFormatException);
  });

  late BriskersLocalDatabase db;
  late Gateway gateway;
  late OwnerJobDeletionServiceV3 service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    gateway = Gateway();
    service = OwnerJobDeletionServiceV3(database: db, gateway: gateway, clock: () => now);
  });
  tearDown(() async => db.close());

  test('missing backend yields simple availability error, no request', () async {
    gateway.previewError = const PostgrestException(
      message: 'Missing briskers_job_delete_preview_v3', code: 'PGRST202');
    await expectLater(service.preview(business, job, actorId: actor, isOwner: true),
      throwsA(isA<JobDeletionV3Unavailable>()));
    expect(await db.customSelect('SELECT * FROM local_job_deletion_v3_requests').get(), isEmpty);
    expect(gateway.calls, isEmpty);
  });
  test('offline without verified preview cannot enqueue destructive consent', () async {
    await expectLater(service.preview(business, job, actorId: actor, isOwner: true, online: false), throwsStateError);
    expect(gateway.calls, isEmpty);
  });
  test('offline exact consent persists only minimal envelope before send', () async {
    await service.preview(business, job, actorId: actor, isOwner: true);
    final cached = await service.preview(business, job, actorId: actor, isOwner: true, online: false);
    expect(cached.fromCache, isTrue);
    final result = await service.queueConfirmed(cached, actorId: actor, isOwner: true, online: false);
    expect(result.state, 'queued');
    final row = await db.customSelect('SELECT * FROM local_job_deletion_v3_requests').getSingle();
    final stored = row.read<String>('confirmation_json');
    expect(jsonDecode(stored), cached.confirmation);
    expect(stored, isNot(contains('12.34')));
    expect(stored, isNot(contains('Cash')));
    expect(gateway.calls, isEmpty);
  });
  test('lost response then denied retry stays same uncertain operation', () async {
    final preview = await service.preview(business, job, actorId: actor, isOwner: true);
    await service.queueConfirmed(preview, actorId: actor, isOwner: true);
    expect((await service.status(business, job)).state, 'pending');
    gateway.onExecute = (_, _) async => throw const PostgrestException(message: 'Owner changed', code: '42501');
    await service.flush(business);
    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.toSet(), hasLength(1));
    expect((await service.status(business, job)).state, 'pending');
    await expectLater(service.queueConfirmed(preview, actorId: actor, isOwner: true), throwsStateError);
  });
  test('changed actor cannot confirm another owners cached graph', () async {
    final preview = await service.preview(business, job, actorId: actor, isOwner: true);
    gateway.signedInActor = nonce;
    await expectLater(service.queueConfirmed(preview, actorId: actor, isOwner: true), throwsStateError);
    expect(gateway.calls, isEmpty);
  });  test('concurrent feed pulls share one traversal and scope changes replay', () async {
    final gate = Completer<Map<String, dynamic>>();
    gateway.onFeed = (_) => gate.future;
    final first = service.pullTombstones(business);
    final second = service.pullTombstones(business);
    await Future<void>.delayed(Duration.zero);
    gate.complete({'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
      'business_id': business, 'actor_id': actor, 'reader_scope': 'staff',
      'visibility_scope': hash, 'cursor': 0, 'has_more': false, 'tombstones': []});
    await Future.wait([first, second]);
    expect(gateway.feedCalls, [0]);
    gateway.onFeed = (_) async => {'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
      'business_id': business, 'actor_id': actor, 'reader_scope': 'customer',
      'visibility_scope': '2222222222222222222222222222222222222222222222222222222222222222',
      'cursor': 0, 'has_more': false, 'tombstones': []};
    await service.pullTombstones(business);
    expect(gateway.feedCalls, [0, 0, 0]);
  });
  test('invalid incomplete operation cannot advance deletion cursor', () async {
    gateway.onFeed = (_) async => {'schema_version': 3, 'protocol_version': ownerDeletionV3Protocol,
      'business_id': business, 'actor_id': actor, 'reader_scope': 'staff',
      'visibility_scope': hash, 'cursor': 1, 'has_more': false,
      'tombstones': [{'cursor': 1, 'business_id': business, 'job_id': job,
        'operation_id': nonce, 'scope_complete': false, 'status': 'deleted',
        'storage_cleanup': 'not_required', 'status_version': 1,
        'deleted_entities': [{'entity_kind': 'job', 'entity_id': job}]}]};
    await expectLater(service.pullTombstones(business), throwsFormatException);
    expect(await db.customSelect('SELECT * FROM local_job_deletion_v3_feed').get(), isEmpty);
  });
  test('verified receipt scrubs preview and never stores payment originals', () async {
    gateway.onExecute = (op, confirmation) async => receipt(op, confirmation);
    final preview = await service.preview(business, job, actorId: actor, isOwner: true);
    final result = await service.queueConfirmed(preview, actorId: actor, isOwner: true);
    expect(result.state, 'deleted');
    expect(await db.customSelect('SELECT * FROM local_job_deletion_v3_previews').get(), isEmpty);
    final stored = await db.customSelect('SELECT confirmation_json,receipt_json FROM local_job_deletion_v3_requests').getSingle();
    expect(stored.data.toString(), isNot(contains('12.34')));
    expect(stored.data.toString(), isNot(contains('Cash')));
    await service.flush(business);
    expect(gateway.calls, hasLength(1));
  });
  test('server deleted cannot regress while local cleanup waits', () async {
    gateway.onExecute = (op, confirmation) async {
      await db.customStatement('CREATE TABLE IF NOT EXISTS local_job_recovery_receipts (id INTEGER PRIMARY KEY,business_id TEXT,outbox_id INTEGER,response_json TEXT)');
      await db.customStatement("INSERT INTO local_job_recovery_receipts (business_id,outbox_id,response_json) VALUES (?,NULL,'malformed response')", [business]);
      return receipt(op, confirmation);
    };
    final preview = await service.preview(business, job, actorId: actor, isOwner: true);
    await service.queueConfirmed(preview, actorId: actor, isOwner: true, online: false);
    await service.flush(business);
    expect((await service.status(business, job)).state, 'purging');
    gateway.onStatus = (op) async => receipt(op, preview.confirmation)
      ..['status'] = 'purging'..['storage_cleanup'] = 'pending'
      ..['status_version'] = 2..['cleanup_completed_at'] = null;
    await service.flush(business);
    final stored = await db.customSelect('SELECT receipt_json FROM local_job_deletion_v3_requests').getSingle();
    expect((jsonDecode(stored.read<String>('receipt_json')) as Map)['status'], 'deleted');
  });

}
