import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/document_edit_permission_cache.dart';

void main() {
  final base = <String, dynamic>{
    'id': 'doc-6330',
    'kind': 'invoice',
    'row_version': 6,
    'legacy_read_only': true,
    'legacy_editable': true,
    'origin': 'mobilebiz',
    'closed_at': null,
  };
  final snapshot = <String, dynamic>{
    'id': 'doc-6330',
    'kind': 'invoice',
    'row_version': 6,
    'memo': 'Original MobileBiz notes',
    'lines': [<String, dynamic>{'id': 'line-1', 'amount': 820.66}],
  };
  test('hydrates only edit-lock metadata without changing details', () {
    final fixed = withVerifiedDocumentEditMetadata(base, snapshot);
    expect(fixed, isNotNull);
    expect(fixed!['legacy_read_only'], true);
    expect(fixed['legacy_editable'], true);
    expect(fixed['lines'], snapshot['lines']);
    expect(fixed['memo'], snapshot['memo']);
    expect(snapshot.containsKey('legacy_read_only'), false);
  });
  test('never trusts a partial or stale server index', () {
    expect(withVerifiedDocumentEditMetadata({...base, 'row_version': 7}, snapshot), isNull);
    expect(withVerifiedDocumentEditMetadata({...base}..remove('legacy_editable'), snapshot), isNull);
    expect(withVerifiedDocumentEditMetadata(base, {...snapshot, 'sync_state': 'pending'}), isNull);
  });
  test('refreshes closed invoice edit lock to read-only', () {
    final stale = {...snapshot, 'legacy_editable': true, 'legacy_read_only': false};
    final updated = withVerifiedDocumentEditMetadata({
      ...base, 'legacy_editable': false, 'closed_at': '2026-10-08T10:00:00Z',
    }, stale);
    expect(updated?['legacy_read_only'], true);
    expect(updated?['legacy_editable'], false);
    expect(updated?['closed_at'], isNotNull);
  });
}
