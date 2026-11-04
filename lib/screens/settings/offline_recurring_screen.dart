import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/connection_mode.dart';
import '../../core/supabase_config.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_financial_cache.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/offline_recurring_repository.dart';
import '../../services/offline_financial_write_service.dart';
import '../../services/recurring_financial_projection.dart';
import '../../services/recurring_recovery_service.dart';
import '../../services/recurring_rpc_transport.dart';
import '../../services/recurring_sync_service.dart';
import '../expenses/expense_detail_screen.dart';

class OfflineRecurringScreen extends StatefulWidget {
  const OfflineRecurringScreen({super.key, required this.businessId});
  final String businessId;
  @override
  State<OfflineRecurringScreen> createState() => _OfflineRecurringScreenState();
}

class _OfflineRecurringScreenState extends State<OfflineRecurringScreen> {
  LocalOwnerGrant? _grant;
  OfflineRecurringRepository? _repository;
  List<RecurringRow> _rules = [];
  List<RecurringRow> _occurrences = [];
  Map<String, dynamic> _options = {};
  String? _message;
  bool _busy = false;
  Timer? _lockTimer;
  static const _transport = RecurringRpcTransport();

  @override
  void initState() {
    super.initState();
    _lockTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _busy || _grant == null || _authorized()) return;
      setState(() { _rules = []; _occurrences = []; _grant = null; });
    });
  }

  @override
  void dispose() { _lockTimer?.cancel(); super.dispose(); }

  bool _authorized() {
    try {
      final grant = _grant;
      if (grant == null) return false;
      grant.assertValid(widget.businessId, supabase.auth.currentUser?.id ?? '');
      return true;
    } on StateError { return false; }
  }

  Future<void> _run(Future<void> Function(OfflineRecurringRepository) action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (!_authorized()) {
        _grant = await DeviceOwnerAuthorization.instance.authority.authorizeLocal(widget.businessId);
      }
      if (!mounted) return;
      final user = _grant!.actorId;
      final repo = OfflineRecurringRepository(database: localDatabase,
        businessId: widget.businessId, userId: user,
        currentUserId: () => supabase.auth.currentUser?.id,
        canRead: _authorized, canWrite: _authorized,
        projectOccurrence: RecurringFinancialProjection(widget.businessId).call);
      _repository = repo;
      await action(repo);
      final rules = await repo.rules();
      final occurrences = await repo.occurrences();
      final options = await LocalFinancialCache().loadOptions(widget.businessId);
      if (!mounted || !_authorized()) return;
      setState(() { _rules = rules; _occurrences = occurrences; _options = options; });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(OfflineRecurringRepository repo) async {
    final counts = await RecurringRecoveryService(repository: repo,
      database: localDatabase, readSnapshot: _transport.readSnapshot,
      currentUserId: () => supabase.auth.currentUser?.id, canRead: _authorized).download();
    _message = 'Saved ${counts.schedules} schedules and ${counts.occurrences} expenses on this device.';
  }

  Future<void> _generate(OfflineRecurringRepository repo) async {
    // Explicit shop date avoids using UTC or a travelling phone's date silently.
    final today = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: today,
      firstDate: DateTime(2000), lastDate: DateTime(today.year + 1),
      helpText: 'Create due expenses through this shop date');
    if (date == null) return;
    final count = await repo.generateThrough(OfflineRecurringRepository.dateText(date));
    _message = '$count expenses created locally. Reopen Expenses to view them.';
  }

  Future<void> _sync(OfflineRecurringRepository repo) async {
    final count = await RecurringSyncService(database: localDatabase, repository: repo,
      writeBundle: _transport.writeBundle,
      synchronizationAllowed: () => !BriskersConnectionModeController.instance.forceOffline,
    ).flush();
    _message = '$count expenses reconciled. Refresh complete financial totals when online.';
  }

  Future<void> _edit(RecurringRow? row) async {
    if (_repository == null) return;
    final edited = await showDialog<RecurringRow>(context: context,
      builder: (_) => _RuleEditor(businessId: widget.businessId, rule: row, options: _options));
    if (edited != null) await _run((repo) => repo.saveRule(edited));
  }

  Future<void> _correct(RecurringRow row) async {
    final controller = TextEditingController(text: ((row['amount_minor'] as int) / 100).toStringAsFixed(2));
    final text = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Correct this expense amount'),
      content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save'))],
    ));
    controller.dispose();
    if (text != null) {
      await _run((repo) => repo.correctAmount(
        row['recurring_rule_id'] as String, row['recurring_occurrence_date'] as String, _minor(text)));
    }
  }

  Future<void> _attach(RecurringRow row) async {
    final source = await showDialog<ImageSource>(context: context, builder: (context) => SimpleDialog(
      title: const Text('Attach receipt'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, ImageSource.camera), child: const Text('Take photo')),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, ImageSource.gallery), child: const Text('Choose photo')),
      ]));
    if (source == null) return;
    final photo = await ImagePicker().pickImage(source: source);
    if (photo == null || !mounted) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    await _run((_) => OfflineFinancialWriteService().attachRecurringReceipts(
      widget.businessId, row['id'] as String, receipts: [{
        'filename': photo.name, 'mime_type': photo.mimeType ?? 'image/jpeg', 'bytes': bytes,
      }], assertAuthorized: () {
        if (!_authorized()) throw StateError('Owner access expired.');
      }));
  }

  Future<void> _resolve(RecurringRow row, bool rule) async {
    final server = row['_server'] as Map?;
    final useServer = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Review recurring conflict'),
      content: SingleChildScrollView(child: Text(
        'Local amount: ${row['amount_minor']} cents\nServer amount: ${server?['amount_minor']} cents\n'
        'Local next/date: ${row['next_date'] ?? row['date']}\n'
        'Server next/date: ${server?['next_date'] ?? server?['date']}\n'
        'Local active: ${row['is_repeating']}\nServer active: ${server?['is_repeating']}\n\n'
        'Local frequency: ${row['frequency']} / ${row['interval_count']}\n'
        'Server frequency: ${server?['frequency']} / ${server?['interval_count']}\n'
        'Local account: ${row['account'] ?? row['account_id']}\n'
        'Server account: ${server?['account'] ?? server?['account_id']}\n'
        'Local category: ${row['category'] ?? row['category_id']}\n'
        'Server category: ${server?['category'] ?? server?['category_id']}\n'
        'Local payee: ${row['counterparty'] ?? row['vendor_id']}\n'
        'Server payee: ${server?['counterparty'] ?? server?['vendor_id']}\n'
        'Local remarks: ${row['remarks'] ?? ''}\nServer remarks: ${server?['remarks'] ?? ''}\n\n'
        'Keep local preserves your values for the next sync. Use server replaces this local record.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep local')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use server'))],
    ));
    if (useServer != null) {
      await _run((repo) => repo.resolveConflict(rule: rule,
        key: row['_key'] as String, revision: row['_revision'] as int, useServer: useServer));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recurring transactions')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy ? null : () => _run((_) async {}), child: const Text('Open saved schedules')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_download), child: const Text('Download existing')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_generate), child: const Text('Create due expenses')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_sync), child: const Text('Sync recurring only')),
      ]),
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text(
        'Download uses internet without enabling general sync. Schedule changes and due expenses save locally.')),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Padding(padding: const EdgeInsets.all(8), child: Text(_message!)),
      if (_authorized()) ...[
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: _busy ? null : () => _edit(null), icon: const Icon(Icons.add), label: const Text('New recurring'))),
        for (final row in _rules) Card(child: ListTile(
          title: Text('${row['counterparty'] ?? row['category'] ?? 'Recurring'} · '
            '\$${((row['amount_minor'] as int) / 100).toStringAsFixed(2)}'),
          subtitle: Text('${row['frequency']} · Next ${row['next_date']} · '
            '${row['is_repeating'] == true ? row['_state'] : 'Stopped'}'
            '${row['paused_reason'] == null ? '' : ' · ${row['paused_reason']}'}'),
          onTap: _busy ? null : () => row['_state'] == 'conflict' ? _resolve(row, true) : _edit(row),
          trailing: IconButton(tooltip: 'Stop repeating', icon: const Icon(Icons.stop_circle_outlined),
            onPressed: _busy || row['is_repeating'] != true || row['_state'] == 'conflict'
              ? null : () => _run((repo) => repo.saveRule({...row, 'is_repeating': false}))),
        )),
        const Padding(padding: EdgeInsets.only(top: 16), child: Text('Generated expenses')),
        for (final row in _occurrences.reversed) ListTile(
          title: Text('${row['date']} · \$${((row['amount_minor'] as int) / 100).toStringAsFixed(2)}'),
          subtitle: Text('${row['counterparty'] ?? ''} · ${row['_state']}'),
          onTap: _busy ? null : () async {
            if (row['_state'] == 'conflict') { await _resolve(row, false); return; }
            final detail = await LocalFinancialCache().loadTransactionDetail(widget.businessId, row['id'] as String);
            if (!context.mounted || !_authorized()) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ExpenseDetailScreen(
              businessId: widget.businessId, transactionId: row['id'] as String,
              cachedDetail: detail, allowRecurring: false)));
          },
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Attach receipt', icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: _busy ? null : () => _attach(row)),
            IconButton(tooltip: 'Correct amount', icon: const Icon(Icons.edit_outlined),
              onPressed: _busy || row['_state'] == 'conflict' ? null : () => _correct(row)),
          ]),
        ),
      ],
    ]),
  );
}

int _minor(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) throw const FormatException('Enter a positive amount with at most two decimals.');
  final parts = text.split('.');
  final result = int.parse(parts[0]) * 100 + (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  if (result <= 0) throw const FormatException('Amount must be positive.');
  return result;
}

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({required this.businessId, required this.rule, required this.options});
  final String businessId;
  final RecurringRow? rule;
  final Map<String, dynamic> options;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final amount = TextEditingController(text: widget.rule == null ? '' : ((widget.rule!['amount_minor'] as int)/100).toStringAsFixed(2));
  late final date = TextEditingController(text: widget.rule?['next_date'] as String? ?? OfflineRecurringRepository.dateText(DateTime.now()));
  late final end = TextEditingController(text: widget.rule?['end_date'] as String? ?? '');
  late final remarks = TextEditingController(text: widget.rule?['remarks'] as String? ?? '');
  late final interval = TextEditingController(text: '${widget.rule?['interval_count'] ?? 1}');
  late String frequency = widget.rule?['frequency'] as String? ?? 'weekly';
  late String direction = widget.rule?['direction'] as String? ?? 'expense';
  late String? account = widget.rule?['account_id'] as String?;
  late String? category = widget.rule?['category_id'] as String?;
  late String? vendor = widget.rule?['vendor_id'] as String?;
  late bool active = widget.rule?['is_repeating'] as bool? ?? true;
  String? error;
  @override
  void dispose() { for (final c in [amount,date,end,remarks,interval]) { c.dispose(); } super.dispose(); }
  List<RecurringRow> options(String key) => [for (final r in widget.options[key] as List? ?? [])
    if (r is Map && r['active'] != false) Map<String,dynamic>.from(r)];
  Widget select(String label, String key, String? selected, void Function(String?) changed) {
    final rows = options(key);
    if (selected != null && !rows.any((r) => r['id'] == selected)) {
      rows.add({'id': selected, 'name': 'Saved $label'});
    }
    return DropdownButtonFormField<String>(initialValue: selected, isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final r in rows) DropdownMenuItem(value: r['id'] as String,
        child: Text('${r['name'] ?? r['label'] ?? r['id']}'))], onChanged: changed);
  }
  void save() {
    try {
      if (account == null || category == null) throw StateError('Select an account and category. Download existing data first if the lists are empty.');
      OfflineRecurringRepository.day(date.text.trim());
      if (end.text.trim().isNotEmpty) OfflineRecurringRepository.day(end.text.trim());
      OfflineRecurringRepository.nextDate(date.text.trim(), frequency, int.parse(interval.text));
      String? name(String key, String? id) => options(key).where((r) => r['id'] == id).firstOrNull?['name'] as String?;
      Navigator.pop(context, <String,dynamic>{
        if (widget.rule != null) ...widget.rule!,
        'id': widget.rule?['id'] ?? _uuid(), 'business_id': widget.businessId,
        'direction': direction, 'account_id': account, 'category_id': category,
        'vendor_id': vendor, 'account': name('accounts',account), 'category': name('categories',category),
        'counterparty': name('counterparties',vendor), 'amount_minor': _minor(amount.text),
        'frequency': frequency, 'interval_count': int.parse(interval.text),
        'next_date': date.text.trim(), 'end_date': end.text.trim().isEmpty ? null : end.text.trim(),
        'remarks': remarks.text.trim(), 'is_repeating': active,
      });
    } catch (e) { setState(() => error = e.toString()); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.rule == null ? 'New recurring transaction' : 'Edit recurring transaction'),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(initialValue: direction, decoration: const InputDecoration(labelText: 'Type'),
        items: [for (final v in ['expense','income']) DropdownMenuItem(value:v,child:Text(v))], onChanged:(v)=>setState(()=>direction=v!)),
      select('Account','accounts',account,(v)=>setState(()=>account=v)),
      select('Category','categories',category,(v)=>setState(()=>category=v)),
      select('Payee','counterparties',vendor,(v)=>setState(()=>vendor=v)),
      TextField(controller:amount,decoration:const InputDecoration(labelText:'Amount'),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
      DropdownButtonFormField<String>(initialValue:frequency,decoration:const InputDecoration(labelText:'Frequency'),
        items:[for(final v in ['daily','weekly','monthly','yearly']) DropdownMenuItem(value:v,child:Text(v))],onChanged:(v)=>setState(()=>frequency=v!)),
      TextField(controller:interval,decoration:const InputDecoration(labelText:'Every (number of periods)'),keyboardType:TextInputType.number),
      TextField(controller:date,decoration:const InputDecoration(labelText:'Next date (YYYY-MM-DD)')),
      TextField(controller:end,decoration:const InputDecoration(labelText:'End date (optional, YYYY-MM-DD)')),
      TextField(controller:remarks,decoration:const InputDecoration(labelText:'Remarks')),
      SwitchListTile(title:const Text('Repeating'),value:active,onChanged:(v)=>setState(()=>active=v)),
      if(error!=null) Text(error!),
    ]))),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:save,child:const Text('Save locally'))],
  );
}
