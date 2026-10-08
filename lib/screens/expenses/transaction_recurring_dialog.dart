import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

/// Edit recurrence of an existing, general expense without modifying the
/// posted transaction or its receipt. Stopping affects only future entries.
class TransactionRecurringDialog extends StatefulWidget {
  const TransactionRecurringDialog({
    super.key,
    required this.businessId,
    required this.transactionId,
    required this.transaction,
  });

  final String businessId;
  final String transactionId;
  final Map<String, dynamic> transaction;

  @override
  State<TransactionRecurringDialog> createState() =>
      _TransactionRecurringDialogState();
}

class _TransactionRecurringDialogState
    extends State<TransactionRecurringDialog> {
  static const _api = BriskersApi();

  String _frequency = 'monthly';
  DateTime _nextDate = DateTime.now().add(const Duration(days: 30));
  DateTime? _endDate;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _rule {
    final raw = widget.transaction['recurring_rule'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  bool get _active => _rule?['is_repeating'] == true;

  @override
  void initState() {
    super.initState();
    final rule = _rule;
    if (rule == null) return;
    final frequency = rule['frequency']?.toString() ?? 'monthly';
    final interval = int.tryParse(
      rule['interval_count']?.toString() ?? '',
    ) ?? 1;
    _frequency = frequency == 'weekly' && interval == 2
        ? 'biweekly' : frequency;
    _nextDate = DateTime.tryParse(
      rule['next_date']?.toString() ?? '',
    ) ?? _nextDate;
    _endDate = DateTime.tryParse(rule['end_date']?.toString() ?? '');
  }

  (String, int) get _repeatParts => switch (_frequency) {
        'daily' => ('daily', 1),
        'weekly' => ('weekly', 1),
        'biweekly' => ('weekly', 2),
        'yearly' => ('yearly', 1),
        _ => ('monthly', 1),
      };

  String _displayDate(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';

  Future<void> _pickNext() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _nextDate = picked;
      if (_endDate != null && _endDate!.isBefore(picked)) {
        _endDate = null;
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _nextDate.add(const Duration(days: 365)),
      firstDate: _nextDate,
      lastDate: DateTime.now().add(const Duration(days: 7300)),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final accountId = widget.transaction['account_id']?.toString() ?? '';
    final categoryId = widget.transaction['category_id']?.toString() ?? '';
    final amount = num.tryParse(
      widget.transaction['amount']?.toString() ?? '',
    );
    if (accountId.isEmpty || categoryId.isEmpty ||
        amount == null || amount <= 0) {
      setState(() {
        _error = 'A valid amount, account and category are required '
            'to schedule this transaction.';
      });
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_nextDate)) {
      setState(() => _error = 'End date cannot precede the next date.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final parts = _repeatParts;
      await _api.saveRecurringTransaction(
        widget.businessId,
        ruleId: _rule?['id']?.toString(),
        sourceTransactionId: widget.transactionId,
        direction: widget.transaction['direction']?.toString() == 'income'
            ? 'income' : 'expense',
        vendorId: widget.transaction['counterparty_id']?.toString(),
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        remarks: widget.transaction['remarks']?.toString(),
        frequency: parts.$1,
        intervalCount: parts.$2,
        nextDate: _nextDate,
        endDate: _endDate,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stop() async {
    final ruleId = _rule?['id']?.toString() ?? '';
    if (_saving || ruleId.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.stopRecurringTransaction(widget.businessId, ruleId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_active
          ? 'Manage recurring transaction'
          : _rule == null
              ? 'Make recurring'
              : 'Resume recurring transaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use this expense’s payee, account, category and amount '
              'for future occurrences. The original expense and receipt '
              'remain unchanged.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Repeat',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(
                  value: 'biweekly', child: Text('Every 2 weeks'),
                ),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
              ],
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() => _frequency = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('Next occurrence'),
              subtitle: Text(_displayDate(_nextDate)),
              onTap: _saving ? null : _pickNext,
              trailing: const Icon(Icons.chevron_right),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('End date'),
              subtitle: Text(_endDate == null
                  ? 'No end date' : _displayDate(_endDate!)),
              onTap: _saving ? null : _pickEnd,
              trailing: _endDate == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: 'Remove end date',
                      onPressed: _saving ? null
                          : () => setState(() => _endDate = null),
                      icon: const Icon(Icons.close),
                    ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_active)
          TextButton(
            onPressed: _saving ? null : _stop,
            child: const Text('Stop repeating'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: BriskersColors.expenses,
          ),
          onPressed: _saving ? null : _save,
          child: Text(_saving
              ? 'Saving...'
              : _active ? 'Save schedule' : 'Start repeating'),
        ),
      ],
    );
  }
}
