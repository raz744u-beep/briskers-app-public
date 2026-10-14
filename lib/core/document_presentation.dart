import 'dart:math';

import 'briskers_i18n.dart';

/// Read-only financial presentation. Never rewrites legacy database statuses.
/// Pending receipts cover customer balance, but remain distinct from posted
/// income and never imply that an invoice was actually closed.
class DocumentPresentation {
  DocumentPresentation(Map<String, dynamic> document)
    : _document = Map.unmodifiable(document);

  final Map<String, dynamic> _document;
  String get kind => _document['kind']?.toString().toLowerCase() ?? 'invoice';
  bool get isInvoice => kind == 'invoice';
  String get rawStatus => _document['status']?.toString().toLowerCase() ?? '';
  bool get isVoid => rawStatus == 'void';
  bool get isClosed =>
      isInvoice &&
      ((_document['closed_at']?.toString().trim().isNotEmpty ?? false) ||
          rawStatus == 'closed');
  bool get requiresReconciliation =>
      _document['_payment_reconciliation_required'] == true;

  int? _cents(Object? value) {
    final number = num.tryParse(value?.toString() ?? '');
    if (number == null ||
        !number.isFinite ||
        !(number * 100).isFinite ||
        number < 0) {
      return null;
    }
    return (number * 100).round();
  }

  int? get totalCents =>
      _cents(_document['total_amount'] ?? _document['total']);
  int? get finalizedCents => _cents(_document['paid_amount']);
  int? get pendingCents => _cents(_document['pending_payment']);
  bool get paymentDetailsKnown =>
      isInvoice &&
      !requiresReconciliation &&
      totalCents != null &&
      finalizedCents != null &&
      pendingCents != null;

  bool get fullyCovered {
    if (!isInvoice || requiresReconciliation || isVoid) return false;
    if (paymentDetailsKnown) {
      return totalCents! > 0 && finalizedCents! + pendingCents! >= totalCents!;
    }
    // The server index has a derived display status even when full payment
    // detail is unavailable offline. Raw historical "draft"/"paid" is not
    // evidence of coverage. Do not invent a numeric balance from this hint.
    final code = _document['display_status_code']?.toString().toLowerCase();
    return code == 'paid' || code == 'pending_close';
  }

  int? get balanceDueCents => !paymentDetailsKnown || isVoid
      ? null
      : max(0, totalCents! - finalizedCents! - pendingCents!);

  String get statusCode {
    if (isVoid) return 'void';
    if (!isInvoice) {
      if (_document['converted'] == true) return 'converted';
      return rawStatus.isEmpty ? 'draft' : rawStatus;
    }
    if (isClosed) return 'closed';
    return fullyCovered ? 'pending_close' : 'open';
  }

  String get statusLabel {
    if (isInvoice) {
      switch (statusCode) {
        case 'void':
          return tr('documentVoid');
        case 'closed':
          return tr('invoiceClosed');
        case 'pending_close':
          return tr('invoicePaidPendingClose');
        default:
          return tr('invoiceOpen');
      }
    }
    switch (statusCode) {
      case 'void':
        return tr('documentVoid');
      case 'converted':
        return tr('documentConverted');
      case 'accepted':
        return tr('documentAccepted');
      case 'declined':
        return tr('documentDeclined');
      case 'expired':
        return tr('documentExpired');
      case 'issued':
        return tr('documentIssued');
      case 'draft':
        return tr('documentDraft');
      default:
        final words = statusCode.replaceAll('_', ' ');
        return words.isEmpty
            ? tr('documentDraft')
            : words[0].toUpperCase() + words.substring(1);
    }
  }
}
