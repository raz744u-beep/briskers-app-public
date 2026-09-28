import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class ExpenseSettingsScreen extends StatefulWidget {
  const ExpenseSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<ExpenseSettingsScreen> createState() => _ExpenseSettingsScreenState();
}

class _ExpenseSettingsScreenState extends State<ExpenseSettingsScreen> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>>? _accounts;
  List<Map<String, dynamic>>? _categories;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.expenseSettings(widget.businessId);
      final accounts = List<dynamic>.from(data['accounts'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final categories = List<dynamic>.from(data['categories'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _categories = categories;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _accounts = const [];
        _categories = const [];
        _error = error.toString();
      });
    }
  }

  Future<void> _editAccount([Map<String, dynamic>? account]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountDialog(
        businessId: widget.businessId,
        account: account,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editCategory([Map<String, dynamic>? category]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(
        businessId: widget.businessId,
        category: category,
      ),
    );
    if (changed == true) await _load();
  }

  String _accountKindLabel(String? value) {
    switch (value) {
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

  String _categoryTypeLabel(String? value) {
    switch (value) {
      case 'direct_cost':
        return 'Job / direct cost';
      case 'overhead':
        return 'Overhead';
      default:
        return 'Review / uncategorized';
    }
  }

  IconData _accountIcon(String? value) {
    switch (value) {
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

  @override
  Widget build(BuildContext context) {
    final loading = _accounts == null || _categories == null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.expenses.withValues(alpha: 0.10),
        title: const Text('Expense setup'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 2, 4, 12),
                    child: Text(
                      'Manage the accounts and categories available when recording expenses. Inactive items stay on old records but no longer appear when adding a new expense.',
                    ),
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _SectionHeader(
                    title: 'Accounts',
                    subtitle: 'Bank, credit card, cash or other payment sources',
                    onAdd: () => _editAccount(),
                  ),
                  if (_accounts!.isEmpty)
                    const _EmptyCard(text: 'No expense accounts yet.')
                  else
                    ..._accounts!.map((account) {
                      final active = account['active'] != false;
                      final kind = account['kind']?.toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: active
                                ? BriskersColors.expenses
                                    .withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.12),
                            child: Icon(
                              _accountIcon(kind),
                              color: active
                                  ? BriskersColors.expenses
                                  : Colors.grey,
                            ),
                          ),
                          title: Text(
                            account['name']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: active ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Text(
                            <String>[
                              _accountKindLabel(kind),
                              if (!active) 'Inactive',
                            ].join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _editAccount(account),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  _SectionHeader(
                    title: 'Expense categories',
                    subtitle: 'Controls how each expense is reported',
                    onAdd: () => _editCategory(),
                  ),
                  if (_categories!.isEmpty)
                    const _EmptyCard(text: 'No expense categories yet.')
                  else
                    ..._categories!.map((category) {
                      final active = category['active'] != false;
                      final treatment =
                          category['report_treatment']?.toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: active
                                ? BriskersColors.expenses
                                    .withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.12),
                            child: Icon(
                              treatment == 'direct_cost'
                                  ? Icons.build_outlined
                                  : treatment == 'overhead'
                                      ? Icons.store_outlined
                                      : Icons.help_outline,
                              color: active
                                  ? BriskersColors.expenses
                                  : Colors.grey,
                            ),
                          ),
                          title: Text(
                            category['name']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: active ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Text(
                            <String>[
                              _categoryTypeLabel(treatment),
                              if (!active) 'Inactive',
                            ].join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _editCategory(category),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(text),
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

  late final TextEditingController _name;
  late String _kind;
  late bool _active;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.account?['name']?.toString() ?? '',
    );
    _kind = widget.account?['kind']?.toString() ?? 'bank';
    _active = widget.account?['active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Account name is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.saveFinancialAccount(
        widget.businessId,
        accountId: widget.account?['id']?.toString(),
        name: name,
        accountKind: _kind,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
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
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Account name'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _kind,
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
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _kind = value);
                    },
            ),
            if (widget.account != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive accounts stay on old expenses.',
                ),
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          backgroundColor: BriskersColors.expenses,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
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

  late final TextEditingController _name;
  late String _treatment;
  late bool _active;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.category?['name']?.toString() ?? '',
    );
    _treatment =
        widget.category?['report_treatment']?.toString() ?? 'direct_cost';
    _active = widget.category?['active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Category name is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.saveExpenseCategory(
        widget.businessId,
        categoryId: widget.category?['id']?.toString(),
        name: name,
        reportTreatment: _treatment,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.category == null ? 'Add category' : 'Edit category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Category name'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _treatment,
              decoration: const InputDecoration(labelText: 'Category type'),
              items: const [
                DropdownMenuItem(
                  value: 'direct_cost',
                  child: Text('Job / direct cost'),
                ),
                DropdownMenuItem(
                  value: 'overhead',
                  child: Text('Overhead'),
                ),
                DropdownMenuItem(
                  value: 'review',
                  child: Text('Review / uncategorized'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _treatment = value);
                      }
                    },
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _treatment == 'direct_cost'
                    ? 'Use for expenses tied directly to a job, such as parts, towing or sublet work.'
                    : _treatment == 'overhead'
                        ? 'Use for general business costs that are not assigned to one job.'
                        : 'Use when the expense needs to be reviewed or categorized later.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (widget.category != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive categories stay on old expenses.',
                ),
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          backgroundColor: BriskersColors.expenses,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
