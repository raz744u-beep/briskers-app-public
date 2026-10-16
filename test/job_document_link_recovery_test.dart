import 'dart:io';

import 'package:briskers_app/services/job_document_link_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale detail cannot override a document linked to another Job', () {
    expect(canRecoverLegacyJobDocumentLink(
      requestedJobId: 'old', indexedJobId: 'current',
    ), isFalse);
    for (final indexed in [null, '', '   ', 'old']) {
      expect(canRecoverLegacyJobDocumentLink(
        requestedJobId: 'old', indexedJobId: indexed,
      ), isTrue);
    }
    expect(canRecoverLegacyJobDocumentLink(
      requestedJobId: '', indexedJobId: null,
    ), isFalse);
  });

  test('authoritative unlink wins unless detail is strictly newer', () {
    for (final version in [3, 4]) {
      expect(isLegacyJobDocumentDetailCurrent(
        index: {'job_id': null, 'row_version': 4},
        detail: {'job_id': 'old', 'row_version': version},
      ), isFalse);
    }
    expect(isLegacyJobDocumentDetailCurrent(
      index: {'job_id': null, 'row_version': 4},
      detail: {'job_id': 'old', 'row_version': 5},
    ), isTrue);
    expect(isLegacyJobDocumentDetailCurrent(
      index: {'row_version': 4}, detail: {},
    ), isFalse);
    expect(isLegacyJobDocumentDetailCurrent(
      index: {'updated_at': '2026-10-15T12:00:00Z'},
      detail: {'updated_at': '2026-10-15T11:00:00Z'},
    ), isFalse);
    expect(isLegacyJobDocumentDetailCurrent(index: {}, detail: {}), isTrue);
    expect(isLegacyJobDocumentDetailCurrent(
      index: {'row_version': 4}, detail: {'row_version': 4},
    ), isTrue);
  });

  test('reassignment during detail load is not displayed or written back', () async {
    final original = <String, dynamic>{'id': 'doc', 'job_id': null};
    var current = original;
    final result = await recoverLegacyJobDocuments(
      requestedJobId: 'old', candidates: [original],
      readDetail: (id) async {
        current = {'id': id, 'job_id': 'new', 'row_version': 4};
        return {'id': id, 'job_id': 'old', 'row_version': 3};
      },
      readCurrentIndex: () async => [current],
    );
    expect(result, isEmpty);
    expect(current['job_id'], 'new');
  });

  test('known conflict skips detail and orphan recovery preserves index', () async {
    final conflicting = await recoverLegacyJobDocuments(
      requestedJobId: 'old', candidates: [{'id': 'doc', 'job_id': 'new'}],
      readDetail: (_) async => throw StateError('Must not read stale detail'),
      readCurrentIndex: () async => [],
    );
    expect(conflicting, isEmpty);
    final orphan = <String, dynamic>{'id': 'doc', 'job_id': null};
    final recovered = await recoverLegacyJobDocuments(
      requestedJobId: 'old', candidates: [orphan],
      readDetail: (id) async => {'id': id, 'job_id': 'old'},
      readCurrentIndex: () async => [orphan],
    );
    expect(recovered.single['job_id'], 'old');
    expect(orphan['job_id'], isNull);
    final mismatched = await recoverLegacyJobDocuments(
      requestedJobId: 'old', candidates: [orphan],
      readDetail: (_) async => {'id': 'wrong-doc', 'job_id': 'old'},
      readCurrentIndex: () async => [orphan],
    );
    expect(mismatched, isEmpty);
  });

  test('legacy fallback is display-only and cannot replace online documents', () {
    final source = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final recovery = source.substring(
      source.indexOf('Future<List<Map<String, dynamic>>> _localDocumentsForJob'),
      source.indexOf('void _scheduleInitialAction'),
    );
    expect(recovery, contains('recoverLegacyJobDocuments('));
    expect(recovery, isNot(contains('upsertFromServer')));
    expect(source, contains('if (mounted && !_onlineReady)'));
  });
}
