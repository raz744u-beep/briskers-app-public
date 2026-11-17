import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/connection_mode.dart';
import '../../core/formatters.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/briskers_api.dart';
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
    if (mounted) setState(() {});
    if (!BriskersConnectionModeController.instance.forceOffline && !editing) {
      unawaited(load());
    }
  }

  String syncFailure(Object error) {
    if (error is PostgrestException) {
      final code = error.code;
      if (code == 'P0002') {
        return 'This employee ID was not found in the connected shop. Existing local records are unchanged. Contact support before editing this profile.';
      }
      if (code == '42501' || code == 'PGRST301') {
        return 'The server did not authorize this Owner session. Sign in again as Owner, then tap Refresh / Sync. Existing local records are unchanged.';
      }
      return 'Could not load existing employee information (server code ${code ?? 'unknown'}). Check the Owner connection and tap Refresh / Sync. Existing records are unchanged.';
    }
    if (error is StateError && '$error'.contains('identity differs')) {
      return 'The employee ID does not match the server profile. Existing records are unchanged. Contact support before editing.';
    }
    return 'Could not load existing employee information. Check the Owner connection and tap Refresh / Sync. Existing records are unchanged.';
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
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
        } catch (error) {
          if (mounted) {
            await readLocal();
            setState(() => message = syncFailure(error));
          }
        }
      } else if (mounted && details.isEmpty) {
        setState(() => message =
            'Turn off Force Offline, then tap Load Existing Details once. No existing employee information has been changed.');
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

  String employeePhone(String raw) {
    final digits = digitsOnly(raw);
    if (digits.length == 10) return formatUsPhone(digits);
    if (digits.length == 11 && digits.startsWith('1')) {
      return '1-${formatUsPhone(digits.substring(1))}';
    }
    return raw;
  }

  Future<void> openAddress() async {
    final address = value('address', fallback: '').trim();
    if (grant == null || address.isEmpty) return;
    grant!.assertValid(widget.businessId, grant!.actorId);
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1', 'query': address,
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No maps app available');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open this address in Maps.'),
        ));
      }
    }
  }

  Future<void> showSsn() async {
    if (grant == null || busy || details.isEmpty) return;
    if (BriskersConnectionModeController.instance.forceOffline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Full SSN needs an online Owner connection. The last four digits remain available offline.'),
      ));
      return;
    }
    setState(() => busy = true);
    try {
      grant!.assertValid(widget.businessId, grant!.actorId);
      BriskersConnectionModeController.instance.ensureNetworkAllowed();
      final ssn = await const BriskersApi().revealEmployeeSsn(
        widget.businessId, widget.employeeId,
      );
      grant!.assertValid(widget.businessId, grant!.actorId);
      if (!mounted) return;
      final digits = digitsOnly(ssn ?? '');
      if (digits.length != 9) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No full SSN is available for this employee.'),
        ));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Employee SSN'),
          content: Text('${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          actions: [TextButton(
            onPressed: () => Navigator.pop(dialog), child: const Text('Hide'),
          )],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Owner verification could not reveal the SSN. Reconnect and try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          k: TextEditingController(text: k == 'phone'
              ? employeePhone(details[k]?.toString() ?? '')
              : details[k]?.toString() ?? ''),
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
    Widget groupTitle(String title, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF24558D)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF173E71),
        )),
      ]),
    );
    InputDecoration editorField(String label, {String? prefixText}) =>
        InputDecoration(
          labelText: label,
          prefixText: prefixText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: const OutlineInputBorder(),
        );
    editing = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          titlePadding: EdgeInsets.zero,
          contentPadding: EdgeInsets.fromLTRB(16, nicknameOnly ? 18 : 16, 16, 12),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!nicknameOnly) groupTitle('Contact Information', Icons.badge_outlined),
                  if (!nicknameOnly)
                    for (final entry in fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          controller: entry.value,
                          keyboardType: entry.key == 'phone'
                              ? TextInputType.phone
                              : entry.key == 'email'
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          inputFormatters: entry.key == 'phone'
                              ? const [WarrantyPhoneTextInputFormatter()] : null,
                          maxLines: entry.key == 'address' ? 2 : 1,
                          decoration: editorField(switch (entry.key) {
                              'name' => 'Full name',
                              'phone' => 'Phone',
                              'email' => 'Email',
                              _ => 'Address',
                            }),
                          validator: (v) {
                            if (entry.key == 'name' &&
                                (v ?? '').trim().isEmpty) {
                              return 'Enter a name';
                            }
                            if (entry.key == 'phone' &&
                                (v ?? '').isNotEmpty &&
                                !(digitsOnly(v!).length == 10 ||
                                  (digitsOnly(v).length == 11 && digitsOnly(v).startsWith('1')))) {
                              return 'Enter a 10-digit phone (or 1 + 10 digits)';
                            }
                            return null;
                          },
                        ),
                      ),
                  if (!nicknameOnly) groupTitle('Employment', Icons.work_outline),
                  if (!nicknameOnly &&
                      positions.any((v) => v['id'] == position))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: DropdownButtonFormField<String>(
                        initialValue: position,
                        isExpanded: true,
                        decoration: editorField('Position'),
                        items: [
                          for (final p in positions)
                            DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(p['name']?.toString() ?? 'Position'),
                            ),
                        ],
                        onChanged: (v) => update(() => position = v),
                      ),
                    ),
                  if (!nicknameOnly && details.containsKey('active'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Material(
                        color: const Color(0xFFF2F6FA),
                        borderRadius: BorderRadius.circular(10),
                        child: SwitchListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          title: const Text('Active employee'),
                          value: active,
                          onChanged: (v) => update(() => active = v),
                        ),
                      ),
                    ),
                  if (!nicknameOnly && details['compensation_enabled'] == true &&
                      details.containsKey('payment_type')) ...[
                    groupTitle('Pay Settings', Icons.payments_outlined),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: DropdownButtonFormField<String>(
                        initialValue: payType,
                        isExpanded: true,
                        decoration: editorField('Payment type'),
                        items: const [
                          DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                          DropdownMenuItem(value: 'fixed_weekly', child: Text('Fixed weekly')),
                        ],
                        onChanged: (v) => update(() {
                          payType = v!;
                          payRate.text = '${details[v == 'hourly' ? 'hourly_rate' : 'weekly_rate'] ?? ''}';
                        }),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: payRate,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: editorField(
                          payType == 'hourly' ? 'Hourly rate' : 'Weekly pay',
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
                    ),
                  ],
                  if (!nicknameOnly && details.containsKey('default_payment_method'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: DropdownButtonFormField<String>(
                        initialValue: method,
                        isExpanded: true,
                        decoration: editorField('Default payment method'),
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
                    ),
                  if (!nicknameOnly) groupTitle('Display Name', Icons.sell_outlined),
                  TextFormField(
                    controller: alias,
                    maxLength: 32,
                    decoration: editorField('Nickname (optional)'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    nicknameOnly
                        ? 'Saving a nickname keeps existing payments and paid hours unchanged.'
                        : 'Changes save on this device first. Existing payments and paid hours stay unchanged.',
                    style: const TextStyle(fontSize: 13, height: 1.35),
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
              if ((e.key == 'phone' ? digitsOnly(e.value.text) : e.value.text.trim()) !=
                  (e.key == 'phone' ? digitsOnly(details[e.key]?.toString() ?? '') :
                      details[e.key]?.toString() ?? ''))
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
    bool link = false,
    String? actionLabel,
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
                    style: TextStyle(fontSize: 14, color: link ? taskBlue : color ?? taskNavy,
                      decoration: link ? TextDecoration.underline : null),
                  ),
                ),
                if (actionLabel != null && onTap != null)
                  Text(actionLabel, style: const TextStyle(
                    color: taskBlue, fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ))
                else if (onTap != null)
                  Icon(link ? Icons.open_in_new : Icons.chevron_right, size: 19),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (nickname.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(name),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
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
              onPressed: grant == null || details.isEmpty ? null : () => editDetails(),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Details'),
            ),
          ),
          if (grant != null && details.isEmpty)
            Card(
              color: const Color(0xFFEAF3FA),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Load existing employee details',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(BriskersConnectionModeController.instance.forceOffline
                        ? 'Turn off Force Offline first. This device has not saved the existing profile yet.'
                        : 'Connect as Owner to securely save the existing profile on this device. Empty fields cannot overwrite it.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: busy || BriskersConnectionModeController.instance.forceOffline
                          ? null : load,
                      icon: const Icon(Icons.sync),
                      label: const Text('Load Existing Details'),
                    ),
                  ],
                ),
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
                        'Pay Method',
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
            detail('Phone', employeePhone(value('phone')), Icons.phone_outlined, inline: true),
            const Divider(height: 1),
            detail('Email', value('email'), Icons.mail_outline, inline: true),
            const Divider(height: 1),
            detail(
              'Address',
              value('address'),
              Icons.location_on_outlined,
              inline: true,
              link: value('address', fallback: '').trim().isNotEmpty,
              onTap: value('address', fallback: '').trim().isNotEmpty ? openAddress : null,
            ),
          ]),
          section('Tax Information', Icons.description_outlined, [
            detail(
              'SSN',
              inline: true,
              details['ssn_last4'] == null
                  ? 'Not saved locally'
                  : '***-**-${details['ssn_last4']}',
              Icons.badge_outlined,
              onTap: grant != null && details.isNotEmpty ? showSsn : null,
              actionLabel: grant != null && details.isNotEmpty ? 'Show' : null,
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
