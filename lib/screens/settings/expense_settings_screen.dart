import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class ExpenseSettingsScreen extends StatelessWidget {
  const ExpenseSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  void _push(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.expenses.withValues(alpha: 0.10),
        title: const Text('Transactions setup'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Manage the lists and shortcuts used by Expenses & income.',
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              color: BriskersColors.expenses,
            ),
            title: const Text('Accounts'),
            subtitle: const Text(
              'Bank, credit card, cash and other accounts',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(
              context,
              AccountsSettingsScreen(businessId: businessId),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.category_outlined,
              color: BriskersColors.expenses,
            ),
            title: const Text('Categories'),
            subtitle: const Text(
              'Expense and income categories such as Shipping, Towing and Customers',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(
              context,
              CategoriesSettingsScreen(businessId: businessId),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.store_outlined,
              color: BriskersColors.expenses,
            ),
            title: const Text('Payees & payers'),
            subtitle: const Text(
              'Worldpac, FedEx, dealerships, utilities and others',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(
              context,
              CounterpartiesSettingsScreen(businessId: businessId),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.bolt_outlined,
              color: BriskersColors.expenses,
            ),
            title: const Text('Quick transactions'),
            subtitle: const Text(
              'Preset payee, account and category combinations',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(
              context,
              QuickTransactionsSettingsScreen(businessId: businessId),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.event_repeat_outlined,
              color: BriskersColors.expenses,
            ),
            title: const Text('Recurring transactions'),
            subtitle: const Text(
              'Only transactions currently set to repeat',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(
              context,
              RecurringTransactionsScreen(businessId: businessId),
            ),
          ),
        ],
      ),
    );
  }
}

abstract class _SettingsState<T extends StatefulWidget> extends State<T> {
  final BriskersApi api = const BriskersApi();

  String? error;

  Future<Map<String, dynamic>> loadSettings(String businessId) {
    return api.transactionSettings(businessId);
  }

  int usage(Map<String, dynamic> row) =>
      int.tryParse(row['usage_count']?.toString() ?? '') ?? 0;

  Future<void> showError(Object e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Could not save'),
        content: Text(e.toString()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class AccountsSettingsScreen extends StatefulWidget {
  const AccountsSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<AccountsSettingsScreen> createState() => _AccountsSettingsScreenState();
}

class _AccountsSettingsScreenState
    extends _SettingsState<AccountsSettingsScreen> {
  List<Map<String, dynamic>>? rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await loadSettings(widget.businessId);
      final result = List<dynamic>.from(data['accounts'] ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        rows = result;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        rows = const [];
        error = e.toString();
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountDialog(
        businessId: widget.businessId,
        account: row,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteAccount(Map<String, dynamic> row) async {
    if (usage(row) > 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          'Delete "${row['name']?.toString() ?? ''}"? '
          'This is only allowed for accounts with no transaction history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await api.deleteFinancialAccount(
        widget.businessId,
        row['id'].toString(),
      );
      await _load();
    } catch (e) {
      await showError(e);
    }
  }

  IconData _icon(String? kind) {
    switch (kind) {
      case 'bank':
        return Icons.account_balance_outlined;
      case 'credit_card':
        return Icons.credit_card_outlined;
      case 'cash':
        return Icons.payments_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _kind(String? kind) {
    switch (kind) {
      case 'bank':
        return 'Bank account';
      case 'credit_card':
        return 'Credit card';
      case 'cash':
        return 'Cash';
      default:
        return 'Other';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Account'),
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      'Accounts that have been used are kept for history. Choose one active account as the default for new expenses. Turn accounts inactive to remove them from new transactions.',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ...rows!.map((row) {
                    final active = row['active'] != false;
                    final isDefaultExpense =
                        row['is_default_expense'] == true;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? BriskersColors.expenses.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.12),
                          child: Icon(
                            _icon(row['kind']?.toString()),
                            color: active
                                ? BriskersColors.expenses
                                : Colors.grey,
                          ),
                        ),
                        title: Text(
                          row['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: active ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          <String>[
                            _kind(row['kind']?.toString()),
                            if (isDefaultExpense) 'Default for expenses',
                            '${usage(row)} transaction(s)',
                            if (!active) 'Inactive',
                          ].join(' • '),
                        ),
                        trailing: usage(row) == 0
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(row);
                                  if (value == 'delete') _deleteAccount(row);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => _edit(row),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.businessId,
    this.account,
  });

  final String businessId;
  final Map<String, dynamic>? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  static const _api = BriskersApi();

  late final TextEditingController name;
  late String kind;
  late bool active;
  late bool isDefaultExpense;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.account?['name']?.toString() ?? '',
    );
    kind = widget.account?['kind']?.toString() ?? 'bank';
    active = widget.account?['active'] != false;
    isDefaultExpense = widget.account?['is_default_expense'] == true;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Account name is required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await _api.saveFinancialAccount(
        widget.businessId,
        accountId: widget.account?['id']?.toString(),
        name: name.text.trim(),
        accountKind: kind,
        active: active,
        isDefaultExpense: isDefaultExpense,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.account == null ? 'Add account' : 'Edit account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              enabled: !saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Account name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Account type'),
              items: const [
                DropdownMenuItem(value: 'bank', child: Text('Bank account')),
                DropdownMenuItem(
                  value: 'credit_card',
                  child: Text('Credit card'),
                ),
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => kind = value);
                    },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Default for expenses'),
              subtitle: const Text(
                'New general and recurring expenses will use this account automatically.',
              ),
              value: isDefaultExpense,
              onChanged: saving || !active
                  ? null
                  : (value) => setState(() => isDefaultExpense = value),
            ),
            if (widget.account != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive accounts stay on historical transactions.',
                ),
                value: active,
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                          active = value;
                          if (!value) isDefaultExpense = false;
                        }),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class CategoriesSettingsScreen extends StatefulWidget {
  const CategoriesSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<CategoriesSettingsScreen> createState() =>
      _CategoriesSettingsScreenState();
}

class _CategoriesSettingsScreenState
    extends _SettingsState<CategoriesSettingsScreen> {
  List<Map<String, dynamic>>? rows;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await loadSettings(widget.businessId);
      final result = List<dynamic>.from(data['categories'] ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        rows = result;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        rows = const [];
        error = e.toString();
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(
        businessId: widget.businessId,
        category: row,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete "${row['name']}"? Only categories that have never been used can be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.deleteTransactionCategory(
        widget.businessId,
        row['id'].toString(),
      );
      await _load();
    } catch (e) {
      await showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = (rows ?? const <Map<String, dynamic>>[])
        .where(
          (row) =>
              filter == 'all' ||
              row['normal_direction']?.toString() == filter,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'expense', label: Text('Expenses')),
                      ButtonSegment(value: 'income', label: Text('Income')),
                    ],
                    selected: {filter},
                    onSelectionChanged: (value) =>
                        setState(() => filter = value.first),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The category type is the normal side of the category. You can still use an expense category for an income refund or credit.',
                  ),
                  const SizedBox(height: 10),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ...visible.map((row) {
                    final active = row['active'] != false;
                    final count = usage(row);
                    final direction =
                        row['normal_direction']?.toString() ?? 'expense';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? BriskersColors.expenses.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.12),
                          child: Icon(
                            direction == 'income'
                                ? Icons.south_west
                                : Icons.north_east,
                            color: active
                                ? BriskersColors.expenses
                                : Colors.grey,
                          ),
                        ),
                        title: Text(
                          row['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: active ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          <String>[
                            direction == 'income' ? 'Income' : 'Expense',
                            '$count transaction(s)',
                            if (!active) 'Inactive',
                          ].join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _edit(row);
                            if (value == 'delete') _delete(row);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            if (count == 0)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                          ],
                        ),
                        onTap: () => _edit(row),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.businessId,
    this.category,
  });

  final String businessId;
  final Map<String, dynamic>? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  static const _api = BriskersApi();

  late final TextEditingController name;
  late String direction;
  late bool active;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.category?['name']?.toString() ?? '',
    );
    direction =
        widget.category?['normal_direction']?.toString() == 'income'
            ? 'income'
            : 'expense';
    active = widget.category?['active'] != false;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Category name is required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await _api.saveTransactionCategory(
        widget.businessId,
        categoryId: widget.category?['id']?.toString(),
        name: name.text.trim(),
        normalDirection: direction,
        active: active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'Add category' : 'Edit category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              enabled: !saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Category name'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {direction},
              onSelectionChanged: saving
                  ? null
                  : (value) => setState(() => direction = value.first),
            ),
            if (widget.category != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged:
                    saving ? null : (value) => setState(() => active = value),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class CounterpartiesSettingsScreen extends StatefulWidget {
  const CounterpartiesSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<CounterpartiesSettingsScreen> createState() =>
      _CounterpartiesSettingsScreenState();
}

class _CounterpartiesSettingsScreenState
    extends _SettingsState<CounterpartiesSettingsScreen> {
  List<Map<String, dynamic>>? rows;
  List<Map<String, dynamic>> categories = const [];
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await loadSettings(widget.businessId);
      final result = List<dynamic>.from(data['counterparties'] ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final loadedCategories =
          List<dynamic>.from(data['categories'] ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where(
                (e) =>
                    e['normal_direction']?.toString() == 'expense' &&
                    e['active'] != false,
              )
              .toList();
      if (!mounted) return;
      setState(() {
        rows = result;
        categories = loadedCategories;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        rows = const [];
        error = e.toString();
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CounterpartyDialog(
        businessId: widget.businessId,
        row: row,
        categories: categories,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete payee/payer?'),
        content: Text(
          'Delete "${row['name']}"? A payee or payer that has ever been used cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.deleteCounterparty(widget.businessId, row['id'].toString());
      await _load();
    } catch (e) {
      await showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = (rows ?? const <Map<String, dynamic>>[])
        .where(
          (row) => (row['name']?.toString().toLowerCase() ?? '')
              .contains(query.trim().toLowerCase()),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Payees & payers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Payee / payer'),
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search payees and payers',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Used names stay in history. Make them inactive instead of removing them.',
                  ),
                  const SizedBox(height: 10),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ...visible.map((row) {
                    final active = row['active'] != false;
                    final count = usage(row);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? BriskersColors.expenses.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.store_outlined,
                            color: active
                                ? BriskersColors.expenses
                                : Colors.grey,
                          ),
                        ),
                        title: Text(
                          row['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: active ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          <String>[
                            if ((row['default_category']?.toString() ?? '')
                                .isNotEmpty)
                              'Default: ${row['default_category']}',
                            '$count transaction(s)',
                            if (!active) 'Inactive',
                          ].join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _edit(row);
                            if (value == 'delete') _delete(row);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            if (count == 0)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                          ],
                        ),
                        onTap: () => _edit(row),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _CounterpartyDialog extends StatefulWidget {
  const _CounterpartyDialog({
    required this.businessId,
    required this.categories,
    this.row,
  });

  final String businessId;
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic>? row;

  @override
  State<_CounterpartyDialog> createState() => _CounterpartyDialogState();
}

class _CounterpartyDialogState extends State<_CounterpartyDialog> {
  static const _api = BriskersApi();

  late final TextEditingController name;
  late bool active;
  String? defaultCategoryId;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.row?['name']?.toString() ?? '');
    active = widget.row?['active'] != false;
    defaultCategoryId = widget.row?['default_category_id']?.toString();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Name is required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await _api.saveCounterparty(
        widget.businessId,
        counterpartyId: widget.row?['id']?.toString(),
        name: name.text.trim(),
        active: active,
        defaultCategoryId: defaultCategoryId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.row == null ? 'Add payee / payer' : 'Edit payee / payer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            enabled: !saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: defaultCategoryId,
            decoration: const InputDecoration(
              labelText: 'Default expense category',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No default category'),
              ),
              ...widget.categories.map(
                (category) => DropdownMenuItem<String?>(
                  value: category['id']?.toString(),
                  child: Text(category['name']?.toString() ?? ''),
                ),
              ),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() => defaultCategoryId = value),
          ),
          if (widget.row != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: active,
              onChanged:
                  saving ? null : (value) => setState(() => active = value),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class QuickTransactionsSettingsScreen extends StatefulWidget {
  const QuickTransactionsSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<QuickTransactionsSettingsScreen> createState() =>
      _QuickTransactionsSettingsScreenState();
}

class _QuickTransactionsSettingsScreenState
    extends _SettingsState<QuickTransactionsSettingsScreen> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await loadSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        data = result;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        data = <String, dynamic>{};
        error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      List<dynamic>.from(data?[key] ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickDialog(
        businessId: widget.businessId,
        template: row,
        accounts: _list('accounts'),
        categories: _list('categories'),
        counterparties: _list('counterparties'),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    await api.deleteQuickTransaction(
      widget.businessId,
      row['id'].toString(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final templates = _list('quick_templates');

    return Scaffold(
      appBar: AppBar(title: const Text('Quick transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: data == null ? null : () => _edit(),
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Quick transaction'),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              children: [
                const Text(
                  'A quick transaction fills in the type, payee/payer, account and category. You only add the amount, receipt and anything that changed.',
                ),
                const SizedBox(height: 10),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (templates.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No quick transactions yet.'),
                    ),
                  )
                else
                  ...templates.map((row) {
                    final active = row['active'] != false;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              BriskersColors.expenses.withValues(alpha: 0.12),
                          child: Icon(
                            row['direction']?.toString() == 'income'
                                ? Icons.south_west
                                : Icons.bolt_outlined,
                            color: BriskersColors.expenses,
                          ),
                        ),
                        title: Text(
                          row['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: active ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          <String>[
                            row['direction']?.toString() == 'income'
                                ? 'Income'
                                : 'Expense',
                            if ((row['vendor']?.toString() ?? '').isNotEmpty)
                              row['vendor'].toString(),
                            row['category']?.toString() ?? '',
                            row['account']?.toString() ?? '',
                            if (!active) 'Inactive',
                          ].where((x) => x.isNotEmpty).join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _edit(row);
                            if (value == 'delete') _delete(row);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                        onTap: () => _edit(row),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _QuickDialog extends StatefulWidget {
  const _QuickDialog({
    required this.businessId,
    required this.accounts,
    required this.categories,
    required this.counterparties,
    this.template,
  });

  final String businessId;
  final Map<String, dynamic>? template;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> counterparties;

  @override
  State<_QuickDialog> createState() => _QuickDialogState();
}

class _QuickDialogState extends State<_QuickDialog> {
  static const _api = BriskersApi();

  late final TextEditingController name;
  late final TextEditingController remarks;
  late final TextEditingController sortOrder;
  late String direction;
  String? accountId;
  String? categoryId;
  String? vendorId;
  late bool active;
  bool saving = false;
  String? error;

  List<Map<String, dynamic>> get activeAccounts =>
      widget.accounts.where((x) => x['active'] != false).toList();
  List<Map<String, dynamic>> get activeCategories =>
      widget.categories.where((x) => x['active'] != false).toList();
  List<Map<String, dynamic>> get activeCounterparties =>
      widget.counterparties.where((x) => x['active'] != false).toList();

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.template?['name']?.toString() ?? '');
    remarks = TextEditingController(
      text: widget.template?['remarks']?.toString() ?? '',
    );
    sortOrder = TextEditingController(
      text: widget.template?['sort_order']?.toString() ?? '0',
    );
    direction = widget.template?['direction']?.toString() == 'income'
        ? 'income'
        : 'expense';
    accountId = widget.template?['account_id']?.toString();
    categoryId = widget.template?['category_id']?.toString() ??
        (activeCategories.isEmpty
            ? null
            : activeCategories.first['id']?.toString());
    vendorId = widget.template?['vendor_id']?.toString();
    active = widget.template?['active'] != false;
  }

  @override
  void dispose() {
    name.dispose();
    remarks.dispose();
    sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty || accountId == null || categoryId == null) {
      setState(() => error = 'Name, account and category are required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await _api.saveQuickTransaction(
        widget.businessId,
        templateId: widget.template?['id']?.toString(),
        name: name.text.trim(),
        direction: direction,
        vendorId: vendorId,
        accountId: accountId!,
        categoryId: categoryId!,
        remarks: remarks.text.trim().isEmpty ? null : remarks.text.trim(),
        sortOrder: int.tryParse(sortOrder.text.trim()) ?? 0,
        active: active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.template == null ? 'Add quick transaction' : 'Edit quick transaction',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Shortcut name'),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {direction},
              onSelectionChanged: saving
                  ? null
                  : (value) => setState(() => direction = value.first),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: vendorId,
              decoration: const InputDecoration(labelText: 'Payee / payer'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                ...activeCounterparties.map(
                  (x) => DropdownMenuItem<String?>(
                    value: x['id']?.toString(),
                    child: Text(x['name']?.toString() ?? ''),
                  ),
                ),
              ],
              onChanged:
                  saving ? null : (value) => setState(() => vendorId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: activeCategories
                  .map(
                    (x) => DropdownMenuItem(
                      value: x['id']?.toString(),
                      child: Text(x['name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged:
                  saving ? null : (value) => setState(() => categoryId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              hint: const Text('Choose account'),
              decoration: const InputDecoration(labelText: 'Account'),
              items: activeAccounts
                  .map(
                    (x) => DropdownMenuItem(
                      value: x['id']?.toString(),
                      child: Text(x['name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged:
                  saving ? null : (value) => setState(() => accountId = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarks,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Default notes'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sortOrder,
              enabled: !saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Sort order'),
            ),
            if (widget.template != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged:
                    saving ? null : (value) => setState(() => active = value),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class RecurringTransactionsScreen extends StatefulWidget {
  const RecurringTransactionsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<RecurringTransactionsScreen> createState() =>
      _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState
    extends State<RecurringTransactionsScreen> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>>? rows;
  Map<String, dynamic>? options;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.recurringTransactions(widget.businessId),
        _api.transactionOptions(widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(results[0] as List);
        options = Map<String, dynamic>.from(results[1] as Map);
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        rows = const [];
        options = <String, dynamic>{};
        error = e.toString();
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurringDialog(
        businessId: widget.businessId,
        row: row,
        options: options ?? const {},
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _stop(Map<String, dynamic> row) async {
    await _api.stopRecurringTransaction(
      widget.businessId,
      row['id'].toString(),
    );
    await _load();
  }

  String _frequency(Map<String, dynamic> row) {
    final f = row['frequency']?.toString() ?? '';
    final n = int.tryParse(row['interval_count']?.toString() ?? '') ?? 1;
    if (f == 'weekly' && n == 2) return 'Every 2 weeks';
    if (f == 'daily') return 'Daily';
    if (f == 'weekly') return 'Weekly';
    if (f == 'yearly') return 'Yearly';
    return 'Monthly';
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: options == null ? null : () => _edit(),
        backgroundColor: BriskersColors.expenses,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Recurring'),
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  const Text(
                    'This is only a filtered management list. Turning repeating off does not move or delete any transaction already created.',
                  ),
                  const SizedBox(height: 10),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (rows!.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('No transactions are currently repeating.'),
                      ),
                    )
                  else
                    ...rows!.map((row) {
                      final paused = row['paused_reason']?.toString() ?? '';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                BriskersColors.expenses.withValues(alpha: 0.12),
                            child: const Icon(
                              Icons.event_repeat_outlined,
                              color: BriskersColors.expenses,
                            ),
                          ),
                          title: Text(
                            row['counterparty']?.toString().isNotEmpty == true
                                ? row['counterparty'].toString()
                                : row['category']?.toString() ?? 'Recurring',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            <String>[
                              row['category']?.toString() ?? '',
                              _frequency(row),
                              'Next ${row['next_date']}',
                              if (paused.isNotEmpty) 'Paused: $paused',
                            ].where((x) => x.isNotEmpty).join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _money(row['amount']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(row);
                                  if (value == 'stop') _stop(row);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'stop',
                                    child: Text('Stop repeating'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _edit(row),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _RecurringDialog extends StatefulWidget {
  const _RecurringDialog({
    required this.businessId,
    required this.options,
    this.row,
  });

  final String businessId;
  final Map<String, dynamic> options;
  final Map<String, dynamic>? row;

  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  static const _api = BriskersApi();

  late final TextEditingController amount;
  late final TextEditingController remarks;
  late String direction;
  String? vendorId;
  String? accountId;
  String? categoryId;
  String preset = 'monthly';
  DateTime nextDate = DateTime.now().add(const Duration(days: 30));
  DateTime? endDate;
  bool saving = false;
  String? error;

  List<Map<String, dynamic>> _list(String key) =>
      List<dynamic>.from(widget.options[key] ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  @override
  void initState() {
    super.initState();
    amount = TextEditingController(text: widget.row?['amount']?.toString() ?? '');
    remarks = TextEditingController(text: widget.row?['remarks']?.toString() ?? '');
    direction = widget.row?['direction']?.toString() == 'income'
        ? 'income'
        : 'expense';
    vendorId = widget.row?['vendor_id']?.toString();
    if (widget.row != null) {
      accountId = widget.row?['account_id']?.toString();
      categoryId = widget.row?['category_id']?.toString();
    } else {
      accountId = null;
      for (final account in _list('accounts')) {
        if (account['is_default_expense'] == true) {
          accountId = account['id']?.toString();
          break;
        }
      }
      categoryId = null;
    }
    if (widget.row != null) {
      nextDate =
          DateTime.tryParse(widget.row!['next_date']?.toString() ?? '') ??
              nextDate;
      final rawEnd = widget.row!['end_date']?.toString() ?? '';
      endDate = rawEnd.isEmpty ? null : DateTime.tryParse(rawEnd);
      final f = widget.row!['frequency']?.toString() ?? 'monthly';
      final n = int.tryParse(widget.row!['interval_count']?.toString() ?? '') ?? 1;
      preset = f == 'weekly' && n == 2 ? 'biweekly' : f;
    }
  }

  @override
  void dispose() {
    amount.dispose();
    remarks.dispose();
    super.dispose();
  }

  (String, int) get repeatParts {
    switch (preset) {
      case 'daily':
        return ('daily', 1);
      case 'weekly':
        return ('weekly', 1);
      case 'biweekly':
        return ('weekly', 2);
      case 'yearly':
        return ('yearly', 1);
      default:
        return ('monthly', 1);
    }
  }

  Future<void> _pickNext() async {
    final value = await showDatePicker(
      context: context,
      initialDate: nextDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) setState(() => nextDate = value);
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      initialDate: endDate ?? nextDate.add(const Duration(days: 365)),
      firstDate: nextDate,
      lastDate: DateTime.now().add(const Duration(days: 7300)),
    );
    if (value != null && mounted) setState(() => endDate = value);
  }

  Future<void> _save() async {
    final value = num.tryParse(amount.text.trim());
    if (value == null || value <= 0 || accountId == null || categoryId == null) {
      setState(() => error = 'Amount, account and category are required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final parts = repeatParts;
      await _api.saveRecurringTransaction(
        widget.businessId,
        ruleId: widget.row?['id']?.toString(),
        sourceTransactionId: widget.row?['source_transaction_id']?.toString(),
        direction: direction,
        vendorId: vendorId,
        accountId: accountId!,
        categoryId: categoryId!,
        amount: num.parse(value.toStringAsFixed(2)),
        remarks: remarks.text.trim().isEmpty ? null : remarks.text.trim(),
        frequency: parts.$1,
        intervalCount: parts.$2,
        nextDate: nextDate,
        endDate: endDate,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counterparties = _list('counterparties');
    final accounts = _list('accounts');
    final categories = _list('categories');

    return AlertDialog(
      title: Text(widget.row == null ? 'Add recurring transaction' : 'Edit recurring transaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {direction},
              onSelectionChanged: saving
                  ? null
                  : (value) => setState(() {
                        direction = value.first;
                        categoryId = null;
                      }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              enabled: !saving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: vendorId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Payee / payer'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                ...counterparties.map(
                  (x) => DropdownMenuItem<String?>(
                    value: x['id']?.toString(),
                    child: Text(
                      x['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged:
                  saving ? null : (value) => setState(() => vendorId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'Select a category',
              ),
              items: categories
                  .map(
                    (x) => DropdownMenuItem(
                      value: x['id']?.toString(),
                      child: Text(
                        x['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged:
                  saving ? null : (value) => setState(() => categoryId = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Account',
                hintText: 'Select an account',
              ),
              items: accounts
                  .map(
                    (x) => DropdownMenuItem(
                      value: x['id']?.toString(),
                      child: Text(
                        x['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged:
                  saving ? null : (value) => setState(() => accountId = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarks,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Description / notes'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: preset,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(
                  value: 'biweekly',
                  child: Text('Every 2 weeks'),
                ),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => preset = value);
                    },
            ),
            const SizedBox(height: 10),
            Material(
              color: BriskersColors.appointments.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: saving ? null : _pickNext,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: BriskersColors.appointments,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Start / next transaction',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${nextDate.month}/${nextDate.day}/${nextDate.year}',
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: BriskersColors.appointments.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: saving ? null : _pickEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_busy_outlined,
                        color: BriskersColors.appointments,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'End date',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              endDate == null
                                  ? 'No end date'
                                  : '${endDate!.month}/${endDate!.day}/${endDate!.year}',
                            ),
                          ],
                        ),
                      ),
                      if (endDate != null)
                        IconButton(
                          tooltip: 'No end date',
                          onPressed: saving
                              ? null
                              : () => setState(() => endDate = null),
                          icon: const Icon(Icons.close),
                        )
                      else
                        const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
