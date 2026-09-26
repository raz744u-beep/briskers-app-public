import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/briskers_api.dart';

class CustomerAccountSection extends StatefulWidget {
  const CustomerAccountSection({
    super.key,
    required this.businessId,
    required this.customerId,
    this.onDeleted,
  });

  final String businessId;
  final String customerId;
  final VoidCallback? onDeleted;

  @override
  State<CustomerAccountSection> createState() => _CustomerAccountSectionState();
}

class _CustomerAccountSectionState extends State<CustomerAccountSection> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _account;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = await _api.customerAccountContext(
      widget.businessId,
      widget.customerId,
    );
    if (!mounted) return;
    setState(() {
      _account = account;
      _loading = false;
    });
  }

  Future<void> _showCredentials(
    String title,
    Map<String, dynamic> result,
  ) async {
    final email = result['email']?.toString() ?? '';
    final password = result['temporary_password']?.toString() ?? '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Give the customer these temporary login credentials:'),
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

  Future<void> _action(String action) async {
    if (action == 'reset_password') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset customer password?'),
          content: const Text(
            'This will replace the customer\'s current password with a new temporary password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset password'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.customerAccountAction(
        widget.businessId,
        widget.customerId,
        action,
      );
      if (!mounted) return;
      await _showCredentials(
        action == 'create' ? 'Online account created' : 'Password reset',
        result,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text(
          'This removes the customer from active lists and disables their online access. Existing invoices and service history are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete customer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.customerAccountAction(
        widget.businessId,
        widget.customerId,
        'delete_customer',
      );
      if (mounted) widget.onDeleted?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    // No users.manage permission: hide account controls from this role.
    if (_account == null) return const SizedBox.shrink();

    final active = _account?['account_active'] == true;
    final email = _account?['email']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              active
                  ? Icons.verified_user_outlined
                  : Icons.person_off_outlined,
            ),
            title: Text(
              active ? 'Online account active' : 'No online account',
            ),
            subtitle: Text(
              active
                  ? email
                  : 'Create customer portal access when needed.',
            ),
            trailing: active
                ? const Icon(Icons.check_circle_outline)
                : null,
          ),
        ),
        const SizedBox(height: 8),
        if (active)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _action('reset_password'),
            icon: const Icon(Icons.key_outlined),
            label: const Text('Reset password'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _action('create'),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Create online account'),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete customer'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }
}
