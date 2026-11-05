import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/payroll_lan_workflow.dart';

Future<String?> payrollLanInput(
  BuildContext context, String title, String label, {String initialValue = ''}
) async {
  final controller = TextEditingController(text:initialValue);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          onTapAlwaysCalled:true,
          onTap:()=>controller.selection=TextSelection(baseOffset:0,extentOffset:controller.text.length),
          decoration: InputDecoration(labelText: label),
          autocorrect: false,
          enableSuggestions: false,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  } finally {
    // The dialog route retains the field during its closing animation.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  }
}

Future<void> showPayrollLanCode(
  BuildContext context, String title, String value,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(child: SelectableText(value)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Close')),
    ],
  ),
);

Future<void> showPayrollLanSync(
  BuildContext context, PayrollLanWorkflow workflow,
) async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  if (!context.mounted) return;
  final port = await workflow.listen(InternetAddress.anyIPv4);
  try {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PayrollLanSyncDialog(
        workflow: workflow,
        endpoints: [
          for (final interface in interfaces)
            for (final ip in interface.addresses) '${ip.address}:$port',
        ],
      ),
    );
  } finally {
    await workflow.delivery.close();
  }
}

class _PayrollLanSyncDialog extends StatefulWidget {
  const _PayrollLanSyncDialog({required this.workflow, required this.endpoints});

  final PayrollLanWorkflow workflow;
  final List<String> endpoints;

  @override
  State<_PayrollLanSyncDialog> createState() => _PayrollLanSyncDialogState();
}

class _PayrollLanSyncDialogState extends State<_PayrollLanSyncDialog> {
  String _endpoint = '';
  String? _result;
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final parts = _endpoint.trim().split(':');
      final address = InternetAddress.tryParse(parts.first);
      final port = parts.length == 2 ? int.tryParse(parts.last) : null;
      if (address == null || port == null || port < 1 || port > 65535) {
        throw const FormatException('Enter the paired device IP and port.');
      }
      final count = await widget.workflow.delivery.deliver(address, port);
      if (mounted) setState(() => _result = '$count payroll changes delivered.');
    } catch (error) {
      if (mounted) setState(() => _result = 'Changes remain saved for retry. $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Shop Wi-Fi payroll'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Keep this open on both paired devices.'),
          for (final endpoint in widget.endpoints) SelectableText(endpoint),
          TextField(
            onChanged: (value) => _endpoint = value,
            decoration: const InputDecoration(labelText: 'Paired device IP:port'),
          ),
          if (_result != null) Text(_result!),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _sending ? null : () => Navigator.pop(context),
        child: const Text('Close')),
      FilledButton(onPressed: _sending ? null : _send,
        child: const Text('Send saved changes')),
    ],
  );
}
