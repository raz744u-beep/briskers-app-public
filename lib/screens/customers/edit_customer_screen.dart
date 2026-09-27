import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../services/briskers_api.dart';

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
  static const _api = BriskersApi();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;

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
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
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
      final response = await _api.updateCustomerProfile(
        widget.businessId,
        widget.customerId,
        name: name,
        phone: phoneDigits.isEmpty ? null : phoneDigits,
        email: email.isEmpty ? null : email,
      );
      final saved = response['customer'];
      final customer = saved is Map
          ? Map<String, dynamic>.from(saved)
          : <String, dynamic>{
              'id': widget.customerId,
              'name': name,
              'phone': phoneDigits.isEmpty ? null : phoneDigits,
              'email': email.isEmpty ? null : email,
            };
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
