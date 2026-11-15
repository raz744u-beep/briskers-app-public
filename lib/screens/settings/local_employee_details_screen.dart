import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/connection_mode.dart';
import '../../core/formatters.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/employee_nickname_store.dart';
import '../../services/local_employee_details.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/secure_employee_details_cache.dart';
import '../payroll/approved_tasks_ui.dart';

class LocalEmployeeDetailsScreen extends StatefulWidget {
  const LocalEmployeeDetailsScreen({
    super.key,
    required this.businessId,
    required this.employeeId,
    this.rosterName,
    this.rosterPosition,
    this.nicknameStore,
    this.unlockOwner,
    this.currentOwner,
  });
  final String businessId, employeeId;
  final String? rosterName, rosterPosition;
  final EmployeeNicknameStore? nicknameStore;
  final Future<LocalOwnerGrant> Function(String)? unlockOwner;
  final OwnerSessionIdentity? Function()? currentOwner;
  @override
  State<LocalEmployeeDetailsScreen> createState() =>
      _LocalEmployeeDetailsScreenState();
}

class _LocalEmployeeDetailsScreenState
    extends State<LocalEmployeeDetailsScreen> {
  static const cache = SecureEmployeeDetailsCache();
  Map<String, dynamic> details = {}, pending = {};
  String nickname = '', message = '';
  String? localPayType;
  int? localPayCents;
  List<String> conflicts = [];
  LocalOwnerGrant? grant;
  bool busy = false, editing = false;
  Timer? timer;
  final _editControllers = <TextEditingController>[];
  late final nicknames = widget.nicknameStore ?? EmployeeNicknameStore();
  @override
  void initState() {
    super.initState();
    unawaited(load());
    BriskersConnectionModeController.instance.addListener(connectionChanged);
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (grant != null) {
        try {
          grant!.assertValid(widget.businessId, grant!.actorId);
        } catch (_) {
          if (mounted) {
            setState(() {
              grant = null;
              details = {};
              pending = {};
              conflicts = [];
              localPayType = null;
              localPayCents = null;
              for (final controller in _editControllers) {
                controller.clear();
              }
              message =
                  'Owner session ended. Sign in to view protected details.';
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final controller in _editControllers) {
      controller.dispose();
    }
    BriskersConnectionModeController.instance.removeListener(connectionChanged);
    super.dispose();
  }

  void connectionChanged() {
    if (!BriskersConnectionModeController.instance.forceOffline && !editing) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    if (busy) return;
    busy = true;
    try {
      final access =
          await (widget.unlockOwner?.call(widget.businessId) ??
              DeviceOwnerAuthorization.instance.authority.authorizeSession(
                widget.businessId,
              ));
      grant = access;
      await readLocal();
      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await LocalEmployeeDetails(nicknameStore: nicknames).sync(
            widget.businessId,
            widget.employeeId,
            access,
          );
          await readLocal();
          conflicts = [];
        } on EmployeeDetailsConflict catch (error) {
          if (mounted) {
            setState(() {
              message = error.message;
              conflicts = error.fields;
            });
          }
        } catch (_) {
          if (mounted) {
            await readLocal();
            setState(
              () => message =
                  'Saved details remain available. Connect as Owner and tap Refresh / Sync to load or send existing employee information.',
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Sign in as Owner to access saved employee details.',
        );
      }
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> readLocal() async {
    final value = await cache.read(
      widget.businessId,
      widget.employeeId,
      grant!,
    );
    final repo = LocalPayrollRepository(
      localDatabase,
      business: widget.businessId,
      owner: true,
      assertOwnerGrant: () =>
          grant!.assertValid(widget.businessId, grant!.actorId),
    );
    final employee = (await repo.employees())
        .where((row) => row['id'] == widget.employeeId)
        .firstOrNull;
    final defaults = await repo.weeklyDefaults(widget.employeeId);
    String? savedAlias;
    try {
      savedAlias = await nicknames.get(widget.businessId, widget.employeeId);
    } catch (_) {
      // A nickname storage failure cannot hide protected employee details.
    }
    grant!.assertValid(widget.businessId, grant!.actorId);
    if (!mounted) return;
    final savedDetails = Map<String, dynamic>.from(value?['details'] as Map? ?? {});
    final verifiedType = savedDetails['payment_type']?.toString();
    final verifiedRate = num.tryParse(
      '${savedDetails[verifiedType == 'fixed_weekly' ? 'weekly_rate' : 'hourly_rate'] ?? ''}',
    );
    setState(() {
      localPayType = verifiedType == 'hourly' || verifiedType == 'fixed_weekly'
          ? verifiedType
          : employee == null
          ? null
          : employee['base_enabled'] == 1
          ? 'fixed_weekly'
          : 'hourly';
      localPayCents = verifiedRate != null
          ? (verifiedRate * 100).round()
          : employee == null
          ? null
          : localPayType == 'fixed_weekly'
          ? (defaults?['base_cents'] as int?)
          : (employee['rate'] as int?);
      details = savedDetails;
      pending = Map<String, dynamic>.from(value?['pending'] as Map? ?? {});
      final syncedAlias = savedDetails['nickname']?.toString() ?? '';
      nickname = savedDetails.containsKey('nickname') &&
              (syncedAlias.isNotEmpty || pending.containsKey('nickname') ||
                  (savedAlias ?? '').isEmpty)
          ? syncedAlias
          : savedAlias ?? '';
      message = value == null
          ? 'Contact and tax details are not saved locally yet. The existing server record has not been removed.'
          : pending.isEmpty
          ? 'Employee details are saved securely on this device.'
          : 'Saved on this device · ${pending.length} field(s) awaiting sync.';
    });
  }

  String value(String key, {String fallback = 'Not saved locally'}) {
    final v = details[key];
    return v == null || '$v'.trim().isEmpty ? fallback : '$v';
  }

  Future<void> reviewConflicts() async {
    if (grant == null || editing || busy) return;
    editing = true;
    try {
      BriskersConnectionModeController.instance.ensureNetworkAllowed();
      final remote = await const LocalEmployeeDetails().remoteDetail(
        widget.businessId, widget.employeeId, grant!,
      );
      grant!.assertValid(widget.businessId, grant!.actorId);
      final reviewed = {
        for (final key in conflicts)
          if (SecureEmployeeDetailsCache.editable.contains(key) &&
              pending.containsKey(key))
            key: pending[key],
      };
      if (!mounted || reviewed.isEmpty) return;
      final keepLocal = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Review employee changes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose which values to keep. Other fields and saved payments remain unchanged.',
                ),
                for (final field in reviewed.keys)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${field.replaceAll('_', ' ')}\nThis device: ${reviewed[field] ?? '(empty)'}\nServer: ${remote[field] ?? '(empty)'}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Use server values'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Keep local edits'),
            ),
          ],
        ),
      );
      if (keepLocal != null) {
        await cache.resolveConflict(
          widget.businessId,
          widget.employeeId,
          remote,
          reviewed,
          keepLocal,
          grant!,
        );
        if (!keepLocal && reviewed.containsKey('nickname')) {
          await nicknames.save(
            widget.businessId, widget.employeeId,
            remote['nickname']?.toString() ?? '',
          );
        }
        if (!keepLocal &&
            reviewed.keys.any(
              (key) =>
                  ['payment_type', 'hourly_rate', 'weekly_rate'].contains(key),
            )) {
          final type = remote['payment_type'];
          final amount = num.tryParse(
            '${remote[type == 'fixed_weekly' ? 'weekly_rate' : 'hourly_rate']}',
          );
          if (['hourly', 'fixed_weekly'].contains(type) && amount != null) {
            await LocalPayrollRepository(
              localDatabase,
              business: widget.businessId,
              owner: true,
              assertOwnerGrant: () =>
                  grant!.assertValid(widget.businessId, grant!.actorId),
            ).saveLocalPayBasis(
              employee: widget.employeeId,
              name: remote['name'] as String,
              paymentType: type as String,
              amountCents: (amount * 100).round(),
            );
          }
        }
        await readLocal();
        conflicts = [];
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Changes are still saved on this device. Reconnect and review again.',
        );
      }
    } finally {
      editing = false;
    }
    if (mounted) await load();
  }

  Future<void> editDetails({bool nicknameOnly = false}) async {
    if (grant == null || editing) return;
    grant!.assertValid(widget.businessId, grant!.actorId);
    final fields = {
      for (final k in ['name', 'phone', 'email', 'address'])
        if (details.containsKey(k))
          k: TextEditingController(text: details[k]?.toString() ?? ''),
    };
    final alias = TextEditingController(text: nickname);
    var payType = details['payment_type']?.toString() ?? 'hourly';
    if (!['hourly', 'fixed_weekly'].contains(payType)) payType = 'hourly';
    final payRate = TextEditingController(
      text: localPayCents == null
          ? '${details[payType == 'hourly' ? 'hourly_rate' : 'weekly_rate'] ?? ''}'
          : (localPayCents! / 100).toStringAsFixed(2),
    );
    var method = details['default_payment_method']?.toString() ?? '';
    final initialPayType = payType;
    final initialAmount = num.tryParse(payRate.text);
    _editControllers.addAll([...fields.values, alias, payRate]);
    final form = GlobalKey<FormState>();
    var active = details['active'] == true;
    var position = details['position_id']?.toString();
    final positions = List<Map<String, dynamic>>.from(
      (details['positions'] as List? ?? []).map(
        (v) => Map<String, dynamic>.from(v as Map),
      ),
    );
    editing = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          titlePadding: EdgeInsets.zero,
          contentPadding: EdgeInsets.fromLTRB(16, nicknameOnly ? 12 : 16, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF2787B9), Color(0xFF123B78)]),
            ),
            child: Row(children: [
              const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 9),
              Expanded(child: Text(nicknameOnly ? 'Edit Nickname' : 'Edit Details',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19))),
            ]),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!nicknameOnly && details.isEmpty)
                    const Text(
                      'Connect once to securely save the existing employee profile. Unknown fields cannot be replaced with a blank profile.',
                    ),
                  if (!nicknameOnly)
                    for (final entry in fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextFormField(
                          controller: entry.value,
                          keyboardType: entry.key == 'phone'
                              ? TextInputType.phone
                              : entry.key == 'email'
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          maxLines: entry.key == 'address' ? 3 : 1,
                          decoration: InputDecoration(
                            labelText: switch (entry.key) {
                              'name' => 'Full name',
                              'phone' => 'Phone',
                              'email' => 'Email',
                              _ => 'Address',
                            },
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (entry.key == 'name' &&
                                (v ?? '').trim().isEmpty) {
                              return 'Enter a name';
                            }
                            if (entry.key == 'phone' &&
                                (v ?? '').isNotEmpty &&
                                digitsOnly(v!).length != 10) {
                              return 'Enter a 10-digit phone';
                            }
                            return null;
                          },
                        ),
                      ),
                  if (!nicknameOnly &&
                      positions.any((v) => v['id'] == position))
                    DropdownButtonFormField<String>(
                      initialValue: position,
                      decoration: const InputDecoration(labelText: 'Position'),
                      items: [
                        for (final p in positions)
                          DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(p['name']?.toString() ?? 'Position'),
                          ),
                      ],
                      onChanged: (v) => update(() => position = v),
                    ),
                  if (!nicknameOnly && details.containsKey('active'))
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active employee'),
                      value: active,
                      onChanged: (v) => update(() => active = v),
                    ),
                  if (!nicknameOnly && details['compensation_enabled'] == true &&
                      details.containsKey('payment_type')) ...[
                    DropdownButtonFormField<String>(
                      initialValue: payType,
                      decoration: const InputDecoration(labelText: 'Payment type'),
                      items: const [
                        DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                        DropdownMenuItem(value: 'fixed_weekly', child: Text('Fixed weekly')),
                      ],
                      onChanged: (v) => update(() {
                        payType = v!;
                        payRate.text = '${details[v == 'hourly' ? 'hourly_rate' : 'weekly_rate'] ?? ''}';
                      }),
                    ),
                    TextFormField(
                      controller: payRate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: payType == 'hourly' ? 'Hourly rate' : 'Weekly pay',
                        prefixText: r'$ ',
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty &&
                            initialAmount == null && payType == initialPayType) {
                          return null; // Preserve an existing unknown rate.
                        }
                        final amount = num.tryParse(v ?? '');
                        return amount == null || !amount.isFinite || amount < 0 ||
                                amount > 1000000 || ((amount * 100).round() - amount * 100).abs() > 0.00001
                            ? 'Enter a valid amount with at most two decimals'
                            : null;
                      },
                    ),
                  ],
                  if (!nicknameOnly && details.containsKey('default_payment_method'))
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(labelText: 'Default payment method'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Not set')),
                        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'Zelle', child: Text('Zelle')),
                        DropdownMenuItem(value: 'Check', child: Text('Check')),
                        DropdownMenuItem(value: 'ACH', child: Text('ACH')),
                        DropdownMenuItem(value: 'Card', child: Text('Card')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) => update(() => method = v ?? ''),
                    ),
                  TextFormField(
                    controller: alias,
                    maxLength: 32,
                    decoration: const InputDecoration(
                      labelText: 'Nickname (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Text(
                    'Saved locally. Existing payments and paid hours stay unchanged.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(dialog, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    try {
      if (saved == true) {
        final payEnabled = !nicknameOnly && details['compensation_enabled'] == true &&
            details.containsKey('payment_type');
        final amount = payEnabled ? num.tryParse(payRate.text) : null;
        final payChanged = payEnabled &&
            (payType != initialPayType ||
                (amount == null ? initialAmount != null :
                    initialAmount == null ||
                    (amount * 100).round() != (initialAmount * 100).round()));
        final patch = <String, dynamic>{
          if (!nicknameOnly &&
              details.containsKey('active') &&
              active != details['active'])
            'active': active,
          if (!nicknameOnly && position != details['position_id'])
            'position_id': position,
          if (!nicknameOnly)
            for (final e in fields.entries)
              if (e.value.text.trim() != (details[e.key]?.toString() ?? ''))
                e.key: e.key == 'phone'
                    ? digitsOnly(e.value.text)
                    : e.value.text.trim(),
          if (payChanged) ...{
            'payment_type': payType,
            'hourly_rate': payType == 'hourly' ? amount : null,
            'weekly_rate': payType == 'fixed_weekly' ? amount : null,
          },
          if (!nicknameOnly && details.containsKey('default_payment_method') &&
              (method.isEmpty ? null : method) != details['default_payment_method'])
            'default_payment_method': method.isEmpty ? null : method,
          if (details.containsKey('nickname') && alias.text.trim() != nickname)
            'nickname': alias.text.trim(),
        };
        if (patch.isNotEmpty) {
          await cache.edit(widget.businessId, widget.employeeId, patch, grant!);
        }
        if (payChanged) {
          await LocalPayrollRepository(
            localDatabase,
            business: widget.businessId,
            owner: true,
            assertOwnerGrant: () => grant!.assertValid(widget.businessId, grant!.actorId),
          ).saveLocalPayBasis(
            employee: widget.employeeId,
            name: fields['name']?.text.trim().isNotEmpty == true
                ? fields['name']!.text.trim()
                : value('name', fallback: widget.rosterName ?? 'Employee'),
            paymentType: payType,
            amountCents: (amount! * 100).round(),
          );
        }
        grant!.assertValid(widget.businessId, grant!.actorId);
        await nicknames.save(widget.businessId, widget.employeeId, alias.text);
        if (mounted) setState(() => nickname = alias.text.trim());
        await readLocal();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              message = 'Could not save changes. Check Owner access and retry.',
        );
      }
    } finally {
      editing = false;
    }
    if (saved == true &&
        !BriskersConnectionModeController.instance.forceOffline) {
      await load();
    }
  }

  Future<void> editPay() async {
    if (grant == null) return;
    var type = localPayType ?? value('payment_type', fallback: 'hourly');
    if (!['hourly', 'fixed_weekly'].contains(type)) type = 'hourly';
    final amount = TextEditingController(
      text: localPayCents == null
          ? value(
              type == 'hourly' ? 'hourly_rate' : 'weekly_rate',
              fallback: '',
            )
          : (localPayCents! / 100).toStringAsFixed(2),
    );
    _editControllers.add(amount);
    final form = GlobalKey<FormState>();
    editing = true;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Employee payment settings'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Payment type'),
                  items: const [
                    DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                    DropdownMenuItem(
                      value: 'fixed_weekly',
                      child: Text('Fixed weekly'),
                    ),
                  ],
                  onChanged: (v) => update(() => type = v!),
                ),
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: type == 'hourly' ? 'Hourly rate' : 'Weekly pay',
                    prefixText: r'$ ',
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || !n.isFinite || n < 0 || n > 1000000
                        ? 'Enter a valid amount'
                        : null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(dialog, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    try {
      if (save == true) {
        final n = double.parse(amount.text);
        final repo = LocalPayrollRepository(
          localDatabase,
          business: widget.businessId,
          owner: true,
          assertOwnerGrant: () =>
              grant!.assertValid(widget.businessId, grant!.actorId),
        );
        if (details.isNotEmpty) {
          await cache.edit(widget.businessId, widget.employeeId, {
            'payment_type': type,
            'hourly_rate': type == 'hourly' ? n : null,
            'weekly_rate': type == 'fixed_weekly' ? n : null,
          }, grant!);
        }
        await repo.saveLocalPayBasis(
          employee: widget.employeeId,
          name: value('name', fallback: widget.rosterName ?? 'Employee'),
          paymentType: type,
          amountCents: (n * 100).round(),
        );
        await readLocal();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Pay settings require review. Saved payments were not changed.',
        );
      }
    } finally {
      editing = false;
    }
    if (save == true &&
        !BriskersConnectionModeController.instance.forceOffline) {
      await load();
    }
  }

  Widget section(String title, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    elevation: 2,
    shadowColor: const Color(0x40051D35),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: const BorderSide(color: Color(0xFFE0E4ED)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF237BAA), Color(0xFF194781)],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 23),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(children: children),
        ),
      ],
    ),
  );
  Widget detail(
    String label,
    String text,
    IconData icon, {
    VoidCallback? onTap,
    Color? color,
    bool inline = false,
  }) => inline
      ? InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: taskNavy, size: 21),
                const SizedBox(width: 10),
                SizedBox(
                  width: 87,
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 14, color: color ?? taskNavy),
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, size: 19),
              ],
            ),
          ),
        )
      : ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          minLeadingWidth: 22,
          horizontalTitleGap: 7,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: taskNavy, size: 21),
          title: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: color == null ? FontWeight.w400 : FontWeight.w700,
              color: color ?? taskNavy,
            ),
          ),
          onTap: onTap,
        );
  @override
  Widget build(BuildContext context) {
    final name = value('name', fallback: widget.rosterName ?? 'Employee');
    final option = (details['positions'] as List? ?? [])
        .where((p) => p['id'] == details['position_id'])
        .firstOrNull;
    final role =
        option?['name']?.toString() ??
        value(
          'position',
          fallback: widget.rosterPosition ?? 'Position unavailable',
        );
    final fixed = (localPayType ?? details['payment_type']) == 'fixed_weekly';
    final rate = localPayCents == null
        ? num.tryParse(
            value(fixed ? 'weekly_rate' : 'hourly_rate', fallback: ''),
          )
        : localPayCents! / 100;
    return Scaffold(
      backgroundColor: taskCanvas,
      appBar: const ApprovedTasksHeader(title: 'Employee Details'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFE0F2F6),
                child: Icon(Icons.build_outlined, color: taskGreen, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname.isEmpty ? name : nickname,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (nickname.isNotEmpty) Text(name),
                    Wrap(
                      spacing: 6,
                      children: [
                        Text(role),
                        if (details.containsKey('active'))
                          Text(
                            details['active'] == false ? 'Inactive' : 'Active',
                            style: const TextStyle(
                              color: taskGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: grant == null ? null : () => editDetails(),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Details'),
            ),
          ),
          if (conflicts.isNotEmpty)
            OutlinedButton.icon(
              onPressed: reviewConflicts,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Review conflicting changes'),
            ),
          section('Employment & Pay', Icons.work_outline, [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      detail(
                        'Payment Type',
                        details['payment_type'] == null
                            ? 'Not saved locally'
                            : fixed
                            ? 'Fixed weekly'
                            : 'Hourly',
                        Icons.person_outline,
                        onTap: grant != null && details.isNotEmpty
                            ? editPay
                            : null,
                      ),
                      detail(
                        fixed ? 'Weekly pay' : 'Hourly rate',
                        rate == null
                            ? 'Not saved locally'
                            : '\$${rate.toStringAsFixed(2)} / ${fixed ? 'week' : 'hr'}',
                        Icons.payments_outlined,
                        color: taskGreen,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      detail(
                        'Default Payment Method',
                        value('default_payment_method'),
                        Icons.credit_card,
                        onTap: grant != null &&
                                details.containsKey('default_payment_method')
                            ? () => editDetails()
                            : null,
                      ),
                      detail('Position', role, Icons.engineering_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ]),
          section('Contact Information', Icons.badge_outlined, [
            detail('Phone', value('phone'), Icons.phone_outlined, inline: true),
            const Divider(height: 1),
            detail('Email', value('email'), Icons.mail_outline, inline: true),
            const Divider(height: 1),
            detail(
              'Address',
              value('address'),
              Icons.location_on_outlined,
              inline: true,
            ),
          ]),
          section('Tax Information', Icons.description_outlined, [
            detail(
              'SSN (Last 4)',
              inline: true,
              details['ssn_last4'] == null
                  ? 'Not saved locally'
                  : '***-**-${details['ssn_last4']}',
              Icons.badge_outlined,
            ),
            const Divider(height: 1),
            detail(
              'W-9 Status',
              inline: true,
              value('w9_status', fallback: 'Not verified'),
              Icons.description_outlined,
            ),
          ]),
          section('Other', Icons.settings_outlined, [
            detail(
              'Nickname',
              inline: true,
              nickname.isEmpty ? 'Not set' : nickname,
              Icons.sell_outlined,
              onTap: grant == null
                  ? null
                  : () => editDetails(nicknameOnly: true),
            ),
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE6ECF6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: taskBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(message, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.sync),
              label: const Text('Refresh / Sync'),
            ),
          ),
        ],
      ),
    );
  }
}
