import 'dart:io';
import 'package:flutter/material.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/payroll_owner_lan.dart';
import '../../services/payroll_owner_lease.dart';
import 'payroll_lan_controls.dart';

class OwnerPayrollConnections {
  static final Map<String, PayrollOwnerLan> _instances = {};
  static Future<PayrollOwnerLan> open(BuildContext context, String business,
      LocalOwnerGrant grant) async {
    grant.assertValid(business, grant.actorId);
    Future<LocalOwnerGrant?> approve(String device) async {
        if (!context.mounted) return null;
        final approved = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
          title: const Text('Connect your other Owner device?'),
          content: const Text('Approve only while you are connecting your own Briskers Owner device on shop Wi-Fi. This shares private payroll records.'),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Approve connection'))],
        ));
        if (approved != true || !context.mounted) return null;
        return DeviceOwnerAuthorization.instance.authority.authorizeLocal(business);
      }
    final existing = _instances[business];
    if (existing != null && existing.actor == grant.actorId) { existing.approve = approve; return existing; }
    if (existing != null) await existing.close();
    final lease = await PayrollOwnerLease.platform(business);
    try { await lease.migrate(grant); } on PayrollPending { /* Join the current shop ledger. */ }
    final instance = PayrollOwnerLan(lease: lease, database: localDatabase,
      actor: grant.actorId,
      assertAccount: () {
        if (DeviceOwnerAuthorization.instance.currentIdentity()?.actorId != grant.actorId) {
          throw StateError('Owner account changed.');
        }
      },
      approve: approve);
    try { await instance.listen(InternetAddress.anyIPv4); } on SocketException {
      // The current lease holder can continue offline without LAN permission.
    }
    _instances[business] = instance;
    return instance;
  }
}

Future<void> showOwnerPayrollConnection(BuildContext context, String business) async {
  try {
    final grant = await DeviceOwnerAuthorization.instance.authority.authorizeLocal(business);
    if (!context.mounted) return;
    final service = await OwnerPayrollConnections.open(context, business, grant);
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Shop payroll Wi-Fi'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Use the same shop Wi-Fi on both Owner devices. Your existing Owner login and unlock are used; no Owner code is needed.'),
        const SizedBox(height: 12),
        const Text('This device’s Wi-Fi address:'),
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (!address.isLoopback) SelectableText('${address.address}:${service.port}'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close')),
        FilledButton(onPressed: () async {
          final address = await payrollLanInput(dialog, 'Connect to shop payroll', 'Other Owner device Wi-Fi address');
          if (address == null || !dialog.mounted) return;
          try {
            final fresh = await DeviceOwnerAuthorization.instance.authority.authorizeLocal(business);
            await service.connect(address, fresh);
            if (dialog.mounted) Navigator.pop(dialog);
          } catch (error) {
            if (dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('$error')));
          }
        }, child: const Text('Connect to other Owner device')),
      ],
    ));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }
}
