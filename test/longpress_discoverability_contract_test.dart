import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs show a long-press hint only when card actions are available', () {
    final jobs = File('lib/widgets/job_compact_card.dart').readAsStringSync();
    expect(jobs, contains('onLongPress: canOpen ? onLongPress : null'));
    expect(jobs, contains('if (canOpen && onLongPress != null)'));
    expect(jobs, contains("tr('longPressForOptions')"));
    expect(jobs, contains('onTap: canOpen ? onOpen : null'));
  });

  test('Estimates and invoices share one discoverable long-press hint', () {
    final documents = File('lib/screens/documents_screen.dart')
        .readAsStringSync();
    expect(documents, contains('onTap: () => _open(row)'));
    expect(documents, contains('onLongPress: () => _showDocumentActions(row)'));
    expect(documents, contains("tr('longPressForOptions')"));
    expect(documents, contains("bool get _estimate => widget.kind == 'estimate'"));
  });

  test('Expenses list advertises actual long press action', () {
    final expenses = File('lib/screens/expenses_screen.dart')
        .readAsStringSync();
    expect(expenses, contains('onTap: () => invoiceReceipt'));
    expect(expenses, contains(': _openTransaction(transaction)'));
    expect(expenses, contains('onLongPress: invoiceReceipt'));
    expect(expenses, contains('_showTransactionActions(transaction)'));
    expect(expenses, contains("tr('longPressForOptions')"));
  });

  test('Appointments list advertises tap, and Customers have no false hint', () {
    final appointments = File('lib/screens/appointments_screen.dart')
        .readAsStringSync();
    expect(appointments, contains('onTap: (_canManage || _canCheckIn)'));
    expect(appointments, contains('onLongPress: (_canManage || _canCheckIn)'));
    expect(appointments, contains("tr('tapForOptions')"));
    expect(appointments, contains('if (_canManage || _canCheckIn) ...['));
    final customers = File('lib/screens/customers/customers_screen.dart')
        .readAsStringSync();
    expect(customers, isNot(contains('onLongPress:')));
    expect(customers, isNot(contains('longPressForOptions')));
  });

  test('Long-press hint is translated in both supported languages', () {
    final translations = File('lib/core/briskers_i18n.dart').readAsStringSync();
    expect(translations, contains("'longPressForOptions': 'Long press for options'"));
    expect(translations, contains("'longPressForOptions': 'Mantén pulsado: opciones'"));
    expect(translations, contains("'tapForOptions': 'Tap for options'"));
    expect(translations, contains("'tapForOptions': 'Toca para ver opciones'"));
  });
}
