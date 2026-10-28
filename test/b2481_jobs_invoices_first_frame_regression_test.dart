import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cold Jobs dock revisit does not supersede its own pending local read', () {
    final source = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(source, contains('_coldLocalReadScope == requestedScope'));
    expect(source, contains('if (_rows == null) _coldLocalReadScope = coldScope;'));
    expect(source, contains('if (_coldLocalReadScope == coldScope) _coldLocalReadScope = null;'));
    // Never paint a Jobs card until its authorization/retirement filters pass.
    expect(source, contains('final visibleRows = await visibility.filter(rows);'));
    expect(source, contains('if (!mounted || !visibility.isCurrent(generation)) return;'));
  });

  test('Jobs read indexes are not recreated on each tab entry', () {
    final jobs = File('lib/services/local_job_repository.dart').readAsStringSync();
    final begin = jobs.indexOf('Future<List<Map<String, dynamic>>> listJobs(');
    final end = jobs.indexOf('/// Customer navigation uses the same card projection', begin);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    final queryPath = jobs.substring(begin, end);
    expect(queryPath, contains('await LocalJobRetirement.ensureSchema(_database);'));
    expect(queryPath, contains('await _ensureListReadIndexes();'));
    expect(queryPath, isNot(contains('CREATE INDEX IF NOT EXISTS')));
    expect(jobs, contains("Expando<Future<void>>('job_list_read_indexes')"));
    expect(jobs, contains('if (ready != null) return ready;'));
  });

  test('Retirement schema setup is single-flight and preserves safety trigger checks', () {
    final code = File('lib/services/local_job_retirement.dart').readAsStringSync();
    expect(code, contains("Expando<Future<void>>('retirement_schema_in_flight')"));
    expect(code, contains('if (pending != null) return pending;'));
    expect(code, contains('await _ensureSchemaImpl(db);'));
    expect(code, contains("name='retirement_accepted_no_change'"));
    expect(code, contains('CREATE TRIGGER IF NOT EXISTS retirement_'));
  });

  test('Auto document sync captures durable retirement fences once per batch', () {
    final source = File('lib/services/local_document_repository.dart')
        .readAsStringSync();
    final replacement = source.substring(
        source.indexOf('Future<void> replaceFromServer('),
        source.indexOf('/// Record a closure already acknowledged'));
    final upsert = source.substring(
        source.indexOf('Future<void> upsertFromServer('),
        source.indexOf('Future<List<Map<String, dynamic>>> listByKind('));
    for (final batch in [replacement, upsert]) {
      expect(batch, contains('final fences = await _retirementFences(businessId);'));
      expect(batch, contains('blockedDocuments: fences.documents'));
      expect(batch, contains('blockedJobs: fences.jobs'));
      expect(batch, isNot(contains('await _serverDocumentBlocked(')));
    }
    // Protection is still based on permanent/queued retirement states,
    // not on a cached network permission guess.
    expect(source, contains('LocalJobRetirement.blockedDocumentIds('));
    expect(source, contains('LocalJobRetirement.blockedJobIds('));
    expect(source, contains("_visibleDocumentSql('local_documents')"));
    expect(source, contains("WHERE local_documents.sync_state = 'synced'"));
  });

    test('Invoices retain protected offline-first read ahead of receipt hydration', () {
    final code = File('lib/screens/documents_screen.dart').readAsStringSync();
    final begin = code.indexOf('Future<void> _loadOnce() async');
    final firstRead = code.indexOf('firstLocalShown = await _loadLocalRows(', begin);
    final receipt = code.indexOf('final receipts = _refreshReceiptTotals(', begin);
    expect(firstRead, greaterThan(begin));
    expect(receipt, greaterThan(firstRead));
    expect(code, contains('await _localDocuments.listByKind(businessId, kind: kind);'));
    expect(code, contains('if (!mounted || epoch != _loadEpoch ||'));
  });
}
