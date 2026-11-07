import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/secure_employee_details_cache.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../local/local_database_provider.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/employee_nickname_store.dart';
import '../payroll/owner_payroll_screen.dart';

class EmployeeEditScreen extends StatefulWidget {
  const EmployeeEditScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    this.employeeId,
    this.rosterName,
    this.rosterPosition,
    this.nicknameStore,
    this.unlockOwner,
    this.currentOwner,
  });

  final String businessId;
  final bool isOwner;
  final String? employeeId;
  final String? rosterName;
  final String? rosterPosition;
  final EmployeeNicknameStore? nicknameStore;
  final Future<LocalOwnerGrant> Function(String)? unlockOwner;
  final OwnerSessionIdentity? Function()? currentOwner;

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  static const _api = BriskersApi();
  late final _nicknameStore = widget.nicknameStore ?? EmployeeNicknameStore();
  OwnerSessionIdentity? _currentOwner(){try{return widget.currentOwner?.call() ?? DeviceOwnerAuthorization.instance.currentIdentity();}catch(_){return null;}}

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _ssn = TextEditingController();
  final _rate = TextEditingController();

  List<Map<String, dynamic>> _positions = const [];
  String? _positionId;
  bool _compensationEnabled = true;
  String _paymentType = 'hourly';
  String? _ssnLast4;
  String? _revealedSsn;
  bool _revealingSsn = false;
  bool _active = true;
  bool _userLinked = false;
  bool _appLoginBusy = false;
  bool _loading = true;
  bool _secureOffline = false;
  String? _localPayType;
  int? _localPayCents;
  bool _savingOfflinePay = false;
  Set<String> _secureKeys={};
  LocalOwnerGrant? _detailsGrant;
  Timer? _privacyTimer;
  OwnerSessionIdentity? _loadedIdentity;
  bool _detailLoaded = false;
  bool _saving = false;
  bool _savingNickname = false;
  String? _error;

  bool get _editing => widget.employeeId != null;

  String get _positionName {
    final id = _positionId;
    if (id == null) return '';
    for (final position in _positions) {
      if (position['id']?.toString() == id) {
        return position['name']?.toString() ?? '';
      }
    }
    return '';
  }

  String? get _appRoleCode {
    switch (_positionName.trim().toLowerCase()) {
      case 'secretary':
        return 'office';
      case 'mechanic':
        return 'mechanic';
      case 'shop foreman':
        return 'manager';
      case 'porter':
        return 'porter';
      default:
        return null;
    }
  }

  String get _appRoleLabel {
    switch (_appRoleCode) {
      case 'office':
        return 'Office / Secretary';
      case 'mechanic':
        return 'Mechanic';
      case 'manager':
        return 'Shop Foreman';
      case 'porter':
        return 'Porter';
      default:
        return 'Not available for this position';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadedIdentity=_currentOwner();
    _name.text=widget.rosterName??'';
    _loading=!_editing;
    unawaited(_hydrateNickname());
    unawaited(_load());
    _privacyTimer=Timer.periodic(const Duration(seconds:2),(_){
      final changed=_loadedIdentity!=null && !_loadedIdentity!.matches(_currentOwner());
      if(changed){
        if(mounted)setState((){_detailLoaded=false;_secureOffline=false;_detailsGrant=null;_phone.clear();_email.clear();_address.clear();_rate.clear();_ssn.clear();_revealedSsn=null;_ssnLast4=null;});
        return;
      }
      if(_detailsGrant==null)return;
      try{_detailsGrant!.assertValid(widget.businessId,_detailsGrant!.actorId);}catch(_){
        if(mounted)setState((){_detailsGrant=null;_secureOffline=false;_phone.clear();_email.clear();_address.clear();_rate.clear();_ssn.clear();_revealedSsn=null;_ssnLast4=null;});
      }
    });
  }

  @override
  void dispose() {
    _privacyTimer?.cancel();
    _name.dispose();
    _nickname.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _ssn.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (BriskersConnectionModeController.instance.forceOffline) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = _editing
              ? null
              : 'Creating employee records is not available in Force Offline.';
        });
        // This Owner is already signed in to Briskers. Read only the existing
        // encrypted employee snapshot and locally configured pay information;
        // never require a second biometric/PIN or a Supabase round trip.
        if (_editing && widget.isOwner) {
          unawaited(_unlockOffline());
        }
        return;
      }
      final positions = await _api.employeePositions(widget.businessId).timeout(const Duration(seconds:8));
      Map<String, dynamic>? employee;
      if (_editing) {
        employee = await _api.employeeSettingsDetail(
          widget.businessId,
          widget.employeeId!,
        ).timeout(const Duration(seconds:8));
      }

      if (!mounted) return;

      if (_editing && employee == null) {
        throw StateError('Employee details could not be loaded.');
      }
      _positions = positions;
      if (employee != null) {
        _name.text = employee['name']?.toString() ?? '';
        _phone.text = formatUsPhone(employee['phone']?.toString() ?? '');
        _email.text = employee['email']?.toString() ?? '';
        _address.text = employee['address']?.toString() ?? '';
        _positionId = employee['position_id']?.toString();
        _compensationEnabled = employee['compensation_enabled'] != false;
        _paymentType =
            employee['payment_type']?.toString() == 'fixed_weekly'
                ? 'fixed_weekly'
                : 'hourly';
        _ssnLast4 = employee['ssn_last4']?.toString();
        _userLinked = employee['user_linked'] == true;

        final rate = _paymentType == 'hourly'
            ? employee['hourly_rate']
            : employee['weekly_rate'];
        if (rate != null) _rate.text = rate.toString();
        _active = employee['active'] != false;
      } else if (_positions.isNotEmpty) {
        _positionId = _positions.first['id']?.toString();
      }

      setState(() {
        _loading = false;
        _detailLoaded = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _hydrateNickname() async {
    if(!_editing)return;
    try {
      final value=await _nicknameStore.get(widget.businessId,widget.employeeId!).timeout(const Duration(seconds:3));
      if(mounted && _nickname.text.isEmpty)setState(()=>_nickname.text=value??'');
    } catch(_){if(mounted)setState(()=>_error='Nickname is not available yet. Known employee details are retained. Retry.');}
  }

  Future<void> _hydrateLocalPayBasis(LocalOwnerGrant grant) async {
    if (!widget.isOwner || widget.employeeId == null) return;
    final repo = LocalPayrollRepository(localDatabase,
      business: widget.businessId, owner: true,
      assertOwnerGrant: () => grant.assertValid(widget.businessId, grant.actorId));
    final employee = (await repo.employees())
      .where((row) => row['id'] == widget.employeeId).firstOrNull;
    final defaults = await repo.weeklyDefaults(widget.employeeId!);
    grant.assertValid(widget.businessId, grant.actorId);
    if (!mounted || employee == null) return;
    final fixed = employee['base_enabled'] == 1;
    final cents = fixed
      ? defaults?['base_cents'] as int? : employee['rate'] as int?;
    setState(() {
      _localPayType = fixed ? 'fixed_weekly' : 'hourly';
      _localPayCents = cents;
      _secureOffline = true;
      _paymentType = _localPayType!;
      if (cents != null) _rate.text = (cents / 100).toStringAsFixed(2);
    });
  }

  Future<void> _editOfflinePayBasis() async {
    if (!widget.isOwner || !_editing || _savingOfflinePay) return;
    try {
      final grant = await (widget.unlockOwner?.call(widget.businessId) ??
        DeviceOwnerAuthorization.instance.authority.authorizeSession(widget.businessId));
      await _hydrateLocalPayBasis(grant);
      if (!mounted) return;
      var type = _localPayType ?? 'hourly';
      final amount = TextEditingController(
        text: _localPayCents == null ? '' :
          (_localPayCents! / 100).toStringAsFixed(2),
      );
      final choice = await showDialog<({String type, int cents})>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: const Text('Employee payment settings'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Payment type'),
                items: const [
                  DropdownMenuItem(value: 'hourly',child: Text('Hourly')),
                  DropdownMenuItem(value: 'fixed_weekly',
                    child: Text('Fixed weekly')),
                ],
                onChanged: (value) {
                  if (value != null) update(() => type = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: type == 'hourly' ? 'Hourly rate' : 'Weekly pay',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 8),
              const Text('Saved on this device for offline Payroll. '
                'Existing paid work is not repriced. Server employee settings '
                'are not updated until a separate verified sync.',
                style: TextStyle(fontSize: 12)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amount.text.trim());
                  if (value == null || !value.isFinite ||
                      value < 0 || value > 1000000) return;
                  Navigator.pop(dialog,
                    (type: type, cents: (value * 100).round()));
                },
                child: const Text('Save offline pay settings'),
              ),
            ],
          ),
        ),
      );
      amount.dispose();
      if (choice == null || !mounted) return;
      setState(() => _savingOfflinePay = true);
      final repo = LocalPayrollRepository(localDatabase,
        business: widget.businessId, owner: true,
        assertOwnerGrant: () => grant.assertValid(widget.businessId, grant.actorId));
      await repo.saveLocalPayBasis(
        employee: widget.employeeId!,
        name: _name.text.trim().isNotEmpty ? _name.text.trim() :
          (widget.rosterName ?? widget.employeeId!),
        paymentType: choice.type,
        amountCents: choice.cents,
      );
      await _hydrateLocalPayBasis(grant);
      if (mounted) setState(() =>
        _error = 'Local pay settings saved. Paid work was not changed.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _savingOfflinePay = false);
    }
  }

  Future<void> _unlockOffline() async {
    if(!widget.isOwner||!_editing)return;
    try{
      final grant=await (widget.unlockOwner?.call(widget.businessId) ?? DeviceOwnerAuthorization.instance.authority.authorizeSession(widget.businessId));
      final snapshot=await const SecureEmployeeDetailsCache().read(widget.businessId,widget.employeeId!,grant);
      if(!mounted)return;
      if(snapshot==null){
        final ledger=LocalPayrollRepository(localDatabase,business:widget.businessId,owner:true,
          assertOwnerGrant:()=>grant.assertValid(widget.businessId,grant.actorId));
        final saved=(await ledger.employees()).where((r)=>r['id']==widget.employeeId).firstOrNull;
        if(!mounted)return;
        setState((){
          _detailsGrant=grant;
          _secureOffline=saved!=null;
          _secureKeys=saved==null?{}:{'hourly_rate'};
          _rate.text=saved==null?'':((saved['rate'] as int)/100).toStringAsFixed(2);
          _error='No verified contact/tax snapshot is saved. This does not mean the record is missing. '
            '${saved==null?'':'Showing the Owner-configured local payroll rate; current server values are unknown.'}';
        });
        await _hydrateLocalPayBasis(grant);
        return;
      }
      final d=snapshot['details'] as Map;
      setState((){_detailsGrant=grant;_secureOffline=true;_secureKeys=d.keys.map((k)=>k.toString()).toSet();
        _phone.text=d['phone']?.toString()??'';_email.text=d['email']?.toString()??'';
        _address.text=d['address']?.toString()??'';_rate.text=(d['hourly_rate']??d['weekly_rate'])?.toString()??'';
        _ssnLast4=d['ssn_last4']?.toString();_error='Verified snapshot: ${snapshot['verified_at']}. Offline copy; current server changes are not known.';});
      await _hydrateLocalPayBasis(grant);
    }catch(e){if(mounted)setState(()=>_error='$e');}
  }

  Future<void> _saveSecureSnapshot() async {
    if(!widget.isOwner||!_detailLoaded||!_editing)return;
    try{
      final grant=await (widget.unlockOwner?.call(widget.businessId) ?? DeviceOwnerAuthorization.instance.authority.authorizeSession(widget.businessId));
      await const SecureEmployeeDetailsCache().save(widget.businessId,widget.employeeId!,{
        'id':widget.employeeId,'name':_name.text,'phone':_phone.text,'email':_email.text,'address':_address.text,
        'position_id':_positionId,'payment_type':_paymentType,'hourly_rate':_paymentType=='hourly'?_rate.text:null,
        'weekly_rate':_paymentType!='hourly'?_rate.text:null,'ssn_last4':_ssnLast4,'active':_active},grant);
      if(mounted)setState(()=>_error='Verified encrypted offline copy saved. Full SSN was not cached.');
    }catch(e){if(mounted)setState(()=>_error='$e');}
  }

  Future<void> _saveNicknameLocally() async {
    if (!widget.isOwner || !_editing || _savingNickname) return;
    setState(() {
      _savingNickname = true;
      _error = null;
    });
    try {
      await _nicknameStore.save(
        widget.businessId, widget.employeeId!, _nickname.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _savingNickname = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneDigits = digitsOnly(_phone.text);
    if (phoneDigits.isNotEmpty && phoneDigits.length != 10) {
      setState(() => _error = 'Phone number must contain 10 digits.');
      return;
    }

    final rate = _compensationEnabled
        ? num.tryParse(_rate.text.trim())
        : null;
    if (_compensationEnabled && rate == null) {
      setState(() => _error = 'Enter a valid pay rate.');
      return;
    }
    if (_positionId == null) {
      setState(() => _error = 'Select a position.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.saveEmployeeSettings(
        widget.businessId,
        employeeId: widget.employeeId,
        name: _name.text.trim(),
        phone: phoneDigits.isEmpty ? null : phoneDigits,
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        positionId: _positionId!,
        compensationEnabled: _compensationEnabled,
        paymentType: _compensationEnabled ? _paymentType : null,
        hourlyRate:
            _compensationEnabled && _paymentType == 'hourly' ? rate : null,
        weeklyRate:
            _compensationEnabled && _paymentType == 'fixed_weekly'
                ? rate
                : null,
        active: _active,
        ssn: _ssn.text.trim().isEmpty ? null : _ssn.text.trim(),
      );
      if (_editing && widget.isOwner) {
        await _nicknameStore.save(
          widget.businessId, widget.employeeId!, _nickname.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatSsn(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 9) return value;
    return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}';
  }

  Future<void> _revealSsn() async {
    final employeeId = widget.employeeId;
    if (!widget.isOwner || employeeId == null) return;

    setState(() {
      _revealingSsn = true;
      _error = null;
    });

    try {
      final ssn = await _api.revealEmployeeSsn(
        widget.businessId,
        employeeId,
      );
      if (!mounted) return;
      setState(() {
        _revealedSsn = ssn;
        if (ssn == null || ssn.isEmpty) {
          _error = 'No SSN is stored for this employee.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _revealingSsn = false);
    }
  }

  Future<void> _sendAppLoginInvite() async {
    final employeeId = widget.employeeId;
    if (!widget.isOwner || employeeId == null || _appLoginBusy) return;

    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid employee email first.');
      return;
    }
    if (_appRoleCode == null) {
      setState(
        () => _error =
            'This employee position does not have a staff app role.',
      );
      return;
    }

    setState(() {
      _appLoginBusy = true;
      _error = null;
    });

    try {
      final result = await _api.inviteEmployeeAppLogin(
        widget.businessId,
        employeeId,
        email: email,
      );
      if (!mounted) return;

      setState(() => _userLinked = true);

      final invited = result['invited'] == true;
      final alreadyLinked = result['already_linked'] == true;
      final message = alreadyLinked
          ? 'App login is already linked.'
          : invited
              ? 'Login invite sent to $email.'
              : 'Existing login linked to this employee.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _appLoginBusy = false);
    }
  }

  Future<void> _createTestLogin() async {
    final employeeId = widget.employeeId;
    if (!widget.isOwner || employeeId == null || _appLoginBusy) return;

    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid employee email first.');
      return;
    }
    if (_appRoleCode == null) {
      setState(
        () => _error =
            'This employee position does not have a staff app role.',
      );
      return;
    }

    final passwordController = TextEditingController();
    bool obscure = true;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create test login'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Set a temporary password for $email. '
                'This test account will be immediately usable without '
                'opening the email invitation.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                autofocus: true,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  helperText: 'At least 8 characters',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = passwordController.text;
                if (value.length < 8) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Create test login'),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();
    if (password == null || !mounted) return;

    setState(() {
      _appLoginBusy = true;
      _error = null;
    });

    try {
      await _api.createEmployeeTestLogin(
        widget.businessId,
        employeeId,
        email: email,
        password: password,
      );
      if (!mounted) return;

      setState(() => _userLinked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Test login ready. Use $email with the temporary password.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _appLoginBusy = false);
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  Widget _cachedDetails() {
    final verified = widget.isOwner && _secureOffline && _detailsGrant != null;
    final rate = verified && _rate.text.trim().isNotEmpty
        ? '\${_rate.text.trim()}/hr' : 'Not saved locally';
    String cachedValue(String field, String value) {
      if (!verified || !_secureKeys.contains(field)) return 'Not saved locally';
      return value.trim().isEmpty ? 'Not recorded' : value.trim();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        ListTile(
          leading: const Icon(Icons.build_outlined, size: 34),
          title: Text(_name.text.isEmpty ? 'Employee' : _name.text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          subtitle: Text(widget.rosterPosition ?? 'Position not saved'),
        ),
        const Divider(height: 24),
        ListTile(
          title: const Text('Hourly rate'),
          trailing: Text(rate, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        ListTile(
          title: const Text('Phone, email and address'),
          subtitle: Text(verified
            ? [cachedValue('phone',_phone.text), cachedValue('email',_email.text),
                cachedValue('address',_address.text)].join(' · ')
            : 'Not saved locally'),
        ),
        ListTile(
          title: const Text('SSN and W-9'),
          subtitle: Text(verified && _ssnLast4 != null
            ? 'SSN ending in $_ssnLast4 · Full SSN remains protected'
            : 'Protected information not saved locally'),
        ),
        const ListTile(
          title: Text('Default payment method'),
          subtitle: Text('Not saved locally'),
        ),
        ListTile(
          title: const Text('Position icon'),
          subtitle: Text(widget.rosterPosition ?? 'Role-based icon'),
        ),
        if (widget.isOwner) ...[
          const Divider(height: 26),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Nickname'),
            subtitle: const Text('Optional display name on this device'),
            children: [
              TextFormField(
                controller: _nickname,
                maxLength: 32,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nickname (optional)'),
              ),
              OutlinedButton.icon(
                onPressed: _savingNickname ? null : _saveNicknameLocally,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save nickname on this device'),
              ),
            ],
          ),
        ],
        if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!,style:const TextStyle(fontSize:12))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Employee Details' : 'Add employee'),
        actions: [
          if(widget.isOwner && _editing && _detailLoaded)IconButton(tooltip:'Save verified offline copy',onPressed:_saveSecureSnapshot,icon:const Icon(Icons.enhanced_encryption_outlined)),
          if (_editing && widget.isOwner && OwnerPayrollScreen.enabled)
            IconButton(
              tooltip: 'Payroll History',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => OwnerPayrollScreen(
                  businessId: widget.businessId, reportsOnly: true,
                  employeeId: widget.employeeId,
                  employeeName: _name.text.isEmpty ? null : _name.text,
                ),
              )),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _editing && !_detailLoaded ? _cachedDetails() : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Personal information',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    validator: _required,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                    ),
                  ),
                  if (_editing && widget.isOwner) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nickname,
                      maxLength: 32,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nickname (optional)',
                        helperText: 'Display alias only; full name stays unchanged.',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _savingNickname ? null : _saveNicknameLocally,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_savingNickname
                          ? 'Saving nickname…'
                          : 'Save nickname on this device'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      const UsPhoneTextInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      hintText: '504-555-1234',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.words,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ssn,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Social Security number',
                      helperText: _ssnLast4 == null
                          ? 'Stored encrypted'
                          : 'Stored: ***-**-$_ssnLast4 • leave blank to keep',
                    ),
                  ),
                  if (_editing && _ssnLast4 != null && widget.isOwner) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _revealedSsn == null
                                    ? 'SSN: ***-**-$_ssnLast4'
                                    : 'SSN: ${_formatSsn(_revealedSsn!)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _revealingSsn
                                  ? null
                                  : (_revealedSsn == null
                                      ? _revealSsn
                                      : () => setState(
                                            () => _revealedSsn = null,
                                          )),
                              icon: _revealingSsn
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _revealedSsn == null
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                              label: Text(
                                _revealedSsn == null ? 'Show' : 'Hide',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Employment',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _positionId,
                    decoration: const InputDecoration(
                      labelText: 'Position',
                    ),
                    items: _positions
                        .map(
                          (position) => DropdownMenuItem<String>(
                            value: position['id'].toString(),
                            child: Text('${position['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _positionId = value),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Track pay'),
                    subtitle: const Text(
                      'Turn this off for owners or anyone whose pay is not tracked here.',
                    ),
                    value: _compensationEnabled,
                    onChanged: (value) {
                      setState(() => _compensationEnabled = value);
                    },
                  ),
                  if (_compensationEnabled) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentType,
                      decoration: const InputDecoration(
                        labelText: 'Payment type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'hourly',
                          child: Text('Hourly'),
                        ),
                        DropdownMenuItem(
                          value: 'fixed_weekly',
                          child: Text('Fixed weekly'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _paymentType = value;
                          _rate.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _rate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: _required,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d{0,7}(\.\d{0,2})?'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: _paymentType == 'hourly'
                            ? 'Hourly rate'
                            : 'Weekly pay',
                        prefixText: '\$ ',
                        suffixText:
                            _paymentType == 'hourly' ? '/ hr' : '/ week',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active employee'),
                    subtitle: const Text(
                      'Inactive employees remain in historical records.',
                    ),
                    value: _active,
                    onChanged: (value) => setState(() => _active = value),
                  ),
                  if (_editing && widget.isOwner) ...[
                    const SizedBox(height: 20),
                    Text(
                      'App login',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: Icon(
                          _userLinked
                              ? Icons.verified_user_outlined
                              : Icons.person_add_alt_1_outlined,
                          color: _userLinked ? Colors.green : null,
                        ),
                        title: Text(
                          _userLinked
                              ? 'Login linked'
                              : 'Create employee login',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          _userLinked
                              ? 'This employee can sign in to Briskers. '
                                  'App role: $_appRoleLabel.'
                              : _appRoleCode == null
                                  ? 'This position does not create a staff '
                                      'login.'
                                  : 'Email: '
                                      '${_email.text.trim().isEmpty ? 'not set' : _email.text.trim()}'
                                      '\nApp role: $_appRoleLabel',
                        ),
                        isThreeLine: !_userLinked && _appRoleCode != null,
                      ),
                    ),
                    if (_appRoleCode != null) ...[
                      const SizedBox(height: 8),
                      if (!_userLinked)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _appLoginBusy ? null : _sendAppLoginInvite,
                            icon: const Icon(Icons.mail_outline),
                            label: const Text('Send app login invite'),
                          ),
                        ),
                      if (!_userLinked) const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed:
                              _appLoginBusy ? null : _createTestLogin,
                          icon: _appLoginBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.key_outlined),
                          label: Text(
                            _userLinked
                                ? 'Set / reset test password'
                                : 'Create test login',
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Test login is owner-only and bypasses the email '
                          'invite so you can use a mock email during testing. '
                          'Real employees should use the email invitation.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ||
                            BriskersConnectionModeController.instance.forceOffline
                        ? null
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save employee'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
