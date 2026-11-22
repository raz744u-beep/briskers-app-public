import '../../services/recorded_payroll_week.dart';
import 'recorded_weekly_payment_card.dart';
import '../../core/briskers_colors.dart';
import 'approved_tasks_ui.dart' show taskBlue, taskCanvas, taskGreen, taskNavy;
import 'payroll_review_widgets.dart';
import 'employee_work_review.dart';
import '../../services/payroll_owner_lease.dart';
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef RecordWeeklyPayroll = Future<void> Function(
  DateTime week, DateTime date, String method,
  List<Map<String, dynamic>> selected, int adjustment, int repayment,
  int net, String reason, int base,
);

class WeeklyLaborReview extends StatefulWidget {
  const WeeklyLaborReview({
    super.key,
    required this.employeeId,
    this.sharedBottomNavigationBar,
    required this.employeeName,
    required this.tasks,
    required this.advanceBalance,
    required this.recordPayment,
    required this.week,
    this.embedded = false,
    this.profileLayout = false,
    this.paymentHistory = const [],
    this.savedRateCents,
    this.onOpenJob,
    this.onOpenTask,
    this.reviewMessage,
    this.advancePanel,
    this.profileAdvanceBalance,
    this.saveDraft,
    this.loadDraft,
    this.onCancel,
    this.onPaymentSaved,
    this.onWeekChanged,
    this.weeklyBaseCents = 0,
    this.weeklyAdjustmentCents = 0,
    this.settlementRateCents,
    this.requiredSupplementMinutes,
    this.settlementReason = '',

  });

  final Widget? sharedBottomNavigationBar;
  final String employeeId;
  final String employeeName;
  final List<Map<String, dynamic>> tasks;
  final Future<int> Function() advanceBalance;
  final RecordWeeklyPayroll recordPayment;
  final DateTime week;
  final bool embedded;
  final bool profileLayout;
  final List<Map<String,dynamic>> paymentHistory;
  final int? savedRateCents;
  final ValueChanged<String>? onOpenJob;
  final Future<void> Function(Map<String, dynamic>)? onOpenTask;
  final String? reviewMessage;
  final Widget Function(Widget Function(VoidCallback cancel)? paycheckEditor)?
      advancePanel;
  final int? profileAdvanceBalance;
  final Future<void> Function(DateTime,Map<String,double>,int,int,String)? saveDraft;
  final Future<Map<String,dynamic>?> Function(DateTime)? loadDraft;
  final VoidCallback? onCancel;
  final Future<void> Function()? onPaymentSaved;
  final ValueChanged<DateTime>? onWeekChanged;
  final int weeklyBaseCents;
  final int weeklyAdjustmentCents;
  final int? settlementRateCents;
  final int? requiredSupplementMinutes;
  final String settlementReason;

  @override
  State<WeeklyLaborReview> createState() => _WeeklyLaborReviewState();
}

class _WeeklyLaborReviewState extends State<WeeklyLaborReview> {
  final Map<String, double> _selected = {};
  // Preserve deliberate exclusions when a task finishes behind its detail page.
  final Set<String> _excluded = <String>{};
  final Set<String> _expandedTasks = <String>{};
  bool _showTip = true;
  Timer? _tipTimer;
  static final _date = DateFormat('MMM d');
  late DateTime _week;
  bool _saving = false;
  int _preparedAdjustment=0,_preparedRepayment=0;
  String _preparedReason='';
  String? _error;

  static DateTime _start(DateTime date) =>
      DateTime(date.year, date.month, date.day,)
        .subtract(Duration(days: date.weekday - 1));
  static DateTime _end(DateTime date) =>
      _start(date).add(const Duration(days: 5));
  static String _id(Map<String, dynamic> task) => task['id'] as String;
  static double _assigned(Map<String, dynamic> task) =>
      (task['estimated_minutes'] as int? ?? task['actual_minutes'] as int) / 60;
  static double _paidHours(Map<String, dynamic> task) =>
      (task['paid_minutes'] as int? ?? (task['paid'] == 1 ? task['actual_minutes'] as int : 0)) / 60;
  static String _statusLabel(Map<String, dynamic> task) => switch (task['state']) {
    'In Progress' => 'In Progress',
    'Done' => 'Completed',
    _ => 'Planned',
  };
  bool get _future => _start(_week).isAfter(DateTime.now());
  bool get _current => _start(_week) == _start(DateTime.now());

  @override
  void initState() {
    super.initState();
    _week = widget.week;
    _tipTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) { setState(() => _showTip = false); }
    });
    _selectUnpaid();
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WeeklyLaborReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.employeeId != oldWidget.employeeId) {
      _week = widget.week;
      _selectUnpaid(); unawaited(_restoreDraft());
      return;
    }
    if(widget.week!=oldWidget.week) {
      _week=widget.week; _selectUnpaid(); unawaited(_restoreDraft());
      return;
    }
    final available = {
      for (final task in _eligible)
        if (_available(task) > 0) _id(task): _available(task),
    };
    _selected.removeWhere((id, _) => !available.containsKey(id));
    final previousTasks = {for (final task in oldWidget.tasks) _id(task): task};
    final previousPaid = {for (final task in oldWidget.tasks) _id(task): task['paid_minutes']};
    _selected.removeWhere((id, _) =>
        widget.tasks.any((task) => _id(task) == id &&
            previousPaid[id] != task['paid_minutes']));
    _selected.updateAll((id, requested) => requested.clamp(0.0, available[id]!).toDouble(),);
    // Task Details refreshes this same mounted review after a local completion.
    // Apply the initial completed/unpaid default only to the new transition;
    // never reset other choices, edited hours, or newly paid allocations.
    for (final task in _eligible) {
      final id = _id(task), previous = previousTasks[_id(task)];
      if (previous != null && previous['state'] != 'Done' &&
          task['state'] == 'Done' && available.containsKey(id) &&
          (!widget.profileLayout || (task['paid_minutes'] as int? ?? 0) == 0) &&
          previous['paid_minutes'] == task['paid_minutes'] && !_excluded.contains(id)) {
        _selected.putIfAbsent(id, () => available[id]!);
      }
    }
  }

  void _choose(Map<String, dynamic> task, bool selected) {
    final id = _id(task);
    if (selected) {
      _excluded.remove(id);
      _selected.putIfAbsent(id, () => _available(task));
    } else {
      _excluded.add(id);
      _selected.remove(id);
    }
  }

  void _selectUnpaid() {
    _preparedAdjustment=0;_preparedRepayment=0;_preparedReason='';
    _selected.clear();
    _excluded.clear();
    for (final task in _eligible) {
      final remaining = _available(task);
      if (remaining > 0 &&
          task['state'] == 'Done' &&
          (!widget.profileLayout || (task['paid_minutes'] as int? ?? 0) == 0)) {
        _selected[_id(task)] = remaining;
      }
    }
  }

  List<Map<String, dynamic>> get _eligible {
    if (_future) return const [];
    return widget.tasks.where((task) {
      final progress = widget.profileLayout && task['state'] == 'In Progress';
      final date = DateTime.tryParse(
        (progress
                    ? task['work_start_date'] ?? task['invoice_date']
                    : task['completed_date'])
                ?.toString() ?? '',);
      // Archived historical labor remains visible elsewhere, but must NEVER
      // become selectable for new payroll without explicit Owner carry-forward.
      final lastPaidWeek = DateTime.tryParse(task['last_paid_week']?.toString() ?? '');
      if (progress && lastPaidWeek != null && !_start(_week).isAfter(lastPaidWeek)) {
        return false;
      }
      final carry=DateTime.tryParse(task['carry_week']?.toString()??'');
      if(carry!=null && carry.isAfter(_start(_week)))return false;
      if(widget.profileLayout && _rate(task)<=0)return false;
      if (task['payroll_treatment'] == 'review' ||task['archived_labor']==1 || task['assignment_conflict']==1 ||
          (!progress && task['state'] != 'Done') ||
          task['source_active'] == 0 || date == null || !date.isBefore(_end(_week))) {
        return false;
      }
      return task['paid'] != 1 || !date.isBefore(_start(_week));
    }).toList();
  }

  static double _available(Map<String, dynamic> task) =>
      task['paid'] == 1 || !['Done', 'In Progress'].contains(task['state'])
      ? 0 :
        (task['remaining_minutes'] as int? ?? task['actual_minutes'] as int) / 60;

  double get _totalHours {
    final ids = _eligible.map(_id).toSet();
    return _selected.entries.where((x) => ids.contains(x.key))
      .fold<double>(0, (sum, x) => sum + x.value);
  }


  void _selectAll() {
    // Paid allocations are historical, never part of a new selection.
    final items = _eligible.where((task) => _available(task) > 0.00001).toList();
    final all = items.isNotEmpty && items.every((t) => _selected.containsKey(_id(t)));
    setState(() {
      for (final t in items) {
        if (all) {
          _choose(t, false);
        } else {
          final hours = _available(t);
          if (hours > 0) { _choose(t, true); }
        }
      }
    });
  }

  Future<void> _editHours(Map<String, dynamic> task) async {
    if (_saving || _available(task) <= 0) return;
    final hours = await showDialog<double>(
      context: context,
      builder: (_) => PayableHoursDialog(
        task: task,
        selected: _selected[_id(task)] ?? _available(task),
        total: _assigned(task),
        paid: _paidHours(task),
        remaining: _available(task)),
    );
    if (hours != null && mounted) { setState(() {
        if (hours == 0) {
          _choose(task, false);
        } else {
          _excluded.remove(_id(task));
          _selected[_id(task)] = hours;
        }
      });
      await _savePreparationDraft();
    }
  }
    Future<void> _savePreparationDraft() async {
    if (!widget.profileLayout || widget.saveDraft == null) return;
    try {
      await widget.saveDraft!(
        _start(_week),
        Map<String, double>.from(_selected),
        _preparedAdjustment,
        _preparedRepayment,
        _preparedReason,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save the payroll draft. Please retry Save (Draft).',
        );
      }
    }
  }

  void _moveWeek(int weeks) {
    if (_saving) return;
    setState(() {
      _week = _week.add(Duration(days: weeks * 7));
      _selectUnpaid();
    });
    widget.onWeekChanged?.call(_week);
  }

  Future<void> _pickWeek() async {
    if (_saving) return;
    final value = await showDatePicker(
      context: context, initialDate: _week,
      firstDate: DateTime(2020), lastDate: DateTime(2100),);
    if (value == null || !mounted) { return; }
    setState(() => _week = value);
    widget.onWeekChanged?.call(_week);
    if (mounted) setState(_selectUnpaid);
  }

  Future<void> _verifyPayment() async {
    if (_saving || _future || (_totalHours <= 0 && widget.weeklyBaseCents <= 0)) { return;
    }
    setState(() { _saving = true; _error = null; });
    late final int debt;
    try {
      debt = await widget.advanceBalance();
    } catch (error) {
      if (mounted) { setState(() { _saving = false; _error = error.toString(); });
      }
      return;
    }
    if (!mounted) return;
    final week = _start(_week);
    final selected = [
      for (final task in _eligible)
        if (_selected.containsKey(_id(task)) && _available(task) > 0)
          {...task,
            if (task['state'] == 'In Progress') 'allow_in_progress': true, 'pay_minutes': (_selected[_id(task)]! * 60).round(),
            if (widget.settlementRateCents != null) 'payment_rate_cents': widget.settlementRateCents,},

    ];
    final laborCents = selected.fold<int>(0, (sum, task) {
      final paid = task['paid_minutes'] as int? ?? 0;
      final minutes = task['pay_minutes'] as int;
      final rate = widget.settlementRateCents ?? task['payment_rate_cents'] as int? ?? task['rate_cents'] as int? ?? 0;
      // Older widget fixtures provide a total but real records carry the rate.
      if (!task.containsKey('rate_cents')) { return sum + (task['gross_cents'] as int);
      }
      return sum + (((paid + minutes) * rate + 30) ~/ 60) - ((paid * rate + 30) ~/ 60);
    });
    final hours = selected.fold<int>(0, (sum, task) => sum + (task['pay_minutes'] as int),) / 60;
    final totalMinutes = selected.fold<int>(0, (sum, task) => sum + (task['pay_minutes'] as int),);
    if (widget.requiredSupplementMinutes != null && totalMinutes != widget.requiredSupplementMinutes) {
      setState(() {
        _saving = false;
        _error = 'Select exactly ${(widget.requiredSupplementMinutes! / 60).toStringAsFixed(2)} approved supplemental hours.';
      });
      return;
    }
    final calculatedGross = laborCents + widget.weeklyBaseCents + widget.weeklyAdjustmentCents;
    final amount=TextEditingController(
      text:((calculatedGross+_preparedAdjustment)/100).toStringAsFixed(2),);
    final debtInput=TextEditingController(text:_preparedRepayment>0?(_preparedRepayment/100).toStringAsFixed(2):'',);
    final note=TextEditingController(text:_preparedReason);
    var method='Zelle';
    var paidDate = DateTime.now();
    var deduct=_preparedRepayment>0;
    // Optional repayment is collapsed until explicitly expanded.
    var showDebtOptions=_preparedRepayment>0;
    final confirmed=await showDialog<bool>(
      context:context,
      builder:(outer)=>StatefulBuilder(
        builder:(dialog,update)=>AlertDialog(
          backgroundColor: Colors.white,
          titlePadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          title: Container(
            color: taskNavy,
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Verify Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          content:SizedBox(width:double.maxFinite,child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text(widget.employeeName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Week of ${DateFormat('MMM d').format(week)} – ${DateFormat('MMM d, yyyy').format(week.add(const Duration(days: 4)))}',
                  style: const TextStyle(fontWeight: FontWeight.w600),),
              Text(selected.length.toString()+' tasks · '+
                hours.toStringAsFixed(2)+' hours',),
              const SizedBox(height:10),
              if (widget.weeklyBaseCents > 0)
                Text('Weekly base: ${(widget.weeklyBaseCents / 100).toStringAsFixed(2)}',),
              Text(r'Calculated labor: $'+(laborCents/100).toStringAsFixed(2),),
              if (widget.weeklyAdjustmentCents != 0)
                Text('Weekly adjustment: ${(widget.weeklyAdjustmentCents / 100).toStringAsFixed(2)}',),
              const SizedBox(height:9),
              TextField(
                  key: const Key('verify-final-gross'),
                  controller:amount,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: taskGreen,
                  ),
                  keyboardType:const TextInputType.numberWithOptions(
                  decimal:true,),
                decoration:const InputDecoration(
                  labelText:'Final gross payment',
                    filled: true,
                    fillColor: Color(0xFFECF8E9),
                  prefixText:r'$ ',border:OutlineInputBorder(),),
                onChanged:(value)=>update((){}),
                onTap:()=>amount.selection=TextSelection(
                  baseOffset:0,extentOffset:amount.text.length,),
              ),
              const SizedBox(height:9),
              Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:DropdownButtonFormField<String>(
                isExpanded:true,
                initialValue:method,
                decoration:const InputDecoration(
                  labelText:'Payment method',isDense:true,contentPadding:EdgeInsets.symmetric(horizontal:10,vertical:12),border:OutlineInputBorder(),),
                items:const [
                  DropdownMenuItem(value:'Zelle',child:Text('Zelle')),
                  DropdownMenuItem(value:'Cash',child:Text('Cash')),
                  DropdownMenuItem(value:'Check',child:Text('Check')),
                  DropdownMenuItem(value:'ACH',child:Text('ACH')),
                  DropdownMenuItem(value:'Card',child:Text('Card')),
                  DropdownMenuItem(value:'Other',child:Text('Other')),
                ],
                onChanged:(value){
                  if(value!=null) {update(()=>method=value);}
                },
              )),
              const SizedBox(width:8),
              Expanded(child:InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialog, initialDate: paidDate,
                    firstDate: DateTime(2020), lastDate: DateTime.now(),
                  );
                  if (date != null && dialog.mounted) { update(() => paidDate = date);
                    }
                },
                child:InputDecorator(decoration:const InputDecoration(labelText:'Payment date',isDense:true,contentPadding:EdgeInsets.symmetric(horizontal:10,vertical:12),border:OutlineInputBorder()),child:Row(children:[const Icon(Icons.calendar_today_outlined,size:18),const SizedBox(width:6),Expanded(child:Text(DateFormat.yMMMd().format(paidDate),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13)))])),
              )),]),
              if(debt>0) ...[
                const SizedBox(height:8),
                // Opening details does not authorize a payroll deduction.
                ListTile(
                  key:const Key('test-debt-deduction-expander'),
                  dense:true,
                  contentPadding:EdgeInsets.zero,
                  title:const Text('Debt deduction (optional)'),
                  trailing:Icon(showDebtOptions
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,),
                  onTap:()=>update((){
                    showDebtOptions=!showDebtOptions;
                    // Closing resets any selection: no hidden deduction.
                    if(!showDebtOptions) {
                      deduct=false;
                      debtInput.clear();
                    }
                  }),
                ),
                if(showDebtOptions) ...[
                  Text(r'Currently owed: $'+
                    (debt/100).toStringAsFixed(2),
                    style:const TextStyle(fontSize:12,
                      color:Color(0xFF64748B),),),
                  CheckboxListTile(
                    dense:true,contentPadding:EdgeInsets.zero,
                    value:deduct,
                    title:const Text('Deduct from employee debt'),
                    onChanged:(value)=>update(()=>deduct=value??false),
                  ),
                  if(deduct) TextField(
                    controller:debtInput,
                    keyboardType:const TextInputType.numberWithOptions(
                      decimal:true,),
                    decoration:const InputDecoration(
                      labelText:'Debt repayment',
                      prefixText:r'$ ',border:OutlineInputBorder(),),
                    onChanged:(value)=>update((){}),
                    onTapAlwaysCalled:true,
                    onTap:()=>debtInput.selection=TextSelection(
                      baseOffset:0,extentOffset:debtInput.text.length,),
                  ),
                ],
              ],
              const SizedBox(height:9),
              Builder(builder:(context){
                final gross=double.tryParse(amount.text.trim())??0;
                final repayment=deduct ?
                  (double.tryParse(debtInput.text.trim())??0):0.0;
                return Column(
                  crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text('Adjustment: '+(gross-calculatedGross/100>=0?'+':'')+
                      (gross-calculatedGross/100).toStringAsFixed(2,),),
                    Text(r'Send employee: $'+
                      (gross-repayment).toStringAsFixed(2),
                      style:const TextStyle(fontWeight:FontWeight.w800),),
                  ],);
              },),
              const SizedBox(height:9),
              TextField(controller:note,minLines:1,maxLines:2,
                decoration:const InputDecoration(
                  labelText:'Payment note or adjustment reason',
                  border:OutlineInputBorder(),),),
              const SizedBox(height:7),
              const Text('This records the payment in Briskers.',
                style:TextStyle(fontSize:11),),
            ],
          ),)),
          actions:[
            OutlinedButton(onPressed:()=>Navigator.pop(dialog,false),
              child:const Text('Cancel'),),
            FilledButton(style:FilledButton.styleFrom(backgroundColor:taskGreen),onPressed:(){
              final gross=double.tryParse(amount.text.trim());
              final repayment=deduct
                ? double.tryParse(debtInput.text.trim()):0.0;
              if(gross==null||!gross.isFinite||gross<=0||
                gross>1000000||repayment==null||!repayment.isFinite||
                repayment<0||(deduct&&repayment<=0)||
                repayment>gross||
                (repayment*100).round()>debt) {return;}
              if ((gross * 100).round() != calculatedGross && note.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Enter a reason for the gross adjustment.'),
                ),);
                return;
              }
              Navigator.pop(dialog,true);
            },child:const Text('Record payment'),),
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
        final carryForward = selected.any((task) =>
              (DateTime.tryParse(
                (task['completed_date'] ??
                            task['work_start_date'] ??
                            task['invoice_date'])
                        ?.toString() ??
                    '',
              )?.isBefore(week) ??
              false),);
        final reason = [
          if (carryForward) 'Prior unpaid work carried forward.',
          if (selected.any((t) => t['allow_in_progress'] == true))
            'Owner selected partial In Progress labor; work status unchanged.',
          if (widget.settlementReason.isNotEmpty) widget.settlementReason,
          if(selected.any((t)=>t['payment_rate_cents']!=null)) 'Use saved local employee compensation for previously unrated unpaid labor.',
          if (note.text.trim().isNotEmpty) note.text.trim(),
        ].join(' ');
        await widget.recordPayment(
          week, paidDate, method, selected, grossCents - laborCents - widget.weeklyBaseCents,
          debtCents, grossCents - debtCents, reason, widget.weeklyBaseCents,
        );
        if(mounted) {
          await showDialog<void>(
            context:context,
            builder:(dialog)=>AlertDialog(
              title:const Text('Payment Recorded'),
              content:Column(
                mainAxisSize:MainAxisSize.min,
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(widget.employeeName+' · '+
                    hours.toStringAsFixed(2)+' hrs',),
                  Text(r'Gross compensation: $'+
                    (grossCents/100).toStringAsFixed(2),),
                  Text(r'Debt repayment: $'+
                    (debtCents/100).toStringAsFixed(2),),
                  Text(r'Transferred: $'+
                    ((grossCents - debtCents)/100).toStringAsFixed(2),
                    style:const TextStyle(fontWeight:FontWeight.w700),),
                  const SizedBox(height:8),
                  const Text('Saved locally; no external transfer sent.'),
                ],
              ),
              actions:[FilledButton(
                onPressed:()=>Navigator.pop(dialog),
                child:const Text('Done'),),],
            ),
          );
          if(mounted) {
            if(widget.embedded) {
              setState((){_selected.clear();_preparedAdjustment=0;_preparedRepayment=0;_preparedReason='';});
              await widget.onPaymentSaved?.call();
            } else {
              Navigator.pop(context,true);
            }
          }
        }
      } on PayrollAlreadyRecorded catch (error) {
        if (mounted) { setState(() { _error = error.message; _selected.clear(); });
        }
        await widget.onPaymentSaved?.call();
      } on PayrollPending catch (error) {
        if (mounted) setState(() => _error = error.message);
      } catch(error) {
        if(mounted) {setState(()=>
          _error='Payment not saved: '+error.toString());}
      } finally {
        if(mounted) {setState(()=>_saving=false);}
      }
    }
    if (mounted && _saving) setState(() => _saving = false);
    amount.dispose();
    debtInput.dispose();
    note.dispose();
  }

  Widget _weekSelector() {
    final start = _start(_week);
    final end = _end(_week).subtract(const Duration(days: 1));
    return Row(children: [
      IconButton(icon: const Icon(Icons.chevron_left),
        onPressed: () => _moveWeek(-1),),
      Expanded(child: InkWell(
        onTap: _pickWeek,
        child: Column(children: [
          Text('Week of ' + DateFormat('MMMM d').format(start),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800,),),
          Text(_date.format(start) + ' – ' +
            DateFormat('MMM d, yyyy').format(end) +
            (_current ? ' · Current' : _future ? ' · Future' : ' · Previous'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B),),),
        ],),
      ),),
      IconButton(icon: const Icon(Icons.chevron_right),
        onPressed: () => _moveWeek(1),),
      IconButton(icon: const Icon(Icons.today_outlined),
        tooltip: 'Current week',
        onPressed: () async {
          setState(() => _week = DateTime.now());
          widget.onWeekChanged?.call(_week);
          if (mounted) setState(_selectUnpaid);
        },),
    ],);
  }

  Widget _detailHours(String label,double? hrs) =>
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Text(label,style:const TextStyle(fontSize:12,color:Color(0xFF64748B)),),
      Text(hrs==null?'—':hrs.toStringAsFixed(2)+' hrs',
        style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700),),
    ],);

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
            icon: const Icon(Icons.chevron_left),),
          Expanded(child: InkWell(
            onTap: _pickWeek,
            child: Center(child: Text(
              DateFormat('MMM d').format(start) + ' – ' +
                DateFormat('MMM d, yyyy').format(end),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,),
              textAlign: TextAlign.center,),
          ),
              ),),
          IconButton(
            tooltip: 'Next week',
            visualDensity: VisualDensity.compact,
            iconSize: 21,
            onPressed: () => _moveWeek(1),
            icon: const Icon(Icons.chevron_right),),
          IconButton(
            tooltip: 'Choose week',
            visualDensity: VisualDensity.compact,
            iconSize: 21,
            onPressed: _pickWeek,
            icon: const Icon(Icons.calendar_today_outlined),),
        ],),
      ),
    );
  }

  Future<void> _restoreDraft() async {
    if(!widget.profileLayout || widget.loadDraft==null)return;
    final week=_start(_week);
    final Map<String,dynamic> savedDraft;
    try { savedDraft=await widget.loadDraft!(week) ?? <String,dynamic>{}; } catch(error) {
      if(mounted) {setState(()=>_error='Could not load the saved draft: $error');
      }
      return;
    }
    if(!mounted || _start(_week)!=week || savedDraft.isEmpty)return;
    final available = {
      for (final task in _eligible)
        if ((task['paid_minutes'] as int? ?? 0) == 0) _id(task): _available(task),
    };
    setState(() { _selected.clear(); _preparedAdjustment=savedDraft['adjustment'] as int? ?? 0;_preparedRepayment=savedDraft['repayment'] as int? ?? 0;_preparedReason=savedDraft['reason'] as String? ?? '';
      for(final entry in (savedDraft['hours'] as Map).entries) {
      final remaining=available[entry.key]??0;
      if(remaining>0 && entry.value>0) {_selected[entry.key]=(entry.value as num).clamp(0,remaining).toDouble();
        }
      }
      _excluded..clear()..addAll(available.keys.where((id) => !_selected.containsKey(id)));
    });
  }
  Future<void> _applyPreparation(_PayrollPreparation value) async {
    setState(() {
      _preparedAdjustment = value.adjustment;
      _preparedRepayment = value.repayment;
      _preparedReason = value.reason;
      _error = null;
    });
    await _savePreparationDraft();
  }

  Future<void> _editPreparation(int labor) async {
    final debt=await widget.advanceBalance();
    if(!mounted)return;
    final adjustment=TextEditingController(text:(_preparedAdjustment/100).toStringAsFixed(2),);
    final repayment=TextEditingController(text:(_preparedRepayment/100).toStringAsFixed(2),);
    final reason=TextEditingController(text:_preparedReason);
    final saved=await showDialog<bool>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update){
      final a=double.tryParse(adjustment.text),r=double.tryParse(repayment.text);
      final valid=a!=null&&r!=null&&a.isFinite&&r.isFinite&&a.abs()<=1000000&&r>=0&&(r*100).round()<=debt&&labor+(a*100).round()>=(r*100).round()&&(a==0||reason.text.trim().isNotEmpty);
          InputDecoration field(String label) => InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
          );
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            title:const Row(
              children: [
                Icon(Icons.payments_outlined, color: taskGreen),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Adjustments & Repayment',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children:[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3EEFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Outstanding advance: \$${(debt/100).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Adjustment (+/−)'),
                  const SizedBox(height: 6),
        TextField(controller:adjustment,keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true,),decoration: field('Adjustment (+/−)',),onChanged:(_)=>update((){}),),
                  const SizedBox(height: 12),
                  const Text('Repayment from this payment'),
                  const SizedBox(height: 6),
        TextField(controller:repayment,keyboardType:const TextInputType.numberWithOptions(decimal:true,),decoration: field('Repayment from this payment',),onChanged:(_)=>update((){}),),
                  const SizedBox(height: 12),
                  const Text('Adjustment reason'),
                  const SizedBox(height: 6),
                  TextField(controller:reason,
                    minLines: 2,
                    maxLines: 3,
                    decoration: field('Adjustment reason',),onChanged:(_)=>update((){}),),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F7DE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(valid
                          ? 'Payment Total: \$${((labor+(a*100).round()-(r*100).round())/100).toStringAsFixed(2)}'
                          : 'Check amounts, advance limit and adjustment reason.',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: taskGreen,
                      ),
                    ),),
      ],),),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel'),),FilledButton(
                style: FilledButton.styleFrom(backgroundColor: taskGreen),
                onPressed:valid?()=>Navigator.pop(dialog,true):null,child:const Text('Apply'),),],);
    },),);
    if(saved==true&&mounted) {setState((){_preparedAdjustment=(double.parse(adjustment.text)*100).round();_preparedRepayment=(double.parse(repayment.text)*100).round();_preparedReason=reason.text.trim();});
      await _savePreparationDraft();
    }
    Future<void>.delayed(const Duration(milliseconds:400),(){adjustment.dispose();repayment.dispose();reason.dispose();});
  }

  _PayrollPreparation get _preparedValues => (
    adjustment: _preparedAdjustment,
    repayment: _preparedRepayment,
    reason: _preparedReason,
  );

  Widget _inlinePreparation(int gross, VoidCallback cancel) =>
      _PayrollPreparationEditor(
        key: ValueKey((widget.employeeId, _week)),
        initial: _preparedValues,
        gross: gross,
        debt: widget.profileAdvanceBalance,
        enabled: !_saving,
        onCancel: cancel,
        onApply: _applyPreparation,
      );

  int _rate(Map<String,dynamic> task)=>widget.settlementRateCents ?? task['payment_rate_cents'] as int? ?? task['rate_cents'] as int? ?? 0;
  int _amount(Map<String,dynamic> task,double hours) {
    return selectedLaborCents(task, hours,rate: _rate(task));
  }
  Widget _payableCard(Map<String,dynamic> task) {
    final id = _id(task), expanded = _expandedTasks.contains(_id(task));
    final hours = _selected[id] ?? _available(task);
    final amount = NumberFormat.simpleCurrency(locale:'en_US').format(_amount(task,hours)/100);
    final description = '${task['description'] ?? 'Labor'}';
    return Card(
      key: ValueKey('payable-$id'),
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: const BoxDecoration(border: Border(left: BorderSide(color:Color(0xFF008C12),width:5))),
        child: InkWell(
          onTap: () => setState(() { if(expanded){_expandedTasks.remove(id);}else{_expandedTasks.add(id);} }),
          child: Column(children:[
            Padding(padding:const EdgeInsets.fromLTRB(0,6,6,6),child:Row(children:[
              SizedBox(width:40,child:Checkbox(
                semanticLabel:'Select $description for payroll',
                value:_selected.containsKey(id),
                onChanged:_saving?null:(v)=>setState(()=>_choose(task,v==true)),
              )),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Semantics(link:true,child:InkWell(
                  onTap:widget.onOpenJob==null || task['job_id']==null?null:()=>widget.onOpenJob!(task['job_id'] as String),
                  child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('${task['job_number']??'Job'} · ${task['customer_name']??''}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Color(0xFF17202A),fontSize:14,fontWeight:FontWeight.w800))),
                )),
                Text(description,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Color(0xFF17202A),fontSize:13)),
                const SizedBox(height:3),
                          Text(
                            '${_statusLabel(task)} · ${_paidHours(task) > 0 ? 'Partially Paid' : 'Unpaid'}',maxLines:1,overflow:TextOverflow.ellipsis,style: const TextStyle(color:Color(0xFF17202A),fontSize:12)),
                const SizedBox(height:5),
              ])),
              Container(width:80,margin:const EdgeInsets.only(left:8),padding:const EdgeInsets.only(left:7),decoration:const BoxDecoration(border:Border(left:BorderSide(color:Color(0xFFD4D9E2)))),child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
                FittedBox(child:Text('${hours.toStringAsFixed(2)} h',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:Color(0xFF17202A)))),
                const SizedBox(height:3),
                FittedBox(child:Text(amount,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:Color(0xFF087A17)))),
              ])),
              Icon(expanded?Icons.expand_less:Icons.chevron_right,size:22,color:const Color(0xFF17202A)),
            ])),
            if(expanded)Padding(padding:const EdgeInsets.fromLTRB(14,0,14,10),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: taskCanvas,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(description,style:const TextStyle(color:Color(0xFF17202A)))),
              if(task['carry_week']!=null && task['work_end_date']==null)const Text('Warranty rework · Carry-forward'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextButton.icon(
                  key: ValueKey('view-payable-task-$id'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFDDF0FF),
                    foregroundColor: const Color(0xFF0753B5),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: widget.onOpenTask == null ? null : () => widget.onOpenTask!(task),
                  icon: const Icon(Icons.open_in_new, size: 19),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('View Task', style: TextStyle(fontWeight: FontWeight.w800))),
                )),
                const SizedBox(width: 10),
                Expanded(child: TextButton.icon(
                  key: ValueKey('edit-payable-hours-$id'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFE4F7E6),
                    foregroundColor: const Color(0xFF087A17),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : () => _editHours(task),
                  icon: const Icon(Icons.schedule_outlined, size: 19),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Payable Hours', style: TextStyle(fontWeight: FontWeight.w800))),
                )),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
  Widget _profileBody() {
    final tasks=_eligible.where((r)=>_available(r)>0 && _rate(r)>0).toList();
    final start=_start(_week);
    final review=EmployeeWorkReview.weeklyReviewRows(widget.tasks,_week,rate:_rate);
    final recorded=RecordedPayrollWeek.fromHistory(widget.paymentHistory,employeeId:widget.employeeId,week:start);
    final paid=recorded.work;
    final preparing=tasks.isNotEmpty || (!recorded.hasPayments && widget.weeklyBaseCents>0) ||
        _preparedAdjustment!=0 || _preparedRepayment!=0;
    final labor=tasks.fold<int>(widget.weeklyBaseCents,(n,r)=>n+_amount(r,_selected[_id(r)]??0),);
    final adjustment=widget.weeklyAdjustmentCents+_preparedAdjustment,gross=labor+widget.weeklyAdjustmentCents+_preparedAdjustment;
    final net=gross-_preparedRepayment;
    final total=tasks.fold<double>(0,(n,r)=>n+_available(r));
    String money(int n)=>NumberFormat.simpleCurrency(locale:'en_US').format(n/100);
    Widget metric(String label,String value,Color color)=>Expanded(child:Container(
        height: (MediaQuery.textScalerOf(context).scale(35)+ 24).clamp(
          62.0,
          120.0,
        ),padding:const EdgeInsets.symmetric(horizontal: 6, vertical: 6),margin:const EdgeInsets.all(3),decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(14),),child:Column(
          mainAxisAlignment: MainAxisAlignment.center,children:[
            FittedBox(
              fit: BoxFit.scaleDown,
              child:Text(label,textAlign:TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child:Text(value,textAlign:TextAlign.center,style: TextStyle(fontSize: 21,fontWeight:FontWeight.w800,
                  color: label == 'Unpaid Hours'
                      ? taskBlue
                      : label == 'Paid Total'
                      ? const Color(0xFF7134B4)
                      : taskGreen,
                  fontFeatures: const [FontFeature.tabularFigures()],),),
            ),],),),);
    Widget summary(String label, String value, {String? unit, bool total = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(label, style: total
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null),
            ),
            if (unit != null) ...[Text(unit), const SizedBox(width: 6)],
            Text(value, textAlign: TextAlign.end, style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
          ],
        ),
      );
    }
    return ListView(key:const Key('employee-payroll-preparation'),padding: EdgeInsets.fromLTRB(12,
        12,
        12,
        20 + MediaQuery.paddingOf(context).bottom,),children:[
      Card(child:_compactWeekSelector()),
      Row(children:[metric(
              'Unpaid Hours',total.toStringAsFixed(2),const Color(0xFFEAF3FF),),metric(
              'Rate / Hr',widget.savedRateCents==null?'Not saved':money(widget.savedRateCents!),const Color(0xFFEAF8EF),),metric('Paid Total',RecordedWeeklyPaymentCard.money(recorded.netCents),const Color(0xFFF2ECFF)),],),
      const SizedBox(height:10),
      RecordedWeeklyPaymentCard(recorded:recorded),
      if(recorded.hasPayments) Card(
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12),
          side:BorderSide(color:BriskersColors.confirm.withValues(alpha:0.4))),
        child:ExpansionTile(
          key:PageStorageKey('payroll-paid-${widget.employeeId}-${_week.toIso8601String()}'),
          leading:const Icon(Icons.receipt_long_outlined,color:BriskersColors.confirm),
          textColor:BriskersColors.confirm,collapsedTextColor:BriskersColors.confirm,
          iconColor:BriskersColors.confirm,collapsedIconColor:BriskersColors.confirm,
          title:const Text('View paid work details',style:TextStyle(fontWeight:FontWeight.w700)),
          subtitle:Text(EmployeeWorkReview.weekLabel(_week)),
          children:[
            if(paid.isEmpty) const ListTile(title:Text('No labor task details are saved on these payments.')),
            for(final r in paid) ListTile(
              title:Text('${r['job_number'] ?? 'Job'} · ${r['description'] ?? 'Paid labor'}'),
              subtitle:Text('${r['actual_minutes'] is int ? ((r['actual_minutes'] as int)/60).toStringAsFixed(2) : 'Not saved'} hrs paid'
                '${r['verified_date']==null?'':' · ${r['verified_date']}'}'
                '${r['method']==null?'':' · ${r['method']}'}'),
              trailing:Text(RecordedWeeklyPaymentCard.money(r['gross_cents'] is int ? r['gross_cents'] as int : null),
                style:const TextStyle(fontWeight:FontWeight.w700)),
            ),
          ],
        ),
      ),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
      Padding(padding:const EdgeInsets.fromLTRB(8,12,8,2),child:Row(children:[
        Expanded(child:Text('Unpaid Labor (${tasks.length})',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800))),
        FilledButton.icon(onPressed:_saving||tasks.isEmpty?null:_selectAll,
          style:FilledButton.styleFrom(backgroundColor:const Color(0xFF008C12),padding:const EdgeInsets.symmetric(horizontal:12)),
          icon:Icon(tasks.isNotEmpty&&tasks.every((r)=>_selected.containsKey(_id(r)))?Icons.deselect:Icons.done_all,size:18),
          label:Text(tasks.isNotEmpty&&tasks.every((r)=>_selected.containsKey(_id(r)))?'Deselect All':'Select All')),
      ])),
      if(tasks.isEmpty)const ListTile(title:Text('No verified unpaid labor for this week.')),
      for(final task in tasks)_payableCard(task),
      if(review.isNotEmpty)Card(child:ExpansionTile(key:PageStorageKey('payroll-review-${widget.employeeId}-${_week.toIso8601String()}',),title:Text('Needs Review (${review.length})'),children:[
        if(widget.reviewMessage!=null)ListTile(title:Text(widget.reviewMessage!)),
        for(final r in review)ListTile(title:Text('${r['job_number']} · ${r['description']}'),subtitle:const Text('Pay status or compensation requires review; excluded from payment.',),),],),),
      if(preparing) Card(
          key:const Key('new-weekly-payment-preparation'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(gradient: BriskersColors.blueHeader),
                child: const Row(
                  children: [
                    Icon(Icons.calculate_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New Payment',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(padding:const EdgeInsets.all(12),child:Column(children:[summary('Total Selected Hours', _totalHours.toStringAsFixed(2), unit: 'hrs'),summary('Labor Pay',money(labor)),summary('Adjustments (+/−)',money(adjustment)),summary('Gross Pay',money(gross)),summary('Advance repayment',money(_preparedRepayment)),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFBCEFB4),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: summary('Payment Total', money(net), total: true),
                    ),
                    if (widget.advancePanel == null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _editPreparation(labor + widget.weeklyAdjustmentCents),
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Adjustments & repayment'),
                      ),
                    ],
                  ],),
              ),
            ],
          ),),
      if (widget.advancePanel case final buildAdvancePanel?)
        buildAdvancePanel(
          preparing && !_future
              ? (cancel) => _inlinePreparation(
                    labor + widget.weeklyAdjustmentCents, cancel,
                  )
              : null,
        ),
      if(preparing) Wrap(spacing:10,runSpacing:8,alignment:WrapAlignment.spaceBetween,children:[OutlinedButton(onPressed:_saving||widget.saveDraft==null?null:()async {await widget.saveDraft!(_start(_week),Map<String,double>.from(_selected),_preparedAdjustment,_preparedRepayment,_preparedReason,);if(mounted) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Payroll draft saved locally.'),),);
                      }},child:const Text('Save (Draft)'),),
        FilledButton.icon(key:const Key('verify-weekly-payment'),style:FilledButton.styleFrom(backgroundColor:const Color(0xFF0A8F53),),onPressed:_saving||_future||gross<=0||net<0||(_totalHours<=0&&widget.weeklyBaseCents<=0)?null:_verifyPayment,icon:const Icon(Icons.check),label:const Text('Verify Weekly Payment'),),
    ],
        ),
      ],);
  }

  @override
  Widget build(BuildContext context) {
    if(widget.profileLayout)return _profileBody();
    final tasks = _eligible.where((task) => _available(task) > 0.00001).toList();
    final pending = _current
        ? widget.tasks.where((task) => task['state'] != 'Done').toList()
        : const <Map<String, dynamic>>[];
    // A zero-hour or unassigned task is not proof of a payment.
    final paidTaskCount = _eligible.where((task) =>
      _available(task) <= 0.00001 && _paidHours(task) > 0
    ).length;
    return Scaffold(
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      appBar: widget.embedded ? null : AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close weekly labor',
          onPressed: () => Navigator.pop(context),),
        titleSpacing: 4,
        title: Row(children: [
          const Expanded(child: Text('Weekly labor times',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17,
              fontWeight: FontWeight.w400,),),),
          const Icon(Icons.engineering_outlined,
            size: 22, color: Color(0xFF00897B),),
          const SizedBox(width: 7),
          Container(width: 1, height: 24,
            color: const Color(0xFFCBD5E1),),
          const SizedBox(width: 7),
          Flexible(child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(widget.employeeName,
              maxLines: 1, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,),),),),
        ],),
      ),
      body: SafeArea(child: Column(children: [
        widget.embedded ? _compactWeekSelector() : _weekSelector(),
        if (_showTip && !widget.embedded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 7,),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2DE),
              borderRadius: BorderRadius.circular(8),),
            child: const Text(
              'Select the work to include in this week.',
              style: TextStyle(fontSize: 11.5,
                color: Color(0xFF80541A)),),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(6),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),),
        Expanded(child: ListView(
            key: const Key('weekly-labor-tasks-scroll-only'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Row(children: [
                Expanded(child: Text('Unpaid work · ' + tasks.length.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),),),
                TextButton(
                  onPressed: tasks.isEmpty ? null : _selectAll,
                  child: Text(tasks.isNotEmpty &&
                    tasks.every((t) => _selected.containsKey(_id(t)),)
                      ? 'Clear All' : 'Select All',),
                ),
              ],),
              if (paidTaskCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline,
                      size: 16, color: Color(0xFF167A54),),
                    const SizedBox(width: 5),
                    Expanded(child: Text(
                      '$paidTaskCount paid task allocation(s) moved to history',
                      style: const TextStyle(fontSize: 11.5,
                        color: Color(0xFF167A54),),),),
                    if (widget.embedded)
                      TextButton(
                        key: const Key('view-paid-tasks-in-reports'),
                        onPressed: () => DefaultTabController.of(context).animateTo(2),
                        child: const Text('View Paid Tasks'),),
                  ],),
                ),
              if (tasks.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(_future
                    ? 'Future weeks show no earned payroll. Planned work '
                      'requires scheduling data.'
                    : paidTaskCount > 0
                      ? 'All work shown for this week is already paid. '
                        'See Reports → Payroll History.'
                      : 'No unpaid labor for this week.',
                    style: const TextStyle(color: Color(0xFF64748B)),),),
              if (pending.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Assigned work', style: TextStyle(fontWeight: FontWeight.bold),),
                ),
              for (final task in [...pending, ...tasks])
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
                            _choose(task,v==true);
                          }),
                      ),
                      Expanded(child:InkWell(
                        onTap:()=>setState((){
                          if(!_expandedTasks.add(_id(task))) {
                            _expandedTasks.remove(_id(task));
                          }
                        }),
                        child:Padding(
                          padding:const EdgeInsets.symmetric(vertical:9,),
                          child:Column(
                            crossAxisAlignment:CrossAxisAlignment.start,
                            children:[
                              Text((task['description'] ?? 'Task').toString(),
                                maxLines:_expandedTasks.contains(_id(task))
                                  ? null:2,
                                overflow:_expandedTasks.contains(_id(task))
                                  ? TextOverflow.visible:TextOverflow.ellipsis,
                                style:const TextStyle(fontWeight:FontWeight.w700,),),
                              Text((task['job_number']?.toString() ?? 'Job')+' · '+_statusLabel(task)+' · '+
                                (task['state'] == 'Done'
                                  ? _available(task,).toStringAsFixed(2) + ' unpaid hrs'
                                  : _assigned(task,).toStringAsFixed(2) + ' actual hrs'),
                                style:const TextStyle(fontSize:11,
                                  color:Color(0xFF64748B),),),
                              if (_paidHours(task) > 0)
                                const Text('Partially Paid · Remaining hours only',
                                  style: TextStyle(fontSize: 11,
                                    color: Color(0xFF167A54),
                                    fontWeight: FontWeight.w700,),),
                              const SizedBox(height: 2),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _expandedTasks.contains(_id(task))
                                      ? 'Tap to collapse' : 'Tap to expand',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF64748B),),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),),
                      Text((_selected[_id(task)] ?? _assigned(task))
                        .toStringAsFixed(2)+'h',
                        style:const TextStyle(fontWeight:FontWeight.bold,),),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        tooltip: 'Edit payable hours',
                        onPressed: _saving || _available(task) <= 0 ? null : () => _editHours(task),
                      ),
                      const SizedBox(width:6),
                    ],),
                    if(_expandedTasks.contains(_id(task)))
                      Padding(
                        padding:const EdgeInsets.fromLTRB(50,0,14,12),
                        child:Column(children:[
                          const Divider(height:12),
                          _detailHours('Customer billed',
                            task['source_invoice_hours'] is num
                              ? (task['source_invoice_hours'] as num).toDouble()
                              : null,),
                          _detailHours('Mechanic assigned',_assigned(task),),
                          _detailHours('Previously paid',_paidHours(task),),
                          _detailHours('Remaining to pay',_available(task),
                      ),
                  ],),
                ),
            ],
          ),
                    ),
                ],
              ),),
        // Approved fixed footer: only the task-list above scrolls.
        Container(
          key: const Key('weekly-labor-fixed-footer'),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFD6E0E8))),),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 9,),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F6F7),
                borderRadius: BorderRadius.circular(10),),
              child: Row(children: [
                Expanded(child: Column(children: [
                  const Text('Tasks selected', style: TextStyle(
                    fontSize: 10.5, color: Color(0xFF64748B),),),
                  const SizedBox(height: 3),
                  Text(_selected.length.toString() +
                    ' of ' + tasks.length.toString(),
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,),),
                ],),),
                Expanded(child: Column(children: [
                  const Text('Selected this week', style: TextStyle(
                    fontSize: 10.5, color: Color(0xFF64748B),),),
                  const SizedBox(height: 3),
                  Text(_totalHours.toStringAsFixed(2) + ' hrs',
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF00897B),),),
                ],),),
                Expanded(child: Column(children: [
                  const Text('Available hours', style: TextStyle(
                    fontSize: 10.5, color: Color(0xFF64748B),),),
                  const SizedBox(height: 3),
                  Text(tasks.fold<double>(0, (sum, task) =>
                    sum + _available(task),).toStringAsFixed(2) + ' hrs',
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,),),
                ],),),
              ],),
            ),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: _saving ? null : () => widget.onCancel == null
                  ? Navigator.pop(context, false)
                  : widget.onCancel!(),
                child: const Text('Cancel'),),),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: _saving || _future || (_totalHours <= 0 && widget.weeklyBaseCents <= 0) ? null : _verifyPayment,
                child: const Text('Verify Payment'),),
        ),
      ],),
                ],
              ),
            ),
          ],
        ),),
    );
  }
}


typedef _PayrollPreparation = ({int adjustment, int repayment, String reason});

class _PayrollPreparationEditor extends StatefulWidget {
  const _PayrollPreparationEditor({
    super.key,
    required this.initial,
    required this.gross,
    required this.debt,
    required this.onCancel,
    required this.onApply,
    this.enabled = true,
  });

  final _PayrollPreparation initial;
  final int gross;
  final int? debt;
  final VoidCallback onCancel;
  final ValueChanged<_PayrollPreparation> onApply;
  final bool enabled;

  @override
  State<_PayrollPreparationEditor> createState() => _PayrollPreparationEditorState();
}

class _PayrollPreparationEditorState extends State<_PayrollPreparationEditor> {
  late final TextEditingController _adjustment;
  late final TextEditingController _repayment;
  late final TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    _adjustment = TextEditingController(text: _dollars(widget.initial.adjustment));
    _repayment = TextEditingController(text: _dollars(widget.initial.repayment));
    _reason = TextEditingController(text: widget.initial.reason);
  }

  @override
  void dispose() {
    _adjustment.dispose();
    _repayment.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _dollars(int cents) => (cents / 100).toStringAsFixed(2);

  int? _cents(String text) {
    final input = text.trim();
    if (input.isEmpty) return 0;
    if (!RegExp(r'^[+-]?(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(input)) {
      return null;
    }
    final amount = double.tryParse(input);
    if (amount == null || !amount.isFinite || amount.abs() > 1000000) return null;
    return (amount * 100).round();
  }

  Widget _amountField(String label, TextEditingController controller, {bool signed = false}) {
    return _field(
      label,
      controller,
      keyboard: TextInputType.numberWithOptions(decimal: true, signed: signed),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboard}) {
    return TextField(
      controller: controller,
      enabled: widget.enabled,
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adjustment = _cents(_adjustment.text);
    final repayment = _cents(_repayment.text);
    final reason = _reason.text.trim();
    final debt = widget.debt;
    final net = widget.gross + (adjustment ?? 0) - (repayment ?? 0);
    final preparation = adjustment != null &&
        repayment != null &&
        repayment >= 0 &&
        debt != null &&
        repayment <= debt &&
        net >= 0 &&
        (adjustment == 0 || reason.isNotEmpty)
        ? (adjustment: adjustment, repayment: repayment, reason: reason)
        : null;
    final money = NumberFormat.simpleCurrency(locale: 'en_US');
    final payAdjustment = _amountField(
      'Pay adjustment (+/−)',
      _adjustment,
      signed: true,
    );
    final payRepayment = _amountField(
      'Repayment amount',
      _repayment,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 320 &&
                MediaQuery.textScalerOf(context).scale(14) <= 16) {
              return Row(children: [
                Expanded(child: payAdjustment),
                const SizedBox(width: 8),
                Expanded(child: payRepayment),
              ]);
            }
            return Column(children: [
              payAdjustment,
              const SizedBox(height: 8),
              payRepayment,
            ]);
          },
        ),
        const SizedBox(height: 10),
        _field('Reason for pay adjustment', _reason),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F7DE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            preparation != null
                ? 'Payment Total: ${money.format(net / 100)}'
                : 'Check the amounts, outstanding balance and adjustment reason.',
            style: const TextStyle(fontWeight: FontWeight.w800, color: taskGreen),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: taskGreen),
              onPressed: preparation != null && widget.enabled
                  ? () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      widget.onApply(preparation);
                      widget.onCancel();
                    }
                  : null,
              child: const Text('Apply to payment'),
            ),
          ],
        ),
      ],
    );
  }
}
