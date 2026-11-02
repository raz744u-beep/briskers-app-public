import 'package:flutter/material.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'local/briskers_local_database.dart';
import 'services/integrated_test_payroll.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = BriskersLocalDatabase(
    driftDatabase(name: 'briskers_integrated_payroll_TEST'),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: IntegratedPayrollHome(repository: IntegratedTestPayroll(db)),
    ),
  );
}

String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
String today() => DateTime.now().toIso8601String().substring(0, 10);
String monday() => DateTime.now()
    .subtract(Duration(days: DateTime.now().weekday - 1))
    .toIso8601String()
    .substring(0, 10);
int decimal(String s) {
  if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(s.trim()))
    { throw ArgumentError('Enter a number with up to two decimals'); }
  final negative = s.trim().startsWith('-');
  final parts = s.trim().replaceFirst('-', '').split('.');
  final n =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return negative ? -n : n;
}

class IntegratedPayrollHome extends StatefulWidget {
  const IntegratedPayrollHome({super.key, required this.repository});
  final IntegratedTestPayroll repository;
  @override
  State<IntegratedPayrollHome> createState() => _IntegratedPayrollHomeState();
}

class _IntegratedPayrollHomeState extends State<IntegratedPayrollHome> {
  IntegratedTestPayroll get r => widget.repository;
  List<Map<String, dynamic>> _jobs = [],
      _tasks = [],
      _work = [],
      _employees = [],
      _history = [];
  String _employee = 'chris', _message = 'Loading local TEST records…';
  int _advance = 0, _page = 0;
  bool _busy = false;
  final _selected = <String>{};
  final _week = TextEditingController(text: monday());
  final _date = TextEditingController(text: today());
  final _base = TextEditingController(text: '0');
  final _adjust = TextEditingController(text: '0');
  final _reason = TextEditingController();
  final _repay = TextEditingController(text: '0');
  String _method = 'Cash';
  @override
  void initState() {
    super.initState();
    _run(() async {
      await r.initializeEmployees();
    });
  }

  @override
  void dispose() {
    for (final c in [_week, _date, _base, _adjust, _reason, _repay]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final jobs = await r.jobs(),
        tasks = await r.tasks(),
        work = await r.work(),
        employees = await r.employees(),
        history = await r.history(_employee),
        advance = await r.advance(_employee);
    if (!mounted) { return; }
    setState(() {
      _jobs = jobs;
      _tasks = tasks;
      _work = work;
      _employees = employees;
      _history = history;
      _advance = advance;
      _selected.removeWhere(
        (id) => !work.any(
          (w) => w['id'] == id && w['paid'] == 0 && w['state'] == 'Done',
        ),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) { return; }
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
      if (mounted)
        { setState(
          () =>
              _message = 'Saved locally • financial posting and sync disabled',
        ); }
    } catch (e) {
      if (mounted) { setState(() => _message = 'Action rejected: $e'); }
    } finally {
      if (mounted) { setState(() => _busy = false); }
    }
  }

  Future<List<String>?> _form(
    String title,
    List<String> labels,
    List<String> initial,
  ) async {
    final cs = initial.map((v) => TextEditingController(text: v)).toList();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                TextField(
                  controller: cs[i],
                  decoration: InputDecoration(labelText: labels[i]),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, cs.map((c) => c.text.trim()).toList()),
            child: const Text('Save locally'),
          ),
        ],
      ),
    );
    // Dialog fields may remain mounted during their exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final c in cs) {
      c.dispose();
    }
    return result;
  }

  Future<void> _newJob() async {
    final v = await _form(
      'New TEST job',
      ['Vehicle / description'],
      ['TEST vehicle'],
    );
    if (v != null)
      { await _run(
        () =>
            r.createJob('TEST-${DateTime.now().microsecondsSinceEpoch}', v[0]),
      ); }
  }

  Future<void> _labor(Map<String, dynamic> job) async {
    final v = await _form(
      'Add invoice labor / recheck',
      ['Labor description', 'Billed hours'],
      ['Service labor', '2.50'],
    );
    if (v != null)
      { await _run(
        () => r.addLabor(
          job['id'] as String,
          'line-${DateTime.now().microsecondsSinceEpoch}',
          v[0],
          decimal(v[1]),
        ),
      ); }
  }

  Future<void> _assign(Map<String, dynamic> task) async {
    final employee = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign another mechanic'),
        children: [
          for (final e in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e['id'] as String),
              child: Text(e['name'] as String),
            ),
        ],
      ),
    );
    if (employee != null)
      { await _run(() => r.assign(task['id'] as String, employee)); }
  }

  Future<void> _edit(Map<String, dynamic> w, String state) async {
    final v = await _form(
      state == 'Done' ? 'Complete own work' : 'Edit / start own work',
      ['Actual hours'],
      [((w['hours_hundredths'] as int) / 100).toStringAsFixed(2)],
    );
    if (v != null)
      { await _run(
        () => r.updateWork(w['id'] as String, state, decimal(v[0]), today()),
      ); }
  }

  List<Map<String, dynamic>> get _picked => _work
      .where(
        (w) => _selected.contains(w['id']) && w['employee_id'] == _employee,
      )
      .toList();
  int _gross() =>
      _picked.fold<int>(
        0,
        (sum, w) =>
            sum +
            ((w['hours_hundredths'] as int) * (w['rate_cents'] as int) + 50) ~/
                100,
      ) +
      decimal(_base.text) +
      decimal(_adjust.text);
  Future<void> _verify() async {
    try {
      final picked = _picked,
          base = decimal(_base.text),
          adjustment = decimal(_adjust.text),
          repayment = decimal(_repay.text),
          gross = _gross();
      final date = _date.text,
          week = _week.text,
          method = _method,
          reason = _reason.text;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verify TEST Payment'),
          content: Text(
            '${picked.length} completed work portions\nGross: ${money(gross)}\nAdvance repayment: ${money(repayment)}\nPay now: ${money(gross - repayment)} via $method\nDate: $date\n\nRecords this payment in the isolated TEST database.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Verify Payment'),
            ),
          ],
        ),
      );
      if (confirmed != true) { return; }
      final operation = 'payment-${DateTime.now().microsecondsSinceEpoch}';
      await _run(() async {
        await r.verify(
          operation: operation,
          employee: _employee,
          week: week,
          date: date,
          method: method,
          selected: picked,
          base: base,
          hourlyAdjustment: adjustment,
          adjustmentReason: reason,
          repayment: repayment,
          confirmedNet: gross - repayment,
        );
        _selected.clear();
        _base.text = '0';
        _adjust.text = '0';
        _repay.text = '0';
      });
    } catch (e) {
      if (mounted) { setState(() => _message = 'Verification rejected: $e'); }
    }
  }

  Widget _field(String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _workCard(Map<String, dynamic> w) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${w['employee_id']} • ${w['description']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${w['state']} • ${(w['hours_hundredths'] as int) / 100} hrs • ${money(w['rate_cents'] as int)}/hr${w['paid'] == 1 ? ' • PAID (frozen)' : ''}',
          ),
          if (w['paid'] == 0)
            Wrap(
              spacing: 8,
              children: [
                if (w['state'] == 'Open')
                  TextButton(
                    onPressed: _busy ? null : () => _edit(w, 'In Progress'),
                    child: const Text('Start'),
                  ),
                if (w['state'] == 'In Progress')
                  TextButton(
                    onPressed: _busy ? null : () => _edit(w, 'Done'),
                    child: const Text('Done'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _edit(w, w['state'] as String),
                  child: const Text('Edit hours'),
                ),
                if (w['state'] == 'Done')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => r.updateWork(
                              w['id'] as String,
                              'In Progress',
                              w['hours_hundredths'] as int,
                              today(),
                            ),
                          ),
                    child: const Text('Reopen unpaid work'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
  Widget _jobsView() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      FilledButton(
        onPressed: _busy ? null : _newJob,
        child: const Text('New TEST job'),
      ),
      if (_jobs.isEmpty)
        const Text('Create a job, add labor, then assign mechanics.'),
      for (final j in _jobs)
        Card(
          child: ExpansionTile(
            title: Text(j['label'] as String),
            subtitle: Text(
              '${j['done']} of ${j['total']} tasks done • ${j['total'] != 0 && j['done'] == j['total']
                  ? 'Complete'
                  : j['started'] != 0
                  ? 'In Progress'
                  : 'Open'}',
            ),
            children: [
              TextButton(
                onPressed: _busy ? null : () => _labor(j),
                child: const Text('Add labor line / new recheck'),
              ),
              for (final t in _tasks.where((t) => t['job_id'] == j['id']))
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(t['description'] as String),
                        subtitle: Text(
                          'Labor ${(t['planned'] as int) / 100} hrs',
                        ),
                        trailing: IconButton(
                          tooltip: 'Assign mechanic',
                          onPressed: _busy ? null : () => _assign(t),
                          icon: const Icon(Icons.person_add),
                        ),
                      ),
                      for (final w in _work.where(
                        (w) => w['task_id'] == t['id'],
                      ))
                        _workCard(w),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ],
  );
  Widget _payrollView() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _field('Week beginning Monday (YYYY-MM-DD)', _week),
      const Text(
        'Select completed unpaid work. Older unpaid work can be included as an Owner override.',
      ),
      for (final w in _work.where(
        (w) =>
            w['employee_id'] == _employee &&
            w['state'] == 'Done' &&
            w['paid'] == 0,
      ))
        CheckboxListTile(
          title: Text(
            '${w['description']} • ${(w['hours_hundredths'] as int) / 100} hrs',
          ),
          subtitle: Text(
            'Completed ${w['completed_date']} • ${money(((w['hours_hundredths'] as int) * (w['rate_cents'] as int) + 50) ~/ 100)}',
          ),
          value: _selected.contains(w['id']),
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  if (v == true) {
                    _selected.add(w['id'] as String);
                  } else {
                    _selected.remove(w['id']);
                  }
                }),
        ),
      if (_employee == 'base') _field('Weekly base (dollars)', _base),
      _field('Hourly earnings adjustment (dollars)', _adjust),
      _field('Owner adjustment / older work reason', _reason),
      ExpansionTile(
        title: Text('Advances & Repayments • ${money(_advance)} outstanding'),
        children: [
          _field('Deduct advance repayment (dollars)', _repay),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final v = await _form(
                      'Add TEST advance',
                      ['Amount (dollars)'],
                      ['20'],
                    );
                    if (v != null)
                      { await _run(() => r.addAdvance(_employee, decimal(v[0]))); }
                  },
            child: const Text('Add TEST advance'),
          ),
        ],
      ),
      DropdownButtonFormField<String>(
        initialValue: _method,
        decoration: const InputDecoration(labelText: 'Payment method'),
        items: [
          for (final m in ['Cash', 'Zelle', 'Check', 'Card', 'Other'])
            DropdownMenuItem(value: m, child: Text(m)),
        ],
        onChanged: _busy ? null : (v) => setState(() => _method = v!),
      ),
      _field('Verification date (YYYY-MM-DD)', _date),
      FilledButton(
        onPressed: _busy ? null : _verify,
        child: const Text('Review / Verify Payment'),
      ),
    ],
  );
  Widget _reportsView() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Text('Historical TEST payroll payments'),
      for (final p in _history)
        ExpansionTile(
          title: Text(
            '${p['verified_date']} • ${money(p['net'] as int)} • ${p['method']}',
          ),
          subtitle: Text(
            'Gross ${money(p['gross'] as int)} • repayment ${money(p['repayment'] as int)}',
          ),
          children: [SelectableText(p['payload'] as String)],
        ),
    ],
  );
  Widget _profile() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<String>(
          initialValue: _employee,
          items: [
            for (final e in _employees)
              DropdownMenuItem(
                value: e['id'] as String,
                child: Text(e['name'] as String),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  setState(() {
                    _employee = v!;
                    _selected.clear();
                    _base.text = '0';
                    _repay.text = '0';
                    _adjust.text = '0';
                  });
                  _run(() async {});
                },
        ),
      ),
      Expanded(
        child: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Details'),
                  Tab(text: 'Tasks'),
                  Tab(text: 'Payroll'),
                  Tab(text: 'Reports'),
                  Tab(text: 'Taxes & 1099'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Isolated TEST employee. Rates are snapshotted on assignment. No real employee records are used.',
                      ),
                    ),
                    ListView(
                      children: [
                        for (final w in _work.where(
                          (w) => w['employee_id'] == _employee,
                        ))
                          _workCard(w),
                      ],
                    ),
                    _payrollView(),
                    _reportsView(),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Recorded gross TEST income: ${money(_history.fold<int>(0, (s, p) => s + (p['gross'] as int)))}\nRepayments do not reduce gross.\n1099 export is not implemented in this milestone.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Briskers Integrated TEST')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'OFFLINE • Isolated data • No real financial posting',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Text(_message),
        Expanded(child: _page == 0 ? _jobsView() : _profile()),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _page,
      onDestinationSelected: (p) => setState(() => _page = p),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.build), label: 'Jobs / Tasks'),
        NavigationDestination(
          icon: Icon(Icons.payments),
          label: 'Employee / Payroll',
        ),
      ],
    ),
  );
}
