import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/connection_mode.dart';
import '../../core/vehicle_options.dart';
import '../../services/offline_customer_vehicle_admin_service.dart';

class EditCustomerScreen extends StatefulWidget {
  const EditCustomerScreen({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.customer,
  });

  final String businessId;
  final String customerId;
  final Map<String, dynamic> customer;

  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen> {
  final OfflineCustomerVehicleAdminService _offlineAdmin =
      OfflineCustomerVehicleAdminService();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _zip;
  String? _state;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.customer['name']?.toString() ?? '',
    );
    _phone = TextEditingController(
      text: formatUsPhone(widget.customer['phone']?.toString() ?? ''),
    );
    _email = TextEditingController(
      text: widget.customer['email']?.toString() ?? '',
    );
    final addressRaw = widget.customer['billing_address'];
    final address = addressRaw is Map
        ? Map<String, dynamic>.from(addressRaw)
        : <String, dynamic>{};
    _address1 = TextEditingController(
      text: address['line1']?.toString() ?? '',
    );
    _address2 = TextEditingController(
      text: address['line2']?.toString() ?? '',
    );
    _city = TextEditingController(
      text: address['city']?.toString() ?? '',
    );
    _zip = TextEditingController(
      text: address['postal_code']?.toString() ??
          address['zip']?.toString() ??
          '',
    );
    final existingState = address['state']?.toString().toUpperCase();
    if (existingState != null && usStateCodes.contains(existingState)) {
      _state = existingState;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _zip.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phoneDigits = digitsOnly(_phone.text);
    final email = _email.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Customer name is required.');
      return;
    }

    if (phoneDigits.isNotEmpty && phoneDigits.length != 10) {
      setState(() => _error = 'Phone number must contain 10 digits.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final address = <String, dynamic>{
        if (_address1.text.trim().isNotEmpty)
          'line1': _address1.text.trim(),
        if (_address2.text.trim().isNotEmpty)
          'line2': _address2.text.trim(),
        if (_city.text.trim().isNotEmpty)
          'city': _city.text.trim(),
        if ((_state ?? '').isNotEmpty) 'state': _state,
        if (_zip.text.trim().isNotEmpty)
          'postal_code': _zip.text.trim(),
        'country': 'US',
      };

      final customer = await _offlineAdmin.queueCustomerProfile(
        widget.businessId,
        widget.customerId,
        name: name,
        phone: phoneDigits.isEmpty ? null : phoneDigits,
        email: email.isEmpty ? null : email,
        billingAddress: address,
      );

      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await _offlineAdmin.flush(widget.businessId);
        } catch (_) {
          // The saved customer edit remains queued for the next sync.
        }
      }

      if (mounted) Navigator.pop(context, customer);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          const SizedBox(height: 12),
          TextField(
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
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Address',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _address1,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Street address'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address2,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Address line 2'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'City'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _state,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'State'),
                  items: usStateCodes
                      .map((state) => DropdownMenuItem(
                            value: state,
                            child: Text(state),
                          ))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _state = value),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _zip,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'ZIP'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Saving...' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}
