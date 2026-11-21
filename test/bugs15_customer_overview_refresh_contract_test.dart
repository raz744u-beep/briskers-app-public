import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('lib/screens/customers/customer_detail_screen.dart');

  test('Bugs 15: customer overview invalidates on returned document changes', () {
    final source = file.readAsStringSync();
    expect(source, contains('int _activityRevision = 0;'));
    expect(source, contains('void _invalidateCustomerActivity()'));
    expect(source, contains(
      '_jobVisibility.epoch, _activityRevision)),',
    ));
    expect(source, contains('await _refreshEditedCustomerDocument(invoiceId);'));
    expect(
      'await _refreshEditedCustomerDocument(documentId);'
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(2),
    );

    final offlineStart = source.indexOf(
      'if (BriskersConnectionModeController.instance.forceOffline) {',
      source.indexOf('Future<void> _createEstimateForCustomer()'),
    );
    final nextStep = source.indexOf('final history = await _api.customerServiceHistory(',
        offlineStart);
    expect(offlineStart, greaterThan(0));
    expect(nextStep, greaterThan(offlineStart));
    final offlinePath = source.substring(offlineStart, nextStep);
    expect(offlinePath, contains('_invalidateCustomerActivity();'));
    expect(
      offlinePath.lastIndexOf('_invalidateCustomerActivity();'),
      lessThan(offlinePath.lastIndexOf('return;')),
    );
  });

  test('Bugs 15: targeted online indexing cannot overwrite queued edits', () {
    final source = file.readAsStringSync();
    final start = source.indexOf('Future<void> _refreshEditedCustomerDocument(');
    final end = source.indexOf('Future<void> _openOverviewRecord(', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final refresh = source.substring(start, end);
    expect(refresh, contains('_invalidateCustomerActivity();'));
    expect(refresh, contains('forceOffline'));
    expect(refresh, contains("documentId.startsWith('local-estimate-')"));
    expect(refresh, contains("documentId.startsWith('local-invoice-')"));
    expect(refresh, contains("detail['customer_id']?.toString() != widget.customerId"));
    expect(refresh, contains("detail['id']?.toString() != documentId"));
    expect(refresh, contains('LocalDocumentRepository().upsertFromServer('));

    final repository = File('lib/services/local_document_repository.dart')
        .readAsStringSync();
    expect(repository, contains("WHERE local_documents.sync_state = 'synced'"));
  });

  test('Bugs 15: returning from document list/editor refreshes customer panel', () {
    final source = file.readAsStringSync();
    final open = source.substring(
      source.indexOf('Future<void> _openOverviewRecord('),
      source.indexOf('Future<void> _showCustomerDocuments('),
    );
    expect(open, contains('await _refreshEditedCustomerDocument(id);'));
    final listing = source.substring(
      source.indexOf('Future<void> _showCustomerDocuments('),
      source.indexOf('Future<void> _showOverviewList('),
    );
    expect(listing, contains('_invalidateCustomerActivity();'));
  });
}
