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
    required this.employeeName,
    required this.tasks,
    required this.advanceBalance,
    required this.recordPayment,
    required this.week,
    this.embedded = false,
    this.profileLayout = false,
    this.paymentHistory = const [],
    this.savedRateCents,
    this.reviewMessage,
    this.extra,
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
  final String? reviewMessage;
  final Widget? extra;
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
      DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  static DateTime _end(DateTime date) =>
      _start(date).add(const Duration(days: 5));
  static String _id(Map<String, dynamic> task) => task['id'] as String;
  static double _assigned(Map<String, dynamic> task) =>
      (task['actual_minutes'] as int) / 60;
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
    }
    final available = {
      for (final task in _eligible)
        if (_available(task) > 0) _id(task): _available(task),
    };
    _selected.removeWhere((id, _) => !available.containsKey(id));
    _selected.updateAll((id, requested) => requested.clamp(0.0, available[id]!).toDouble());
  }

  void _selectUnpaid() {
    _preparedAdjustment=0;_preparedRepayment=0;_preparedReason='';
    _selected.clear();
    for (final task in _eligible) {
      final remaining = _available(task);
      if (remaining > 0) _selected[_id(task)] = remaining;
    }
  }

  List<Map<String, dynamic>> get _eligible {
    if (_future) return const [];
    return widget.tasks.where((task) {
      final date = DateTime.tryParse(task['completed_date']?.toString() ?? '');
      // Archived historical labor remains visible elsewhere, but must NEVER
      // become selectable for new payroll without explicit Owner carry-forward.
      final carry=DateTime.tryParse(task['carry_week']?.toString()??'');
      if(carry!=null && carry.isAfter(_start(_week)))return false;
      if(widget.profileLayout && _rate(task)<=0)return false;
      if (task['archived_labor']==1 || task['assignment_conflict']==1 ||
          task['state'] != 'Done' || date == null || !date.isBefore(_end(_week))) {
        return false;
      }
      return task['paid'] != 1 || !date.isBefore(_start(_week));
    }).toList();
  }

  static double _available(Map<String, dynamic> task) =>
      task['paid'] == 1 || task['state'] != 'Done' ? 0 :
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
    if (_saving || _available(task) <= 0) return;
    final input = TextEditingController(text:
      (_selected[_id(task)] ?? _available(task)).toStringAsFixed(2));
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Mechanic Labor'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _detailHours('Mechanic actual', _assigned(task)),
          _detailHours('Previously paid', _paidHours(task)),
          _detailHours('Remaining to pay', _available(task)),
          const SizedBox(height: 12),
          TextField(
            controller: input,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onTapAlwaysCalled: true,
            onTap: () => input.selection = TextSelection(
              baseOffset: 0, extentOffset: input.text.length,
            ),
            decoration: const InputDecoration(
              labelText: 'Hours to pay this week', border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final hours = double.tryParse(input.text.trim());
              if (hours == null || !hours.isFinite || hours <= 0) return;
              final minutes = (hours * 60).round();
              if (minutes <= 0 || minutes > (_available(task) * 60).round()) return;
              Navigator.pop(context, minutes);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (minutes != null && mounted) setState(() => _selected[_id(task)] = minutes / 60);
    Future<void>.delayed(const Duration(milliseconds: 400), input.dispose);
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
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (value == null || !mounted) { return; }
    setState(() => _week = value);
    widget.onWeekChanged?.call(_week);
    if (mounted) setState(_selectUnpaid);
  }

  Future<void> _verifyPayment() async {
    if (_saving || _future || (_totalHours <= 0 && widget.weeklyBaseCents <= 0)) return;
    setState(() { _saving = true; _error = null; });
    late final int debt;
    try {
      debt = await widget.advanceBalance();
    } catch (error) {
      if (mounted) setState(() { _saving = false; _error = error.toString(); });
      return;
    }
    if (!mounted) return;
    final week = _start(_week);
    final selected = [
      for (final task in _eligible)
        if (_selected.containsKey(_id(task)) && _available(task) > 0)
          {...task, 'pay_minutes': (_selected[_id(task)]! * 60).round(),
            if (widget.settlementRateCents != null) 'payment_rate_cents': widget.settlementRateCents},

    ];
    final laborCents = selected.fold<int>(0, (sum, task) {
      final paid = task['paid_minutes'] as int? ?? 0;
      final minutes = task['pay_minutes'] as int;
      final rate = widget.settlementRateCents ?? task['payment_rate_cents'] as int? ?? task['rate_cents'] as int? ?? 0;
      // Older widget fixtures provide a total but real records carry the rate.
      if (!task.containsKey('rate_cents')) return sum + (task['gross_cents'] as int);
      return sum + (((paid + minutes) * rate + 30) ~/ 60) - ((paid * rate + 30) ~/ 60);
    });
    final hours = selected.fold<int>(0, (sum, task) => sum + (task['pay_minutes'] as int)) / 60;
    final totalMinutes = selected.fold<int>(0, (sum, task) => sum + (task['pay_minutes'] as int));
    if (widget.requiredSupplementMinutes != null && totalMinutes != widget.requiredSupplementMinutes) {
      setState(() {
        _saving = false;
        _error = 'Select exactly ${(widget.requiredSupplementMinutes! / 60).toStringAsFixed(2)} approved supplemental hours.';
      });
      return;
    }
    final calculatedGross = laborCents + widget.weeklyBaseCents + widget.weeklyAdjustmentCents;
    final amount=TextEditingController(
      text:((calculatedGross+_preparedAdjustment)/100).toStringAsFixed(2));
    final debtInput=TextEditingController(text:_preparedRepayment>0?(_preparedRepayment/100).toStringAsFixed(2):'');
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
          title:const Text('Verify Payment'),
          content:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text(widget.employeeName+' · Week of '+
                DateFormat('MMM d, yyyy').format(week)),
              Text(selected.length.toString()+' tasks · '+
                hours.toStringAsFixed(2)+' hours'),
              const SizedBox(height:10),
              if (widget.weeklyBaseCents > 0)
                Text('Weekly base: ${(widget.weeklyBaseCents / 100).toStringAsFixed(2)}'),
              Text(r'Calculated labor: $'+(laborCents/100).toStringAsFixed(2)),
              if (widget.weeklyAdjustmentCents != 0)
                Text('Weekly adjustment: ${(widget.weeklyAdjustmentCents / 100).toStringAsFixed(2)}'),
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
              ),
              ListTile(
                title: const Text('Payment date'),
                subtitle: Text(DateFormat.yMMMd().format(paidDate)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialog, initialDate: paidDate,
                    firstDate: DateTime(2020), lastDate: DateTime.now(),
                  );
                  if (date != null && dialog.mounted) update(() => paidDate = date);
                },
              ),
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
                    : Icons.keyboard_arrow_down),
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
                      color:Color(0xFF64748B))),
                  CheckboxListTile(
                    dense:true,contentPadding:EdgeInsets.zero,
                    value:deduct,
                    title:const Text('Deduct from employee debt'),
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
                    onTapAlwaysCalled:true,
                    onTap:()=>debtInput.selection=TextSelection(
                      baseOffset:0,extentOffset:debtInput.text.length),
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
                      (gross-calculatedGross/100).toStringAsFixed(2)),
                    Text(r'Send employee: $'+
                      (gross-repayment).toStringAsFixed(2),
                      style:const TextStyle(fontWeight:FontWeight.w800)),
                  ]);
              }),
              const SizedBox(height:9),
              TextField(controller:note,maxLines:2,
                decoration:const InputDecoration(
                  labelText:'Payment note or adjustment reason',
                  border:OutlineInputBorder())),
              const SizedBox(height:7),
              const Text('This records the payment in Briskers.',
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
                (repayment*100).round()>debt) {return;}
              if ((gross * 100).round() != calculatedGross && note.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Enter a reason for the gross adjustment.'),
                ));
                return;
              }
              Navigator.pop(dialog,true);
            },child:const Text('Record payment')),
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
          DateTime.parse(task['completed_date'] as String).isBefore(week));
        final reason = [
          if (carryForward) 'Prior unpaid work carried forward.',
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
                    hours.toStringAsFixed(2)+' hrs'),
                  Text(r'Gross compensation: $'+
                    (grossCents/100).toStringAsFixed(2)),
                  Text(r'Debt repayment: $'+
                    (debtCents/100).toStringAsFixed(2)),
                  Text(r'Transferred: $'+
                    ((grossCents - debtCents)/100).toStringAsFixed(2),
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
              setState((){_selected.clear();_preparedAdjustment=0;_preparedRepayment=0;_preparedReason='';});
              await widget.onPaymentSaved?.call();
            } else {
              Navigator.pop(context,true);
            }
          }
        }
      } on PayrollAlreadyRecorded catch (error) {
        if (mounted) setState(() { _error = error.message; _selected.clear(); });
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
          if (mounted) setState(_selectUnpaid);
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

  Future<void> _restoreDraft() async {
    if(!widget.profileLayout || widget.loadDraft==null)return;
    final week=_start(_week);
    final Map<String,dynamic>? savedDraft;
    try { savedDraft=await widget.loadDraft!(week); } catch(error) {
      if(mounted)setState(()=>_error='Could not load the saved draft: $error');
      return;
    }
    if(!mounted || _start(_week)!=week || savedDraft==null)return;
    final available={for(final r in _eligible) _id(r):_available(r)};
    setState(() { _selected.clear(); _preparedAdjustment=savedDraft['adjustment'] as int? ?? 0;_preparedRepayment=savedDraft['repayment'] as int? ?? 0;_preparedReason=savedDraft['reason'] as String? ?? '';
      for(final entry in (savedDraft['hours'] as Map).entries) {
      final remaining=available[entry.key]??0;
      if(remaining>0 && entry.value>0)_selected[entry.key]=(entry.value as num).clamp(0,remaining).toDouble();
    }});
  }
  Future<void> _editPreparation(int labor) async {
    final debt=await widget.advanceBalance();
    if(!mounted)return;
    final adjustment=TextEditingController(text:(_preparedAdjustment/100).toStringAsFixed(2));
    final repayment=TextEditingController(text:(_preparedRepayment/100).toStringAsFixed(2));
    final reason=TextEditingController(text:_preparedReason);
    final saved=await showDialog<bool>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update){
      final a=double.tryParse(adjustment.text),r=double.tryParse(repayment.text);
      final valid=a!=null&&r!=null&&a.isFinite&&r.isFinite&&a.abs()<=1000000&&r>=0&&(r*100).round()<=debt&&labor+(a*100).round()>=(r*100).round()&&(a==0||reason.text.trim().isNotEmpty);
      return AlertDialog(title:const Text('Adjustments & repayment'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Outstanding advance: \$${(debt/100).toStringAsFixed(2)}'),
        TextField(controller:adjustment,keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true),decoration:const InputDecoration(labelText:'Adjustment (+/−)'),onChanged:(_)=>update((){})),
        TextField(controller:repayment,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Repayment from this payment'),onChanged:(_)=>update((){})),
        TextField(controller:reason,decoration:const InputDecoration(labelText:'Adjustment reason'),onChanged:(_)=>update((){})),
        if(valid)Text('Payment Total: \$${((labor+(a*100).round()-(r*100).round())/100).toStringAsFixed(2)}'),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel')),FilledButton(onPressed:valid?()=>Navigator.pop(dialog,true):null,child:const Text('Apply'))]);
    }));
    if(saved==true&&mounted)setState((){_preparedAdjustment=(double.parse(adjustment.text)*100).round();_preparedRepayment=(double.parse(repayment.text)*100).round();_preparedReason=reason.text.trim();});
    Future<void>.delayed(const Duration(milliseconds:400),(){adjustment.dispose();repayment.dispose();reason.dispose();});
  }
  int _rate(Map<String,dynamic> task)=>widget.settlementRateCents ?? task['payment_rate_cents'] as int? ?? task['rate_cents'] as int? ?? 0;
  int _amount(Map<String,dynamic> task,double hours) {
    final paid=task['paid_minutes'] as int? ?? 0, minutes=(hours*60).round(),rate=_rate(task);
    return ((paid+minutes)*rate+30)~/60-(paid*rate+30)~/60;
  }
  Widget _profileBody() {
    final tasks=_eligible.where((r)=>_available(r)>0 && _rate(r)>0).toList();
    final start=_start(_week),end=_end(_week);
    final dated=widget.tasks.where((r){final d=DateTime.tryParse((r['carry_week']??r['completed_date']??r['invoice_date'])?.toString()??'');return d!=null&&!d.isBefore(start)&&d.isBefore(end);}).toList();
    final review=dated.where((r)=>r['assignment_conflict']==1 || r['archived_labor']==1 || (r['state']=='Done'&&r['paid']!=1&&_rate(r)<=0)).toList();
    final paid=widget.paymentHistory.where((p)=>p['week']==start.toIso8601String().substring(0,10)).expand((p)=>(p['work'] as List? ?? []).whereType<Map>().map(Map<String,dynamic>.from)).toList();
    final labor=tasks.fold<int>(widget.weeklyBaseCents,(n,r)=>n+_amount(r,_selected[_id(r)]??0));
    final adjustment=widget.weeklyAdjustmentCents+_preparedAdjustment,gross=labor+widget.weeklyAdjustmentCents+_preparedAdjustment;
    final net=gross-_preparedRepayment;
    final total=tasks.fold<double>(0,(n,r)=>n+_available(r));
    String money(int n)=>NumberFormat.simpleCurrency(locale:'en_US').format(n/100);
    Widget metric(String label,String value,Color color)=>Expanded(child:Container(padding:const EdgeInsets.all(10),margin:const EdgeInsets.all(3),decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(14)),child:Column(children:[Text(label,textAlign:TextAlign.center),Text(value,textAlign:TextAlign.center,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800))])));
    Widget summary(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[Expanded(child:Text(label)),Text(value,style:const TextStyle(fontWeight:FontWeight.w800))]));
    return ListView(key:const Key('employee-payroll-preparation'),padding:const EdgeInsets.all(12),children:[
      Card(child:_compactWeekSelector()),
      Row(children:[metric('Unpaid Labor','${total.toStringAsFixed(2)} hrs',const Color(0xFFEAF3FF)),metric('Saved Rate',widget.savedRateCents==null?'Not saved':'${money(widget.savedRateCents!)} / hr',const Color(0xFFEAF8EF)),metric('Selected Gross',money(gross),const Color(0xFFF2ECFF))]),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
      Card(child:Column(children:[ListTile(title:Text('Unpaid Labor (${tasks.length})',style:const TextStyle(fontWeight:FontWeight.w800)),trailing:TextButton(onPressed:tasks.isEmpty?null:_selectAll,child:const Text('Select All'))),
        if(tasks.isEmpty)const ListTile(title:Text('No verified unpaid labor for this week.')),
        for(final r in tasks)CheckboxListTile(key:ValueKey('payable-${_id(r)}'),value:_selected.containsKey(_id(r)),onChanged:_saving?null:(v)=>setState((){if(v==true){_selected[_id(r)]=_available(r);}else{_selected.remove(_id(r));}}),
          title:Text('${r['job_number']??'Job'} · ${r['customer_name']??''}',style:const TextStyle(fontWeight:FontWeight.w800)),
          subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${r['description']??'Labor'}'),Text(r['carry_week']!=null?'Completed · Warranty rework · Carry-forward':'Completed · Unpaid'),
            TextButton(onPressed:_saving?null:()=>_editHours(r),child:Text('${(_selected[_id(r)]??_available(r)).toStringAsFixed(2)} h · ${money(_amount(r,_selected[_id(r)]??_available(r)))}'))]),controlAffinity:ListTileControlAffinity.leading),
      ])),
      if(review.isNotEmpty || widget.reviewMessage!=null)Card(child:ExpansionTile(title:Text('Needs Review (${review.length})'),children:[
        if(widget.reviewMessage!=null)ListTile(title:Text(widget.reviewMessage!)),
        for(final r in review)ListTile(title:Text('${r['job_number']} · ${r['description']}'),subtitle:const Text('Pay status or compensation requires review; excluded from payment.'))])),
      if(paid.isNotEmpty)Card(child:ExpansionTile(title:const Text('Previously Paid Work'),children:[for(final r in paid)ListTile(title:Text('${r['job_number']} · ${r['description']}'),subtitle:Text('${((r['actual_minutes'] as int? ?? 0)/60).toStringAsFixed(2)} hrs · Paid · selected week'))])),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[summary('Total Selected Hours','${_totalHours.toStringAsFixed(2)} hrs'),summary('Labor Pay',money(labor)),summary('Adjustments (+/−)',money(adjustment)),summary('Gross Pay',money(gross)),summary('Advance repayment',money(_preparedRepayment)),summary('Payment Total',money(net)),
        TextButton(onPressed:_saving?null:()=>_editPreparation(labor+widget.weeklyAdjustmentCents),child:const Text('Adjustments & repayment'))]))),
      if(widget.extra!=null)widget.extra!,
      Wrap(spacing:10,runSpacing:8,alignment:WrapAlignment.spaceBetween,children:[OutlinedButton(onPressed:_saving||widget.saveDraft==null?null:()async {await widget.saveDraft!(_start(_week),Map<String,double>.from(_selected),_preparedAdjustment,_preparedRepayment,_preparedReason);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Payroll draft saved locally.')));},child:const Text('Save (Draft)')),
        FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF0A8F53)),onPressed:_saving||_future||gross<=0||net<0||(_totalHours<=0&&widget.weeklyBaseCents<=0)?null:_verifyPayment,icon:const Icon(Icons.check),label:const Text('Verify Weekly Payment'))]),
    ]);
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
              'Select the work to include in this week.',
              style: TextStyle(fontSize: 11.5,
                color: Color(0xFF80541A))),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(6),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
        Expanded(child: ListView(
            key: const Key('weekly-labor-tasks-scroll-only'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Row(children: [
                Expanded(child: Text('Unpaid work · ' + tasks.length.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
                TextButton(
                  onPressed: tasks.isEmpty ? null : _selectAll,
                  child: Text(tasks.isNotEmpty &&
                    tasks.every((t) => _selected.containsKey(_id(t)))
                      ? 'Clear All' : 'Select All'),
                ),
              ]),
              if (paidTaskCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline,
                      size: 16, color: Color(0xFF167A54)),
                    const SizedBox(width: 5),
                    Expanded(child: Text(
                      '$paidTaskCount paid task allocation(s) moved to history',
                      style: const TextStyle(fontSize: 11.5,
                        color: Color(0xFF167A54)))),
                    if (widget.embedded)
                      TextButton(
                        key: const Key('view-paid-tasks-in-reports'),
                        onPressed: () => DefaultTabController.of(context).animateTo(2),
                        child: const Text('View Paid Tasks')),
                  ]),
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
                    style: const TextStyle(color: Color(0xFF64748B)))),
              if (pending.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Assigned work', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              Text((task['description'] ?? 'Task').toString(),
                                maxLines:_expandedTasks.contains(_id(task))
                                  ? null:2,
                                overflow:_expandedTasks.contains(_id(task))
                                  ? TextOverflow.visible:TextOverflow.ellipsis,
                                style:const TextStyle(fontWeight:FontWeight.w700)),
                              Text((task['job_number']?.toString() ?? 'Job')+' · '+_statusLabel(task)+' · '+
                                (task['state'] == 'Done'
                                  ? _available(task).toStringAsFixed(2) + ' unpaid hrs'
                                  : _assigned(task).toStringAsFixed(2) + ' actual hrs'),
                                style:const TextStyle(fontSize:11,
                                  color:Color(0xFF64748B))),
                              if (_paidHours(task) > 0)
                                const Text('Partially Paid · Remaining hours only',
                                  style: TextStyle(fontSize: 11,
                                    color: Color(0xFF167A54),
                                    fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _expandedTasks.contains(_id(task))
                                      ? 'Tap to collapse' : 'Tap to expand',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                      Text((_selected[_id(task)] ?? _assigned(task))
                        .toStringAsFixed(2)+'h',
                        style:const TextStyle(fontWeight:FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        tooltip: 'Edit payable hours',
                        onPressed: _saving || _available(task) <= 0 ? null : () => _editHours(task),
                      ),
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
                          _detailHours('Previously paid',_paidHours(task)),
                          _detailHours('Remaining to pay',_available(task)),
                        ]),
                      ),
                  ]),
                ),
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
                onPressed: _saving ? null : () => widget.onCancel == null
                  ? Navigator.pop(context, false)
                  : widget.onCancel!(),
                child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: _saving || _future || (_totalHours <= 0 && widget.weeklyBaseCents <= 0) ? null : _verifyPayment,
                child: const Text('Verify Payment'))),
            ]),
          ]),
        ),
      ])),
    );
  }
}
