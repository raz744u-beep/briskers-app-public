import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/connection_mode.dart';
import '../../core/briskers_colors.dart';
import '../../core/module_modal_theme.dart';
import '../../local/local_database_provider.dart';
import '../../services/briskers_api.dart';
import '../../services/local_document_detail_cache.dart';
import '../../services/local_document_repository.dart';
import '../../services/local_job_quarantine.dart';
import '../../services/offline_invoice_payment_ledger.dart';
import 'job_document_screen.dart';

bool canOpenJobInvoicePayment(String roleCode) =>
    const {'owner', 'manager', 'office'}.contains(roleCode);

num? _amount(Object? value) {
  final number = value is num ? value : num.tryParse(value?.toString() ?? '');
  return number != null && number.isFinite ? number : null;
}

/// Pending receipts remain eligible so the existing Payment tab can show them.
/// Never treat an unknown balance, void, closed, or historical lock as payable.
bool isJobInvoicePaymentEligible(Map<String, dynamic> invoice) {
  if (invoice['kind'] != 'invoice' ||
      (invoice['id']?.toString().trim().isEmpty ?? true) ||
      invoice['closed_at'] != null ||
      invoice['legacy_read_only'] == true) {
    return false;
  }
  final status = invoice['status']?.toString().toLowerCase();
  final displayStatus = invoice['display_status_code']
      ?.toString()
      .toLowerCase();
  if (const {
        'void',
        'voided',
        'cancelled',
        'canceled',
        'closed',
        'paid',
      }.contains(status) ||
      const {'void', 'closed', 'paid'}.contains(displayStatus)) {
    return false;
  }
  final total = _amount(invoice['total_amount']);
  final paid = _amount(invoice['paid_amount']);
  final pending = _amount(invoice['pending_payment']);
  if (total == null ||
      paid == null ||
      pending == null ||
      total < 0 ||
      paid < 0 ||
      pending < 0) {
    return false;
  }
  return total - paid > 0.005 || pending > 0.005;
}

/// The local document index has placeholder payment zeros. Only a complete,
/// correctly linked detail plus the receipt ledger can supply an offline balance.
Map<String, dynamic>? cachedJobInvoicePaymentSnapshot(
  Map<String, dynamic> row,
  Map<String, dynamic>? detail, {
  required String jobId,
  List<Map<String, dynamic>> queuedPayments = const [],
}) {
  final id = row['id']?.toString() ?? '';
  if (detail == null ||
      id.isEmpty ||
      detail['id']?.toString() != id ||
      detail['job_id']?.toString() != jobId ||
      detail['kind'] != 'invoice' ||
      (!detail.containsKey('legacy_read_only') &&
          !id.startsWith('local-invoice-')) ||
      _amount(detail['total_amount']) == null ||
      _amount(detail['paid_amount']) == null ||
      _amount(detail['pending_payment']) == null) {
    return null;
  }
  final invoice = OfflineInvoicePaymentLedger.projectPendingPayments({
    ...row,
    ...detail,
  }, queuedPayments);
  return isJobInvoicePaymentEligible(invoice) ? invoice : null;
}

Future<Map<String, dynamic>?> chooseJobInvoice(
  BuildContext context, {
  required List<Map<String, dynamic>> invoices,
  required String title,
  bool showBalance = false,
}) async {
  if (invoices.isEmpty) return null;
  if (invoices.length == 1) return invoices.single;
  final money = NumberFormat.simpleCurrency();
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: moduleModalTheme(Theme.of(context), BriskersColors.invoices).colorScheme.surface,
    isScrollControlled: true,
    builder: (sheetContext) => Theme(
      data: moduleModalTheme(Theme.of(sheetContext), BriskersColors.invoices),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            for (final invoice in invoices)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  'Invoice #${invoice['document_number'] ?? 'Pending sync'}',
                ),
                subtitle: showBalance
                    ? Text(
                        'Balance ${money.format(((_amount(invoice['total_amount']) ?? 0) - (_amount(invoice['paid_amount']) ?? 0) - (_amount(invoice['pending_payment']) ?? 0)).clamp(0, double.infinity))}'
                        '${(_amount(invoice['pending_payment']) ?? 0) > .005 ? ' · Payment pending' : ''}',
                      )
                    : null,
                onTap: () => Navigator.pop(sheetContext, invoice),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Opens the existing payment workspace; it never records or finalizes money.
Future<bool> openJobInvoicePayment(
  BuildContext context, {
  required String businessId,
  required String jobId,
  required String roleCode,
  List<Map<String, dynamic>>? documents,
}) async {
  final originRoute = ModalRoute.of(context);
  bool stillCurrent() => context.mounted && (originRoute?.isCurrent ?? true);
  void notice(String message) {
    if (stillCurrent()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  if (!canOpenJobInvoicePayment(roleCode)) {
    notice('Your role cannot manage invoice payments.');
    return false;
  }
  const api = BriskersApi();
  const cache = LocalDocumentDetailCache();
  final offline = BriskersConnectionModeController.instance.forceOffline;
  try {
    if (await LocalJobQuarantine.isJobBlocked(
      localDatabase,
      businessId,
      jobId,
    )) {
      notice(
        'Job access has changed. Connect and refresh before adding a payment.',
      );
      return false;
    }
    final rows = offline
        ? await LocalDocumentRepository().listByJob(businessId, jobId)
        : documents ?? await api.jobDocuments(businessId, jobId);
    final invoices = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row['kind'] != 'invoice') continue;
      var invoice = row;
      if (offline) {
        final id = row['id']?.toString() ?? '';
        final detail = await cache.load(businessId, id);
        final saved = cachedJobInvoicePaymentSnapshot(
          row,
          detail,
          jobId: jobId,
          queuedPayments: await OfflineInvoicePaymentLedger().pendingForInvoice(
            businessId,
            id,
          ),
        );
        if (saved == null) continue;
        invoice = saved;
      }
      if (isJobInvoicePaymentEligible(invoice)) invoices.add(invoice);
    }
    if (!context.mounted || !stillCurrent()) return false;
    if (invoices.isEmpty) {
      notice(
        offline
            ? 'No eligible invoice is saved offline. Connect and open an unpaid invoice first.'
            : 'No unpaid or pending invoice is available for this Job.',
      );
      return false;
    }
    final selected = await chooseJobInvoice(
      context,
      invoices: invoices,
      title: 'Choose invoice for payment',
      showBalance: true,
    );
    if (selected == null || !context.mounted || !stillCurrent()) return false;
    final id = selected['id'].toString();
    if (!offline) {
      // Recheck permissions, linkage, balance, and locks after the chooser.
      final current = await api.documentDetail(businessId, id);
      if (current['job_id']?.toString() != jobId ||
          !isJobInvoicePaymentEligible(current)) {
        notice(
          'This invoice is no longer available for payment. Refresh the Job.',
        );
        return false;
      }
    }
    if (await LocalJobQuarantine.isJobBlocked(
      localDatabase,
      businessId,
      jobId,
    )) {
      notice('Job access has changed. Refresh before adding a payment.');
      return false;
    }
    if (!context.mounted || !stillCurrent()) return false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: businessId,
          documentId: id,
          roleCode: roleCode,
          isOwner: roleCode == 'owner',
          canManageExpenses: true,
          initialTab: 'payment',
        ),
      ),
    );
    return true;
  } catch (_) {
    // Do not turn an online permission failure into a cached authorization.
    notice(
      offline
          ? 'The saved invoice could not be opened. Connect and refresh the Job.'
          : 'Could not verify invoice access. Check your connection and refresh the Job.',
    );
    return false;
  }
}
