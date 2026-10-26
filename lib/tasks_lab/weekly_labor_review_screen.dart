// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:intl/intl.dart';

import '../local/local_database_provider.dart';

/// Offline-only TEST labor draft. Never posts money or marks work paid.
class WeeklyLaborReviewLab extends StatefulWidget {
  const WeeklyLaborReviewLab({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.tasks,
    required this.hoursOf,
    required this.rateCents,
    required this.week,
  });

  final String employeeId;
  final String employeeName;
  final List<Map<String, dynamic>> tasks;
  final double Function(Map<String, dynamic>) hoursOf;
  final int? rateCents;
  final DateTime week;

  @override
  State<WeeklyLaborReviewLab> createState() => _WeeklyLaborReviewLabState();
}

class _WeeklyLaborReviewLabState extends State<WeeklyLaborReviewLab> {
  final Map<String, double> _selected = {};
  final _override = TextEditingController();
  static final _date = DateFormat('MMM d');
  static final _money = NumberFormat.simpleCurrency(locale: 'en_US');
  late DateTime _week;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static DateTime _start(DateTime date) =>
      DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  static DateTime _end(DateTime date) =>
      _start(date).add(const Duration(days: 7));
  static String _id(Map<String, dynamic> task) =>
      task['document_id'].toString() + ':' + task['line_id'].toString();
  static String _weekKey(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(_start(value));
  bool get _future => _start(_week).isAfter(DateTime.now());
  bool get _current => _start(_week) == _start(DateTime.now());

  @override
  void initState() {
    super.initState();
    _week = widget.week;
    _load();
  }

  @override
  void dispose() {
    _override.dispose();
    super.dispose();
  }

  Future<void> _ensure() => localDatabase.customStatement('''
    CREATE TABLE IF NOT EXISTS lab_weekly_payroll_drafts (
      business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
      week_key TEXT NOT NULL, selected_json TEXT NOT NULL,
      override_cents INTEGER, updated_at INTEGER NOT NULL,
      PRIMARY KEY(business_id, employee_id, week_key)
    )
  ''');

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _ensure();
      final row = await localDatabase.customSelect(
        'SELECT selected_json, override_cents FROM lab_weekly_payroll_drafts '
        'WHERE business_id=? AND employee_id=? AND week_key=?',
        variables: [
          const Variable<String>('briskers-tasks-test-only'),
          Variable<String>(widget.employeeId),
          Variable<String>(_weekKey(_week)),
        ],
      ).getSingleOrNull();
      final selections = <String, double>{};
      if (row != null) {
        final data = jsonDecode(row.read<String>('selected_json'));
        if (data is Map) {
          for (final item in data.entries) {
            if (item.key is String && item.value is num) {
              final n = (item.value as num).toDouble();
              if (n > 0 && n.isFinite) { selections[item.key as String] = n; }
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _selected..clear()..addAll(selections);
        final cents = row?.readNullable<int>('override_cents');
        _override.text = cents == null ? '' : (cents / 100).toStringAsFixed(2);
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Unable to read test draft: ' + error.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _eligible {
    if (_future) return const [];
    if (_current) return widget.tasks;
    return widget.tasks.where((task) {
      final t = task['completed_at'];
      if (t is! int || task['status'] != 'done') return false;
      final when = DateTime.fromMillisecondsSinceEpoch(t);
      return !when.isBefore(_start(_week)) && when.isBefore(_end(_week));
    }).toList();
  }

  double get _totalHours {
    final ids = _eligible.map(_id).toSet();
    return _selected.entries.where((x) => ids.contains(x.key))
      .fold<double>(0, (sum, x) => sum + x.value);
  }

  int get _suggestedCents => (_totalHours * (widget.rateCents ?? 0)).round();

  void _selectAll() {
    final items = _eligible;
    final all = items.isNotEmpty && items.every((t) => _selected.containsKey(_id(t)));
    setState(() {
      for (final t in items) {
        final key = _id(t);
        if (all) {
          _selected.remove(key);
        } else {
          final hours = widget.hoursOf(t);
          if (hours > 0) { _selected.putIfAbsent(key, () => hours); }
        }
      }
    });
  }

  Future<void> _editHours(Map<String, dynamic> task) async {
    final key = _id(task);
    final maxHours = widget.hoursOf(task);
    final input = TextEditingController(text:
      (_selected[key] ?? maxHours).toStringAsFixed(1));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hours to pay (TEST)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Assigned: ' + maxHours.toStringAsFixed(1) + ' hrs'),
          const SizedBox(height: 12),
          TextField(
            controller: input,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Payable hours', border: OutlineInputBorder()),
            onTap: () => input.selection = TextSelection(
              baseOffset: 0, extentOffset: input.text.length),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final parsed = double.tryParse(input.text);
            if (parsed == null || !parsed.isFinite || parsed < 0 ||
                parsed > maxHours) return;
            Navigator.pop(context, parsed);
          }, child: const Text('Apply')),
        ],
      ),
    );
    input.dispose();
    if (value == null || !mounted) { return; }
    setState(() {
      if (value == 0) { _selected.remove(key); }
      else { _selected[key] = value; }
    });
  }

  Future<void> _moveWeek(int weeks) async {
    setState(() => _week = _week.add(Duration(days: weeks * 7)));
    await _load();
  }

  Future<void> _pickWeek() async {
    final value = await showDatePicker(
      context: context, initialDate: _week,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (value == null || !mounted) { return; }
    setState(() => _week = value);
    await _load();
  }

  Future<void> _save() async {
    if (_loading || _saving || _future) return;
    int? cents;
    if (_override.text.trim().isNotEmpty) {
      final value = double.tryParse(_override.text.trim());
      if (value == null || !value.isFinite || value < 0 ||
          value > 1000000) {
        setState(() => _error = 'Enter a valid final amount');
        return;
      }
      cents = (value * 100).round();
    }
    final valid = <String, double>{};
    for (final task in _eligible) {
      final key = _id(task), hours = _selected[key];
      if (hours != null && hours > 0 && hours <= widget.hoursOf(task)) {
        valid[key] = hours;
      }
    }
    setState(() => _saving = true);
    try {
      await _ensure();
      await localDatabase.customStatement(
        'INSERT INTO lab_weekly_payroll_drafts '
        '(business_id, employee_id, week_key, selected_json, '
        'override_cents, updated_at) VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(business_id,employee_id,week_key) DO UPDATE SET '
        'selected_json=excluded.selected_json, '
        'override_cents=excluded.override_cents, updated_at=excluded.updated_at',
        ['briskers-tasks-test-only', widget.employeeId,
         _weekKey(_week), jsonEncode(valid), cents,
         DateTime.now().millisecondsSinceEpoch],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() =>
        _error = 'Unable to save test draft: ' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _weekSelector() {
    final start = _start(_week);
    final end = _end(_week).subtract(const Duration(days: 1));
    return Row(children: [
      IconButton(icon: const Icon(Icons.chevron_left),
        onPressed: () => _moveWeek(-1)),
      Expanded(child: InkWell(
        onTap: _pickWeek,
        child: Column(children: [
          Text('Week of ' + DateFormat('MMMM d').format(start),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(_date.format(start) + ' – ' +
            DateFormat('MMM d, yyyy').format(end) +
            (_current ? ' · Current' : _future ? ' · Future' : ' · Previous'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        ]),
      )),
      IconButton(icon: const Icon(Icons.chevron_right),
        onPressed: () => _moveWeek(1)),
      IconButton(icon: const Icon(Icons.today_outlined),
        tooltip: 'Current week',
        onPressed: () async {
          setState(() => _week = DateTime.now());
          await _load();
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _eligible;
    return Scaffold(
      appBar: AppBar(title: Text('Weekly Labor Times — ' + widget.employeeName,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFDDECFD),
              child: Icon(Icons.build_outlined)),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.employeeName,
              style: const TextStyle(fontWeight: FontWeight.bold))),
            const Text('TEST ONLY', style: TextStyle(
              color: Color(0xFF865A1E), fontWeight: FontWeight.bold)),
          ]),
        ),
        _weekSelector(),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF2DE),
            borderRadius: BorderRadius.circular(8)),
          child: const Text(
            'Offline draft · No real payroll posting or paid-once tracking.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF80541A))),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(6),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: ListView(
            key: const Key('weekly-labor-tasks-scroll-only'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Row(children: [
                Expanded(child: Text('Jobs & Tasks · ' + tasks.length.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
                TextButton(
                  onPressed: tasks.isEmpty ? null : _selectAll,
                  child: Text(tasks.isNotEmpty &&
                    tasks.every((t) => _selected.containsKey(_id(t)))
                      ? 'Clear All' : 'Select All'),
                ),
              ]),
              if (tasks.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(_future
                    ? 'Future weeks show no earned payroll. Planned work '
                      'requires scheduling data.'
                    : 'No dated test labor for this week.',
                    style: const TextStyle(color: Color(0xFF64748B)))),
              for (final task in tasks)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Checkbox(
                      value: _selected.containsKey(_id(task)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          final h = widget.hoursOf(task);
                          if (h > 0) { _selected[_id(task)] = h; }
                        } else { _selected.remove(_id(task)); }
                      }),
                    ),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((task['custom_description'] ??
                          task['source_description'] ?? 'Task').toString(),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('J-24 · ' + task['status'].toString() +
                          ' · ' + widget.hoursOf(task).toStringAsFixed(1) +
                          ' assigned hrs', style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    )),
                    Text((_selected[_id(task)] ??
                      widget.hoursOf(task)).toStringAsFixed(1) + 'h',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      tooltip: 'Edit hours',
                      onPressed: () => _editHours(task)),
                  ]),
                ),
              const Text('Unfinished tasks can be selected, but '
                'this test cannot verify or mark previously paid labor.',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          )),
        // Fixed footer: ONLY the task list above scrolls.
        Container(
          key: const Key('weekly-labor-fixed-footer'),
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFD6E0E8)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_selected.length.toString() + ' tasks · ' +
                  _totalHours.toStringAsFixed(1) + ' hrs',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(widget.rateCents == null
                  ? 'Rate not set'
                  : 'Suggested ' + _money.format(_suggestedCents / 100),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            const SizedBox(height: 8),
            TextField(
              controller: _override,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Final amount override (TEST)',
                prefixText: r'$ ', border: OutlineInputBorder()),
              onTap: () => _override.selection = TextSelection(
                baseOffset: 0, extentOffset: _override.text.length),
            ),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(
                onPressed: _loading || _saving || _future ? null : _save,
                child: const Text('Save Draft (TEST)'))),
            ]),
          ]),
        ),
      ])),
    );
  }
}
