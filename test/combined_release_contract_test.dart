import 'dart:io';

import 'package:briskers_app/core/document_navigation_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice navigation preserves exact role without Office escalation', () {
    for (final role in ['owner', 'office', 'manager', 'mechanic', 'viewer']) {
      expect(documentNavigationRole(roleCode: role, isOwner: role == 'owner'), role);
    }
    expect(documentNavigationRole(isOwner: false), 'viewer');
    expect(documentNavigationRole(isOwner: true), 'owner');
    expect(documentNavigationRole(roleCode: 'mechanic', isOwner: true), 'mechanic');
  });

  test('payment finalization stays Owner-only and independent of Job completion', () {
    final source = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _finalizeEnteredPayments()');
    final end = source.indexOf('Future<void> _enterWarrantyPayment()', start);
    final finalize = source.substring(start, end);
    expect(finalize, contains('if (!widget.isOwner) return;'));
    expect(finalize, contains('_queuedPaymentOperationIds.isNotEmpty'));
    expect(source, contains('if (widget.isOwner) ...['));
    expect(source, contains('Future<void> _offerCompleteJobAfterPaymentEntry()'));
    expect(source, contains('This does not finalize the '));
  });

  test('local note projections protect refresh, PDF and stale signatures', () {
    final source = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    // Local reads can be parallel, but the final invoice projection order
    // must remain Memo -> Finding Notes -> Pending Payments -> Pending Edits.
    expect(source, contains('final parallel = await Future.wait<dynamic>(['));
    expect(source, contains('_pendingMemo.project('));
    expect(source, contains('_offlinePayments.pendingForInvoice('));
    expect(source, contains('_offlinePayments.pendingEditsForInvoice('));
    final projectionStart = source.indexOf(
        'Future<Map<String, dynamic>> _withLocalPayments(');
    final projectionEnd = source.indexOf(
        'Set<String> get _queuedPaymentOperationIds', projectionStart);
    expect(projectionStart, greaterThanOrEqualTo(0));
    expect(projectionEnd, greaterThan(projectionStart));
    final projection = source.substring(projectionStart, projectionEnd);
    final memo = projection.indexOf('final memoProjected =');
    final findings = projection.indexOf('projectInvoiceNotes(');
    final payments = projection.indexOf(
        'OfflineInvoicePaymentLedger.projectPendingPayments(');
    final edits = projection.indexOf(
        'OfflineInvoicePaymentLedger.projectPendingEdits(');
    expect(memo, greaterThanOrEqualTo(0));
    expect(findings, greaterThan(memo));
    expect(payments, greaterThan(findings));
    expect(edits, greaterThan(payments));
    expect(source, contains("_notesController.text = projected['memo']"));
    expect(source, contains("_notesController.text = datedCached['memo']"));
    final start = source.indexOf('Future<Map<String, dynamic>> _pendingMemoForPdf(');
    final end = source.indexOf('Future<Map<String, dynamic>?> _preparePdf()', start);
    final guard = source.substring(start, end);
    expect(guard, contains("projected['_local_pending_memo'] == true"));
    for (final field in ['signature_bytes', 'signer_name', 'signed_at']) {
      expect(guard, contains("projected.remove('$field')"));
    }
    expect(guard, contains("projected['signature_current'] = false"));
    expect(source, contains('return _withPdfUnits(await _pendingMemoForPdf(localDetail))'));
  });
}
