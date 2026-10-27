// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:intl/intl.dart';

import '../local/local_database_provider.dart';
import 'employee_advance_ledger.dart';
import 'lab_payroll_payment_service.dart';

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
    this.embedded = false,
    this.onCancel,
    this.onPaymentSaved,
    this.onWeekChanged,
    this.onAssignedHoursChange,
  });

  final String employeeId;
  final String employeeName;
  final List<Map<String, dynamic>> tasks;
  final double Function(Map<String, dynamic>) hoursOf;
  final int? rateCents;
  final DateTime week;
  final bool embedded;
  final VoidCallback? onCancel;
  final Future<void> Function()? onPaymentSaved;
  final ValueChanged<DateTime>? onWeekChanged;
  final Future<void> Function(Map<String, dynamic>, double)? onAssignedHoursChange;

  @override
  State<WeeklyLaborReviewLab> createState() => _WeeklyLaborReviewLabState();
}

class _WeeklyLaborReviewLabState extends State<WeeklyLaborReviewLab> {
  final Map<String, double> _selected = {};
  final Map<String, double> _paidHours = {};
  final Map<String, double> _assignedOverrides = {};
  final Set<String> _expandedTasks = <String>{};
  bool _showTip = true;
  Timer? _tipTimer;
  static final _date = DateFormat('MMM d');
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
    _tipTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) { setState(() => _showTip = false); }
    });
    _load();
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensure() async {
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_weekly_payroll_drafts (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        week_key TEXT NOT NULL, selected_json TEXT NOT NULL,
        override_cents INTEGER, updated_at INTEGER NOT NULL,
        PRIMARY KEY(business_id, employee_id, week_key)
      )
    ''');
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_payroll_task_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        document_id TEXT NOT NULL,
        line_id TEXT NOT NULL,
        week_key TEXT NOT NULL,
        description TEXT NOT NULL,
        hours REAL NOT NULL,
        cents INTEGER NOT NULL,
        method TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        paid_at INTEGER NOT NULL
      )
    ''');
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_weekly_labor_notes (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        week_key TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(business_id, employee_id, week_key)
      )
    ''');
  }

  Future<void> _load({bool selectUnpaidByDefault = true}) async {
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
      final paidRows = await localDatabase.customSelect(
        'SELECT document_id, line_id, SUM(hours) AS paid_hours '
        'FROM lab_payroll_task_payments WHERE business_id=? AND employee_id=? '
        'GROUP BY document_id, line_id',
        variables: [const Variable<String>('briskers-tasks-test-only'),
          Variable<String>(widget.employeeId)],
      ).get();
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
      if (!mounted) { return; }
      setState(() {
        _paidHours.clear();
        for (final paid in paidRows) {
          final key = paid.read<String>('document_id') + ':' +
            paid.read<String>('line_id');
          _paidHours[key] = paid.read<double>('paid_hours');
        }
        _selected.clear();
        for (final task in _eligible) {
          final key = _id(task);
          final remaining = _available(task);
          if (selectUnpaidByDefault && remaining > 0) {
            final requested = selections[key];
            _selected[key] = requested == null ? remaining :
              requested.clamp(0.0, remaining).toDouble();
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to read test draft: ' + error.toString();
        });
      }
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

  double _assigned(Map<String, dynamic> task) =>
    _assignedOverrides[_id(task)] ?? widget.hoursOf(task);

  double _available(Map<String, dynamic> task) =>
    (_assigned(task) - (_paidHours[_id(task)] ?? 0))
      .clamp(0.0, double.infinity).toDouble();

  double get _totalHours {
    final ids = _eligible.map(_id).toSet();
    return _selected.entries.where((x) => ids.contains(x.key))
      .fold<double>(0, (sum, x) => sum + x.value);
  }


  void _selectAll() {
    final items = _eligible;
    final all = items.isNotEmpty && items.every((t) => _selected.containsKey(_id(t)));
    setState(() {
      for (final t in items) {
        final key = _id(t);
        if (all) {
          _selected.remove(key);
        } else {
          final hours = _available(t);
          if (hours > 0) { _selected.putIfAbsent(key, () => hours); }
        }
      }
    });
  }

  Future<void> _editHours(Map<String, dynamic> task) async {
    final key = _id(task);
    final paid = _paidHours[key] ?? 0;
    final assignedInput = TextEditingController(
      text:_assigned(task).toStringAsFixed(2));
    final payInput = TextEditingController(
      text:(_selected[key] ?? _available(task)).toStringAsFixed(2));
    final rawBilled = task['source_invoice_hours'];
    final billed = rawBilled is num ? rawBilled.toDouble() : null;
    final result = await showDialog<({double assigned,double pay})>(
      context:context,
      builder:(dialog) => AlertDialog(
        title:const Text('Edit Mechanic Labor · TEST'),
        content:SingleChildScrollView(child:Column(
          mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text((task['custom_description'] ??
              task['source_description'] ?? 'Task').toString(),
              style:const TextStyle(fontWeight:FontWeight.w700)),
            const SizedBox(height:12),
            Text('Customer billed: ' + (billed == null ? '—' :
              billed.toStringAsFixed(2) + ' hrs')),
            const SizedBox(height:12),
            TextField(
              controller:assignedInput,
              readOnly:widget.onAssignedHoursChange == null,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:const InputDecoration(
                labelText:'Mechanic assigned hours',
                suffixText:'hrs',border:OutlineInputBorder()),
              onTap:()=>assignedInput.selection=TextSelection(
                baseOffset:0,extentOffset:assignedInput.text.length),
            ),
            const SizedBox(height:10),
            Text('Previously paid: ' + paid.toStringAsFixed(2) + ' hrs'),
            const SizedBox(height:10),
            TextField(
              controller:payInput,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:const InputDecoration(
                labelText:'Hours to pay now',
                suffixText:'hrs',border:OutlineInputBorder()),
              onTap:()=>payInput.selection=TextSelection(
                baseOffset:0,extentOffset:payInput.text.length),
            ),
            const SizedBox(height:7),
            const Text('Customer billed labor is unchanged.',
              style:TextStyle(fontSize:11,color:Color(0xFF64748B))),
          ],
        )),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog),
            child:const Text('Cancel')),
          FilledButton(onPressed:(){
            final assigned=double.tryParse(assignedInput.text.trim());
            final pay=double.tryParse(payInput.text.trim());
            if(assigned==null||pay==null||!assigned.isFinite||
              !pay.isFinite||assigned<paid||pay<0||
              pay>assigned-paid+0.00001) {return;}
            Navigator.pop(dialog,(assigned:assigned,pay:pay));
          },child:const Text('Save')),
        ],
      ),
    );
    assignedInput.dispose();payInput.dispose();
    if(!mounted||result==null) {return;}
    try {
      if((result.assigned-_assigned(task)).abs()>0.00001) {
        await widget.onAssignedHoursChange?.call(task,result.assigned);
      }
      if(!mounted) {return;}
      setState((){
        _assignedOverrides[key]=result.assigned;
        if(result.pay<=0) {_selected.remove(key);}
        else {_selected[key]=result.pay;}
      });
    } catch(error) {
      if(mounted) {setState(() => _error =
        'Unable to update mechanic hours: ' + error.toString());}
    }
  }

  Future<void> _moveWeek(int weeks) async {
    setState(() => _week = _week.add(Duration(days: weeks * 7)));
    widget.onWeekChanged?.call(_week);
    await _load();
  }

  Future<void> _pickWeek() async {
    final value = await showDatePicker(
      context: context, initialDate: _week,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (value == null || !mounted) { return; }
    setState(() => _week = value);
    widget.onWeekChanged?.call(_week);
    await _load();
  }

  Future<void> _verifyPayment() async {
    if(_saving||_loading||_future||widget.rateCents==null||
      widget.rateCents!<=0||_totalHours<=0) {return;}
    final debt=await LabAdvanceLedger(localDatabase)
      .read('briskers-tasks-test-only',widget.employeeId);
    if(!mounted) {return;}
    final selected=Map<String,double>.from(_selected)
      ..removeWhere((key,hours)=>hours<=0);
    final laborCents=(_totalHours*widget.rateCents!).round();
    final amount=TextEditingController(
      text:(laborCents/100).toStringAsFixed(2));
    final debtInput=TextEditingController();
    final note=TextEditingController();
    var method='zelle';
    var deduct=false;
    final confirmed=await showDialog<bool>(
      context:context,
      builder:(outer)=>StatefulBuilder(
        builder:(dialog,update)=>AlertDialog(
          title:const Text('Verify Payment · TEST'),
          content:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text(widget.employeeName+' · Week of '+
                DateFormat('MMM d, yyyy').format(_start(_week))),
              Text(selected.length.toString()+' tasks · '+
                _totalHours.toStringAsFixed(2)+' hours'),
              const SizedBox(height:10),
              Text(r'Calculated labor: $'+(laborCents/100).toStringAsFixed(2)),
              const SizedBox(height:9),
              TextField(
                controller:amount,
                keyboardType:const TextInputType.numberWithOptions(
                  decimal:true),
                decoration:const InputDecoration(
                  labelText:'Final gross payment',
                  prefixText:r'$ ',border:OutlineInputBorder()),
                onChanged:(value)=>update((){}),
                onTap:()=>amount.selection=TextSelection(
                  baseOffset:0,extentOffset:amount.text.length),
              ),
              const SizedBox(height:9),
              DropdownButtonFormField<String>(
                initialValue:method,
                decoration:const InputDecoration(
                  labelText:'Payment method',border:OutlineInputBorder()),
                items:const [
                  DropdownMenuItem(value:'zelle',child:Text('Zelle')),
                  DropdownMenuItem(value:'cash',child:Text('Cash')),
                  DropdownMenuItem(value:'check',child:Text('Check')),
                  DropdownMenuItem(value:'ach',child:Text('ACH')),
                ],
                onChanged:(value){
                  if(value!=null) {update(()=>method=value);}
                },
              ),
              if(debt.remainingCents>0) ...[
                const SizedBox(height:8),
                CheckboxListTile(
                  dense:true,contentPadding:EdgeInsets.zero,
                  value:deduct,
                  title:const Text('Deduct from employee debt'),
                  subtitle:Text(r'Currently owed: $'+
                    (debt.remainingCents/100).toStringAsFixed(2)),
                  onChanged:(value)=>update(()=>deduct=value??false),
                ),
                if(deduct) TextField(
                  controller:debtInput,
                  keyboardType:const TextInputType.numberWithOptions(
                    decimal:true),
                  decoration:const InputDecoration(
                    labelText:'Debt repayment',
                    prefixText:r'$ ',border:OutlineInputBorder()),
                  onChanged:(value)=>update((){}),
                  onTap:()=>debtInput.selection=TextSelection(
                    baseOffset:0,extentOffset:debtInput.text.length),
                ),
              ],
              const SizedBox(height:9),
              Builder(builder:(context){
                final gross=double.tryParse(amount.text.trim())??0;
                final repayment=deduct ?
                  (double.tryParse(debtInput.text.trim())??0):0.0;
                return Column(
                  crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text('Adjustment: '+(gross-laborCents/100>=0?'+':'')+
                      (gross-laborCents/100).toStringAsFixed(2)),
                    Text(r'Send employee: $'+
                      (gross-repayment).toStringAsFixed(2),
                      style:const TextStyle(fontWeight:FontWeight.w800)),
                  ]);
              }),
              const SizedBox(height:9),
              TextField(controller:note,maxLines:2,
                decoration:const InputDecoration(
                  labelText:'Payment note (optional)',
                  border:OutlineInputBorder())),
              const SizedBox(height:7),
              const Text('TEST ONLY · Local simulated payment; '
                'no external money transferred.',
                style:TextStyle(fontSize:11)),
            ],
          )),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(dialog,false),
              child:const Text('Cancel')),
            FilledButton(onPressed:(){
              final gross=double.tryParse(amount.text.trim());
              final repayment=deduct
                ? double.tryParse(debtInput.text.trim()):0.0;
              if(gross==null||!gross.isFinite||gross<=0||
                gross>1000000||repayment==null||!repayment.isFinite||
                repayment<0||(deduct&&repayment<=0)||
                repayment>gross||
                (repayment*100).round()>debt.remainingCents) {return;}
              Navigator.pop(dialog,true);
            },child:const Text('Pay (TEST)')),
          ],
        ),
      ),
    );
    if(confirmed==true&&mounted) {
      setState(()=>_saving=true);
      try {
        final grossCents=(double.parse(amount.text.trim())*100).round();
        final debtCents=deduct
          ? (double.parse(debtInput.text.trim())*100).round():0;
        final result=await LabPayrollPaymentService.record(
          employeeId:widget.employeeId,
          week:_week,tasks:_eligible,
          hoursByTask:selected,assignedHours:_assigned,
          hourlyRateCents:widget.rateCents!,
          grossCents:grossCents,debtCents:debtCents,
          method:method,note:note.text,
        );
        if(mounted) {
          await showDialog<void>(
            context:context,
            builder:(dialog)=>AlertDialog(
              title:const Text('Payment Recorded · TEST'),
              content:Column(
                mainAxisSize:MainAxisSize.min,
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(widget.employeeName+' · '+
                    result.hours.toStringAsFixed(2)+' hrs'),
                  Text(r'Gross compensation: $'+
                    (result.grossCents/100).toStringAsFixed(2)),
                  Text(r'Debt repayment: $'+
                    (result.debtCents/100).toStringAsFixed(2)),
                  Text(r'Transferred: $'+
                    (result.netCents/100).toStringAsFixed(2),
                    style:const TextStyle(fontWeight:FontWeight.w700)),
                  const SizedBox(height:8),
                  const Text('Saved locally; no external transfer sent.'),
                ],
              ),
              actions:[FilledButton(
                onPressed:()=>Navigator.pop(dialog),
                child:const Text('Done'))],
            ),
          );
          if(mounted) {
            if(widget.embedded) {
              await _load(selectUnpaidByDefault:false);
              await widget.onPaymentSaved?.call();
            } else {
              Navigator.pop(context,true);
            }
          }
        }
      } catch(error) {
        if(mounted) {setState(()=>
          _error='Payment not saved: '+error.toString());}
      } finally {
        if(mounted) {setState(()=>_saving=false);}
      }
    }
    amount.dispose();
    debtInput.dispose();
    note.dispose();
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
          widget.onWeekChanged?.call(_week);
          await _load();
        }),
    ]);
  }

  Widget _detailHours(String label,double? hrs) =>
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Text(label,style:const TextStyle(fontSize:12,color:Color(0xFF64748B))),
      Text(hrs==null?'—':hrs.toStringAsFixed(2)+' hrs',
        style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
    ]);

  Widget _compactWeekSelector() {
    final start = _start(_week);
    final end = _end(_week).subtract(const Duration(days: 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: SizedBox(
        height: 43,
        child: Row(children: [
          IconButton(
            tooltip: 'Previous week',
            visualDensity: VisualDensity.compact,
            iconSize: 21,
            onPressed: () => _moveWeek(-1),
            icon: const Icon(Icons.chevron_left)),
          Expanded(child: InkWell(
            onTap: _pickWeek,
            child: Center(child: Text(
              DateFormat('MMM d').format(start) + ' – ' +
                DateFormat('MMM d, yyyy').format(end),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center)),
          )),
          IconButton(
            tooltip: 'Next week',
            visualDensity: VisualDensity.compact,
            iconSize: 21,
            onPressed: () => _moveWeek(1),
            icon: const Icon(Icons.chevron_right)),
          IconButton(
            tooltip: 'Choose week',
            visualDensity: VisualDensity.compact,
            iconSize: 21,
            onPressed: _pickWeek,
            icon: const Icon(Icons.calendar_today_outlined)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _eligible;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close weekly labor',
          onPressed: () => Navigator.pop(context)),
        titleSpacing: 4,
        title: Row(children: [
          const Expanded(child: Text('Weekly labor times',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17,
              fontWeight: FontWeight.w400))),
          const Icon(Icons.engineering_outlined,
            size: 22, color: Color(0xFF00897B)),
          const SizedBox(width: 7),
          Container(width: 1, height: 24,
            color: const Color(0xFFCBD5E1)),
          const SizedBox(width: 7),
          Flexible(child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(widget.employeeName,
              maxLines: 1, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800)))),
        ]),
      ),
      body: SafeArea(child: Column(children: [
        widget.embedded ? _compactWeekSelector() : _weekSelector(),
        if (_showTip && !widget.embedded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2DE),
              borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'Select the work to include in this week. '
              'OFFLINE TEST · No actual payroll posting.',
              style: TextStyle(fontSize: 11.5,
                color: Color(0xFF80541A))),
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
              for(final task in tasks)
                Card(
                  key:ValueKey('payroll-task-'+_id(task)),
                  color:const Color(0xFFF0F6F5),
                  margin:const EdgeInsets.only(bottom:6),
                  child:Column(children:[
                    Row(children:[
                      Checkbox(
                        value:_selected.containsKey(_id(task)),
                        onChanged:_available(task)<=0 ? null :
                          (v)=>setState((){
                            if(v==true) {_selected[_id(task)]=_available(task);}
                            else {_selected.remove(_id(task));}
                          }),
                      ),
                      Expanded(child:InkWell(
                        onTap:()=>setState((){
                          if(!_expandedTasks.add(_id(task))) {
                            _expandedTasks.remove(_id(task));
                          }
                        }),
                        child:Padding(
                          padding:const EdgeInsets.symmetric(vertical:9),
                          child:Column(
                            crossAxisAlignment:CrossAxisAlignment.start,
                            children:[
                              Text((task['custom_description'] ??
                                task['source_description'] ?? 'Task').toString(),
                                maxLines:_expandedTasks.contains(_id(task))
                                  ? null:2,
                                overflow:_expandedTasks.contains(_id(task))
                                  ? TextOverflow.visible:TextOverflow.ellipsis,
                                style:const TextStyle(fontWeight:FontWeight.w700)),
                              Text('J-24 · '+task['status'].toString()+' · '+
                                _available(task).toStringAsFixed(2)+' unpaid hrs',
                                style:const TextStyle(fontSize:11,
                                  color:Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      )),
                      Text((_selected[_id(task)]??_available(task))
                        .toStringAsFixed(2)+'h',
                        style:const TextStyle(fontWeight:FontWeight.bold)),
                      IconButton(icon:const Icon(Icons.edit_outlined,size:19),
                        tooltip:'Edit mechanic assigned / payable hours',
                        onPressed:()=>_editHours(task)),
                      Icon(_expandedTasks.contains(_id(task))
                        ? Icons.keyboard_arrow_up:Icons.keyboard_arrow_down,
                        color:const Color(0xFF64748B),size:19),
                      const SizedBox(width:6),
                    ]),
                    if(_expandedTasks.contains(_id(task)))
                      Padding(
                        padding:const EdgeInsets.fromLTRB(50,0,14,12),
                        child:Column(children:[
                          const Divider(height:12),
                          _detailHours('Customer billed',
                            task['source_invoice_hours'] is num
                              ? (task['source_invoice_hours'] as num).toDouble()
                              : null),
                          _detailHours('Mechanic assigned',_assigned(task)),
                          _detailHours('Previously paid',_paidHours[_id(task)]??0),
                          _detailHours('Remaining to pay',_available(task)),
                        ]),
                      ),
                  ]),
                ),
              if (!widget.embedded)
                const Text('Unfinished work can be paid partially in TEST. '
                  'Real payroll posting remains disabled.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          )),
        // Approved fixed footer: only the task-list above scrolls.
        Container(
          key: const Key('weekly-labor-fixed-footer'),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFD6E0E8)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F6F7),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(child: Column(children: [
                  const Text('Tasks selected', style: TextStyle(
                    fontSize: 10.5, color: Color(0xFF64748B))),
                  const SizedBox(height: 3),
                  Text(_selected.length.toString() +
                    ' of ' + tasks.length.toString(),
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
                ])),
                Expanded(child: Column(children: [
                  const Text('Selected this week', style: TextStyle(
                    fontSize: 10.5, color: Color(0xFF64748B))),
                  const SizedBox(height: 3),
                  Text(_totalHours.toStringAsFixed(2) + ' hrs',
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF00897B))),
                ])),
                Expanded(child: Column(children: [
                  const Text('Available hours', style: TextStyle(
                    fontSize: 10.5, color: Color(0xFF64748B))),
                  const SizedBox(height: 3),
                  Text(tasks.fold<double>(0, (sum, task) =>
                    sum + _available(task)).toStringAsFixed(2) + ' hrs',
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
                ])),
              ]),
            ),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => widget.onCancel == null
                  ? Navigator.pop(context, false)
                  : widget.onCancel!(),
                child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: _loading || _saving || _future ||
                  _totalHours <= 0 ? null : _verifyPayment,
                child: const Text('Verify Payment'))),
            ]),
          ]),
        ),
      ])),
    );
  }
}
