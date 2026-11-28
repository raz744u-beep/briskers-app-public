import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/local_owner_reports.dart';
import '../../services/local_shop_closeout.dart';
import '../../services/local_task_reminders.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/job_document_screen.dart';
import '../payroll/approved_tasks_ui.dart';
import '../payroll/owner_payroll_screen.dart';

class ShopCloseoutScreen extends StatefulWidget {
  const ShopCloseoutScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    required this.reports,
    this.bottomNavigationBar,
  });

  final String businessId;
  final bool isOwner;
  final LocalOwnerReports reports;
  final Widget? bottomNavigationBar;

  @override
  State<ShopCloseoutScreen> createState() => _ShopCloseoutScreenState();
}

class _ShopCloseoutScreenState extends State<ShopCloseoutScreen> {
  late Future<ShopCloseout> _agenda = _load();
  final _reminders = LocalTaskReminders();
  bool? _reminder;

  @override
  void initState() {
    super.initState();
    if (widget.isOwner) _readReminder();
  }

  Future<void> _readReminder() async {
    try {
      final enabled = await _reminders.fridayCloseoutEnabled(widget.businessId);
      if (mounted) setState(() => _reminder = enabled);
    } catch (_) {
      if (mounted) setState(() => _reminder = false);
    }
  }

  Future<void> _setReminder(bool enabled) async {
    final before = _reminder;
    setState(() => _reminder = null);
    try {
      await _reminders.setFridayCloseoutReminder(widget.businessId, enabled);
      if (mounted) setState(() => _reminder = enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _reminder = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The Friday reminder could not be updated. Check device notification settings.',
          ),
        ),
      );
    }
  }

  Future<ShopCloseout> _load() =>
      LocalShopCloseout(widget.reports)
          .load(widget.businessId, isOwner: widget.isOwner);

  void _refresh() => setState(() {
    _agenda = _load();
  });

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) _refresh();
  }

  Widget _section(
    String title,
    List<CloseoutItem> items,
    String emptyLabel, {
    ValueChanged<CloseoutItem>? onTap,
  }) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: Text('${items.length}'),
        ),
        if (items.isEmpty) ListTile(title: Text(emptyLabel)),
        for (final item in items)
          ListTile(
            title: Text(item.title),
            subtitle: Text(item.detail),
            trailing: onTap == null ? null : const Icon(Icons.chevron_right),
            onTap: onTap == null ? null : () => onTap(item),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return const Scaffold(
        body: Center(child: Text('Owner access is required.')),
      );
    }
    return Scaffold(
      backgroundColor: taskCanvas,
      appBar: ApprovedTasksHeader(
        title: 'Friday Closeout',
        actions: [
          IconButton(
            tooltip: 'Refresh closeout',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
        ],
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: FutureBuilder<ShopCloseout>(
        future: _agenda,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(
              child: Text(
                'Saved shop records could not be read. Refresh to retry.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Week ending ${DateFormat.yMMMd().format(data.friday)}\n'
                  'Records saved on this device · Read ${DateFormat.yMMMd().add_jm().format(data.loadedAt)}',
                ),
              ),
              _section(
                'Completed labor awaiting payroll',
                data.labor,
                data.payrollAvailable
                    ? 'No completed unpaid labor found on this device.'
                    : 'Payroll records unavailable.',
                onTap: OwnerPayrollScreen.enabled
                    ? (_) => _open(
                        OwnerPayrollScreen(
                          businessId: widget.businessId,
                          sharedBottomNavigationBar: widget.bottomNavigationBar,
                        ),
                      )
                    : null,
              ),
              _section(
                'Fully paid invoices ready to close',
                data.invoices,
                'No invoices verified ready on this device.',
                onTap: (item) => _open(
                  JobDocumentScreen(
                    businessId: widget.businessId,
                    documentId: item.id,
                    isOwner: true,
                    roleCode: 'owner',
                    canManageExpenses: true,
                    sharedBottomNavigationBar: widget.bottomNavigationBar,
                  ),
                ),
              ),
              _section(
                'Open jobs requiring attention',
                data.jobs,
                'No open jobs found on this device.',
                onTap: (item) => _open(
                  JobDetailScreen(
                    businessId: widget.businessId,
                    jobId: item.id,
                    roleCode: 'owner',
                    bottomNavigationBar: widget.bottomNavigationBar,
                  ),
                ),
              ),
              if (data.verify.isNotEmpty)
                _section('Needs verification', [
                  for (final detail in data.verify)
                    (title: detail, detail: '', id: ''),
                ], ''),
              SwitchListTile(
                title: const Text('Friday device reminder'),
                subtitle: const Text('Around 3 PM Gretna time'),
                value: _reminder ?? false,
                onChanged: _reminder == null ? null : _setReminder,
              ),
            ],
          );
        },
      ),
    );
  }
}
