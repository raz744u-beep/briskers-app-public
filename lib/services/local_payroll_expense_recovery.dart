import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'local_financial_cache.dart';
import 'local_owner_authorization.dart';
import 'local_payroll_expense_review.dart';
import 'offline_financial_write_service.dart';
import 'payroll_expense_identity.dart';
import 'payroll_expense_link_store.dart';

typedef PayrollPayout = ({
  String reference,
  String employee,
  String date,
  String method,
  int cents,
});

class PayrollExpensePreview {
  PayrollExpensePreview._(
    this.business,
    this.week,
    this.account,
    this.accountId,
    this.categoryId,
    Iterable<PayrollPayout> payouts,
  ) : payouts = List.unmodifiable(payouts);

  final String business, week;
  final String? account, accountId, categoryId;
  final List<PayrollPayout> payouts;

  int get totalCents =>
      payouts.fold(0, (total, payout) => total + payout.cents);
}

/// Projects only immutable, still-active payouts the Owner previewed on this
/// device. The expense, posting queue, totals delta, and durable link commit
/// together. This service has no network replay or payroll write entry point.
class LocalPayrollExpenseRecovery {
  LocalPayrollExpenseRecovery(
    this.database, {
    OfflineFinancialWriteService? writer,
  }) : _cache = LocalFinancialCache(database: database),
       _writer = writer ?? OfflineFinancialWriteService(database: database);

  final BriskersLocalDatabase database;
  final LocalFinancialCache _cache;
  final OfflineFinancialWriteService _writer;
  static const _missing = 'Verified payment with no linked expense';

  Future<PayrollExpensePreview> preview(
    String business,
    String week,
  ) => database.transaction(() async {
    final rows = await LocalPayrollExpenseReview(
      database,
    ).forWeek(business, week);
    final options = await _cache.loadOptions(business);
    List<Map<String, dynamic>> choices(String key) =>
        (options[key] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
    final accounts = choices('accounts');
    final accountId = PayrollExpenseIdentity.uniqueOptionId(
      accounts,
      'Business Checking - 9858',
    );
    final categoryId = PayrollExpenseIdentity.uniqueOptionId(
      choices('categories'),
      'Payroll',
    );
    final account = accounts
        .where((value) => value['id'] == accountId)
        .firstOrNull;
    final candidates = rows
        .where(
          (row) =>
              row['status'] == _missing &&
              (row['possible_expenses'] as List).isEmpty,
        )
        .toList();
    final inventory = candidates.isEmpty
        ? <Map<String, dynamic>>[]
        : await _cache.payrollRecoveryInventory(business);
    final pendingCreates = candidates.isEmpty
        ? <String>{}
        : (await database
                  .customSelect(
                    "SELECT entity_id, json_extract(payload_json,'\$.operation_id') AS operation "
                    "FROM sync_outbox WHERE business_id=? AND entity_type='financial_create'",
                    variables: [Variable(business)],
                  )
                  .get())
              .expand(
                (row) => [
                  row.read<String>('entity_id'),
                  row.readNullable<String>('operation'),
                ],
              )
              .nonNulls
              .toSet();

    final eligible = <PayrollPayout>[];
    for (final row in candidates) {
      final payout = (
        reference: row['payroll_reference'] as String,
        employee: row['employee'] as String,
        date: row['payment_date'] as String,
        method: row['payment_method'] as String,
        cents: row['net_cents'] as int,
      );
      final id = PayrollExpenseIdentity.transactionId(
        business,
        payout.reference,
      );
      if (row['has_saved_employee'] != true ||
          payout.employee.trim().isEmpty ||
          payout.method.trim().isEmpty ||
          payout.cents <= 0 ||
          pendingCreates.contains(id) ||
          pendingCreates.contains(
            PayrollExpenseIdentity.expenseCreateOperation(
              business,
              payout.reference,
            ),
          ) ||
          inventory.any(
            (expense) => _couldAlreadyBeExpense(expense, payout, id),
          )) {
        continue;
      }
      eligible.add(payout);
    }
    return PayrollExpensePreview._(
      business,
      week,
      (account?['name'] ?? account?['label'])?.toString(),
      accountId,
      categoryId,
      eligible,
    );
  });

  static bool _couldAlreadyBeExpense(
    Map<String, dynamic> row,
    PayrollPayout payout,
    String id,
  ) {
    if (row['id'] == id || row['payroll_operation_id'] == payout.reference) {
      return true;
    }
    if (row['direction'] == 'income' || row['payroll_operation_id'] != null) {
      return false;
    }
    final amount = num.tryParse(
      (row['amount'] ?? row['signed_amount'])?.toString() ?? '',
    );
    if (amount == null ||
        !(amount * 100).isFinite ||
        (amount.abs() * 100).round() != payout.cents) {
      return false;
    }
    final date = DateTime.tryParse(
      (row['transaction_date'] ?? row['date'])?.toString() ?? '',
    );
    if (date?.toIso8601String().split('T').first != payout.date) return false;
    final name =
        (row['counterparty'] ?? row['payee_text'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final employee = payout.employee.trim().toLowerCase();
    return name == employee ||
        employee.startsWith('$name ') ||
        employee.endsWith(' $name') ||
        name.isEmpty && LocalFinancialCache.requiresOwnerAccountEdit(row);
  }

  Future<int> reconcile(
    PayrollExpensePreview confirmed,
    LocalOwnerGrant grant,
  ) => database.transaction(() async {
    final business = confirmed.business;
    grant.assertValid(business, grant.actorId);
    final current = await preview(business, confirmed.week);
    final byReference = {
      for (final payout in current.payouts) payout.reference: payout,
    };
    final links = PayrollExpenseLinkStore(database);
    final toCreate = <PayrollPayout>[];
    for (final payout in confirmed.payouts) {
      if (byReference[payout.reference] == payout) {
        toCreate.add(payout);
        continue;
      }
      final linkedId = await links.transactionId(business, payout.reference);
      final existing = linkedId == null
          ? null
          : await _cache.loadTransactionDetail(business, linkedId);
      final amount = num.tryParse(existing?['amount']?.toString() ?? '');
      if (existing?['payroll_operation_id'] != payout.reference ||
          existing?['direction'] != 'expense' ||
          existing?['sync_state'] == 'reversed' ||
          existing?['transaction_date'] != payout.date ||
          amount == null ||
          !(amount * 100).isFinite ||
          (amount * 100).round() != payout.cents ||
          existing?['payment_method'] != payout.method) {
        throw StateError(
          'The saved expenses changed. Reopen the review before reconciling.',
        );
      }
    }
    if (toCreate.isEmpty) return 0;
    if (current.accountId == null ||
        current.account == null ||
        current.categoryId == null ||
        current.accountId != confirmed.accountId ||
        current.categoryId != confirmed.categoryId) {
      throw StateError(
        'Business Checking–9858 and the Payroll category must be saved on this phone.',
      );
    }
    for (final payout in toCreate) {
      grant.assertValid(business, grant.actorId);
      await _writer.createLocalTransaction(
        business,
        direction: 'expense',
        accountId: current.accountId!,
        accountName: current.account!,
        categoryId: current.categoryId!,
        categoryName: 'Payroll',
        amount: payout.cents / 100,
        date: DateTime.parse(payout.date),
        counterpartyName: payout.employee,
        remarks: 'Verified payroll payment · ${payout.method}',
        receipts: const [],
        verifiedPayrollOperationId: payout.reference,
      );
    }
    grant.assertValid(business, grant.actorId);
    return toCreate.length;
  });
}
