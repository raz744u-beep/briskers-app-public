import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../services/briskers_api.dart';

class EmployeeEditScreen extends StatefulWidget {
  const EmployeeEditScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    this.employeeId,
  });

  final String businessId;
  final bool isOwner;
  final String? employeeId;

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  static const _api = BriskersApi();

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
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
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.employeeId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _ssn.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final positions = await _api.employeePositions(widget.businessId);
      Map<String, dynamic>? employee;
      if (_editing) {
        employee = await _api.employeeSettingsDetail(
          widget.businessId,
          widget.employeeId!,
        );
      }

      if (!mounted) return;

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

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit employee' : 'Add employee'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
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
                    onPressed: _saving ? null : _save,
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
