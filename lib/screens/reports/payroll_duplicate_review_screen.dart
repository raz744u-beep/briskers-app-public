import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/supabase_config.dart';
import '../../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../../services/device_owner_authorization.dart';
import '../../services/local_employee_reports.dart';
import '../../services/offline_financial_write_service.dart';
import '../payroll/approved_tasks_ui.dart';

class PayrollDuplicateReviewScreen extends StatefulWidget {
  const PayrollDuplicateReviewScreen({
    super.key,
    required this.businessId,
    this.database,
    this.sharedBottomNavigationBar,
  });

  final String businessId;
  final BriskersLocalDatabase? database;
  final Widget? sharedBottomNavigationBar;

  @override
  State<PayrollDuplicateReviewScreen> createState() =>
      _PayrollDuplicateReviewScreenState();
}

class _PayrollDuplicateReviewScreenState
    extends State<PayrollDuplicateReviewScreen> {
  late Future<List<PayrollDuplicateGroup>> _groups = _load();
  bool _busy = false;
  String? _error;

  Future<List<PayrollDuplicateGroup>> _load() =>
      LocalEmployeeReports(database: widget.database)
          .duplicateGroups(widget.businessId, isOwner: true);

  String _describe(EmployeeReportPayment entry) {
    final row = entry.expense!;
    final id = row['id'].toString();
    return [
      entry.savedName,
      if (row['copy_number'] case final int copyNumber) 'Copy $copyNumber',
      if (row['account'] case final String account) account,
      if (row['remarks'] case final String notes when notes.trim().isNotEmpty)
        notes,
      if (entry.operationId != null) 'Linked payroll payment',
      if (row['sync_state'] == 'pending') 'Pending sync',
      'Record ${id.length > 8 ? id.substring(id.length - 8) : id}',
    ].join(' · ');
  }

  Future<void> _review(
    PayrollDuplicateGroup group,
    EmployeeReportPayment duplicate,
  ) async {
    final keep = await showDialog<EmployeeReportPayment>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose the entry to keep'),
        children: [
          for (final entry in group.entries)
            if (entry != duplicate)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry),
                child: Text(_describe(entry)),
              ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (keep == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove duplicate on this device?'),
        content: Text(
          '${group.employee} · ${DateFormat.yMMMd().format(group.date)} · '
          '${NumberFormat.simpleCurrency(locale: 'en_US').format(group.cents / 100)}\n\n'
          'Keep ${_describe(keep)}\n\nRemove ${_describe(duplicate)}\n\n'
          'Confirm after checking the bank paid this amount once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove duplicate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grant = await DeviceOwnerAuthorization.instance.authority
          .authorizeLocal(widget.businessId);
      await OfflineFinancialWriteService(database: widget.database)
          .voidDuplicatePayrollExpense(
            widget.businessId,
            duplicateId: duplicate.expense!['id'].toString(),
            keepId: keep.expense!['id'].toString(),
            ownerId: grant.actorId,
            assertAuthorized: () => grant.assertValid(
              widget.businessId,
              supabase.auth.currentUser?.id ?? '',
            ),
          );
      if (mounted) setState(() => _groups = _load());
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove the duplicate.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ApprovedTasksHeader(title: 'Payroll Duplicates'),
    bottomNavigationBar: widget.sharedBottomNavigationBar,
    body: SafeArea(
      child: FutureBuilder<List<PayrollDuplicateGroup>>(
        future: _groups,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _groups = _load()),
                child: const Text('Could not read saved payroll. Retry'),
              ),
            );
          }
          final groups = snapshot.data ?? const <PayrollDuplicateGroup>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Review saved Payroll expenses for the same employee, date, and amount. '
                'Confirmed removals update this device and keep an audit record.',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No matching saved payroll expenses.'),
                ),
              for (final group in groups)
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(group.employee),
                        subtitle: Text(DateFormat.yMMMd().format(group.date)),
                        trailing: Text(
                          NumberFormat.simpleCurrency(locale: 'en_US')
                              .format(group.cents / 100),
                        ),
                      ),
                      for (final entry in group.entries)
                        ListTile(
                          title: Text(_describe(entry)),
                          trailing: entry.operationId == null
                              ? TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _review(group, entry),
                                  child: const Text('Review removal'),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
