import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import 'new_vehicle_screen.dart';

class NewCustomerScreen extends StatefulWidget {
  const NewCustomerScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends State<NewCustomerScreen> {
  static const _api = BriskersApi();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  String? _error;
  bool _busy = false;
  bool _createOnlineAccount = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _showCredentials(Map<String, dynamic> result) async {
    final email = result['email']?.toString() ?? _email.text.trim();
    final password = result['temporary_password']?.toString() ?? '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Online account created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Give the customer these temporary login credentials:',
            ),
            const SizedBox(height: 12),
            SelectableText('Email: $email'),
            const SizedBox(height: 8),
            SelectableText('Temporary password: $password'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: 'Email: $email\nPassword: $password'),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Credentials copied.')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Customer name is required.');
      return;
    }

    final phoneDigits = digitsOnly(_phone.text);
    if (phoneDigits.isNotEmpty && phoneDigits.length != 10) {
      setState(() => _error = 'Phone number must contain 10 digits.');
      return;
    }

    if (_createOnlineAccount && email.isEmpty) {
      setState(
        () => _error = 'An email address is required for an online account.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final customerId = await _api.createCustomer(
        widget.businessId,
        name: name,
        phone: phoneDigits.isEmpty ? null : phoneDigits,
        email: email.isEmpty ? null : email,
      );

      if (_createOnlineAccount) {
        final credentials = await _api.customerAccountAction(
          widget.businessId,
          customerId,
          'create',
        );
        if (mounted) await _showCredentials(credentials);
      }

      if (!mounted) return;

      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NewVehicleScreen(
            businessId: widget.businessId,
            customerId: customerId,
          ),
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const roundedInput = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      borderSide: BorderSide(color: Color(0xFFB8C0CC)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('New customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name *', border: roundedInput, enabledBorder: roundedInput, focusedBorder: roundedInput),
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
              border: roundedInput,
              enabledBorder: roundedInput,
              focusedBorder: roundedInput,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email', border: roundedInput, enabledBorder: roundedInput, focusedBorder: roundedInput),
          ),
          const SizedBox(height: 10),
          Card(
            child: CheckboxListTile(
              value: _createOnlineAccount,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                        () => _createOnlineAccount = value ?? false,
                      ),
              title: const Text('Create online customer account'),
              subtitle: const Text(
                'Creates the login now and generates a temporary random password.',
              ),
              secondary: const Icon(Icons.person_add_alt_1),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.customers,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save customer & add vehicle'),
          ),
        ],
      ),
    );
  }
}
