import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit history download is read only and does not change Force Offline',
      () async {
    final service = await File('lib/services/financial_history_recovery.dart')
        .readAsString();
    final screen = await File('lib/screens/expenses_screen.dart')
        .readAsString();
    expect(service, contains('briskers_list_transactions_recurring_v1'));
    expect(service, contains('client.auth.currentSession'));
    expect(service, contains('p_start_date'));
    expect(service, contains('p_end_date'));
    expect(service, contains('p_offset'));
    expect(service, contains('mergeServerTransactions'));
    expect(service, contains('onPage(ids.length)'));
    expect(service, isNot(contains('networkSupabase')));
    expect(service, isNot(contains('syncCreateManualTransaction')));
    expect(service, isNot(contains('flush(')));
    expect(screen, contains("title: const Text('Download saved history?')"));
    expect(screen, contains('if (!allowed || !mounted) return;'));
    expect(screen, contains('FinancialHistoryRecovery('));
    expect(screen, contains('Force Offline stays enabled'));
  });
}
