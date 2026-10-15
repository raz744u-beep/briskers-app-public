import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String path, String start, String end) {
  final source = File(path).readAsStringSync();
  final from = source.indexOf(start);
  expect(from, greaterThanOrEqualTo(0), reason: '$path must retain $start');
  final to = source.indexOf(end, from + start.length);
  expect(to, greaterThan(from), reason: '$path must retain $end');
  return source.substring(from, to).replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  const invoice = 'lib/screens/jobs/job_document_screen.dart';

  test('historical reopen keeps owner/offline/version/audit boundaries', () {
    final action = _section(invoice, 'Future<void> _ownerForceReopen()',
        'Future<void> _enableImportedInvoiceEditing()');
    final confirmation = action.indexOf('await showDialog<String>');
    expect(action.indexOf('if (!_canForceReopen || _busy) return;'),
        inInclusiveRange(0, confirmation - 1));
    expect(action.indexOf('forceOffline'), inInclusiveRange(0, confirmation - 1));
    expect(action, contains('_historicalInvoiceReopenDialog(dialogContext, reason)'));
    final accepted = action.indexOf('if (!mounted || confirmed == null) return;');
    final mutation = action.indexOf('_api.ownerForceReopenInvoice(');
    expect(accepted, greaterThan(confirmation));
    expect(mutation, greaterThan(accepted));
    expect(action, contains('expectedVersion: _version, reason: confirmed'));
    final eligibility = _section(invoice, 'bool get _canForceReopen =>',
        'bool get _canManageInvoiceExpenses =>');
    expect(eligibility, contains('widget.isOwner && !_estimate'));
    expect(eligibility, contains("_detail?['status']?.toString() != 'void'"));
    expect(eligibility, contains("_detail?['legacy_read_only'] == true"));
    expect(eligibility, contains("_detail?['closed_at'] != null"));
  });

  test('payment UI delegates only after unchanged receipt guards and consent', () {
    final action = _section(invoice, 'Future<void> _finalizeEnteredPayments()',
        'Future<void> _enterWarrantyPayment()');
    final dialog = action.indexOf('await showDialog<bool>');
    for (final guard in [
      'if (!widget.isOwner) return;',
      "_number(_detail?['pending_payment']) <= 0.005",
      'BriskersConnectionModeController.instance.forceOffline',
      '_queuedPaymentOperationIds.isNotEmpty',
      '_offlineDocumentDraft.isLocalDraftId(widget.documentId)',
    ]) {
      expect(action.indexOf(guard), inInclusiveRange(0, dialog - 1), reason: guard);
    }
    expect(action, contains('_estimate || _busy'));
    expect(action, contains('_finalizeReceivedPaymentDialog(dialogContext, _money(amount))'));
    final consent = action.indexOf('if (!confirmed || !mounted) return;');
    final durableGuard = action.indexOf('InvoiceFinalizationGuard().run<void>(');
    final mutation = action.indexOf('await _api.finalizePendingInvoicePayment(');
    expect(consent, greaterThan(dialog));
    expect(durableGuard, greaterThan(consent));
    expect(mutation, greaterThan(durableGuard));
    expect(action, contains('invoiceIds: [widget.documentId], isOwner: widget.isOwner'));
    expect(action, contains('if (mounted && succeeded) {'));
    expect(action, contains('await _offerCompletePaidJob();'));
    expect(action, contains('await _autoCloseOwnerInvoiceIfReady();'));
  });

  test('warranty company sheet scrolls around keyboard without bypassing name', () {
    final action = _section(
      'lib/screens/settings/warranty_workflow_settings_screen.dart',
      'Future<void> _editCompany(',
      'Future<void> _editNote(',
    );
    expect(action, contains('useSafeArea: true'));
    expect(action, contains('isScrollControlled: true'));
    expect(action, contains('backgroundColor: Theme.of(context).colorScheme.surface'));
    expect(action, contains('minHeight: MediaQuery.sizeOf(sheetContext).height * 0.65'));
    expect(action, contains('maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.91'));
    expect(action, contains('SingleChildScrollView('));
    expect(action, contains('MediaQuery.viewInsetsOf(sheetContext).bottom + 26'));
    expect(action, contains('if (name.text.trim().isNotEmpty) { Navigator.pop(sheetContext, true);'));
    final cancellation = action.indexOf('if (save != true || companyName.isEmpty) return;');
    expect(cancellation, greaterThan(0));
    expect(action.indexOf('await _api.createWarrantyCompany('), greaterThan(cancellation));
    expect(action.indexOf('await _api.updateWarrantyCompany('), greaterThan(cancellation));
    for (final label in [
      'Company name', 'Claims phone', 'Invoice submission email',
      'Portal / website (optional)', 'Notes (optional)',
    ]) {
      expect(action, contains("labelText: '$label'"));
    }
  });

  test('invoice warranty creation uses tested dialog and validates before RPC', () {
    final action = _section(
      'lib/screens/jobs/invoice_warranty_panel.dart',
      'Future<Map<String, dynamic>?> _createCompany(',
      'Future<void> _saveLocalWarranty(',
    );
    expect(action, contains('_createWarrantyCompanyDialog('));
    expect(action, contains('autofocusName: initialName.isEmpty'));
    final validation = action.indexOf('if (save != true || companyName.isEmpty) return null;');
    expect(validation, greaterThan(0));
    expect(action.indexOf('await _api.createWarrantyCompany('), greaterThan(validation));
    expect(action, contains('final companyName = name.text.trim();'));
    expect(action, contains('final claimsPhone = formatWarrantyPhone(phone.text.trim());'));
    expect(action, contains('final submissionEmail = email.text.trim();'));
  });

  for (final entry in [
    (
      path: 'lib/screens/jobs/job_detail_screen.dart',
      end: 'Future<void> _editFinding(',
      mutation: 'await _offlineWorkFindings.createLocalFinding(',
    ),
    (
      path: 'lib/screens/customers/customer_vehicle_findings_section.dart',
      end: 'Future<void> _showPhotoGallery(',
      mutation: 'await _offlineWrites.createFinding(',
    ),
  ]) {
    test('finding sheet stays keyboard-safe, teal, and guarded in ${entry.path}', () {
      final action = _section(entry.path, 'Future<void> _addFinding()', entry.end);
      expect(action, contains('useSafeArea: true'));
      expect(action, contains('isScrollControlled: true'));
      expect(action, contains('backgroundColor: Theme.of(context).colorScheme.surface'));
      expect(action, contains('minHeight: MediaQuery.sizeOf(sheetContext).height * 0.48'));
      expect(action, contains('maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84'));
      expect(action, contains('SingleChildScrollView('));
      expect(action, contains('MediaQuery.viewInsetsOf(sheetContext).bottom + 28'));
      expect(action, contains('backgroundColor: Colors.teal.shade700'));
      expect(action, contains('Icon(Icons.photo_library_outlined, color: Colors.teal)'));
      expect(action, contains('Icon(Icons.photo_camera_outlined, color: Colors.teal)'));
      expect(action, contains('if (controller.text.trim().isEmpty) return;'));
      final cancel = action.indexOf('if (save != true || body.isEmpty) return;');
      expect(cancel, greaterThan(0));
      expect(action.indexOf(entry.mutation), greaterThan(cancel));
      expect(action, contains('includeOnInvoice: includeOnInvoice'));
      expect(action, contains('source: ImageSource.camera'));
      expect(action, contains('maxWidth: 1920, maxHeight: 1920'));
    });
  }
}
