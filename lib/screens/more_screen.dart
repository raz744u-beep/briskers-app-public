import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/supabase_config.dart';
import 'expenses_screen.dart';
import '../widgets/test_employee_payroll_staging_panel.dart';
import 'settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.businessId,
    required this.businessName,
    required this.roleCode,
    this.onBusinessNameChanged,
  });

  final String businessId;
  final String businessName;
  final String roleCode;
  final ValueChanged<String>? onBusinessNameChanged;

  @override
  Widget build(BuildContext context) {
    final owner = roleCode == 'owner';
    final canOpenExpenses = roleCode == 'owner' || roleCode == 'manager';
    final canOpenSettings = <String>{
      'owner',
      'manager',
      'office',
      'mechanic',
      'porter',
    }.contains(roleCode);

    return ListView(
      children: [
        if (canOpenExpenses)
          ListTile(
            leading: const Icon(
              Icons.receipt_long,
              color: BriskersColors.expenses,
            ),
            title: Text(tr('expensesIncome')),
            subtitle: Text(tr('expensesIncomeSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpensesScreen(
                    businessId: businessId,
                    roleCode: roleCode,
                  ),
                ),
              );
            },
          ),
        ListTile(
          leading: const Icon(Icons.calendar_month, color: BriskersColors.schedule),
          title: Text(tr('schedule')),
          subtitle: Text(tr('appointments')),
        ),
        if (owner)
          ListTile(
            leading: const Icon(Icons.analytics, color: BriskersColors.reports),
            title: Text(tr('reportsProfitability')),
            subtitle: Text(tr('reportsProfitabilitySub')),
          ),
        if (owner)
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Payroll staging TEST'),
            subtitle: const Text('Local preview only — no payments'),
            onTap: () async {
              final controller = TextEditingController();
              final employeeId = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('TEST employee ID'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Employee ID'),
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        final value = controller.text.trim();
                        if (value.isNotEmpty) Navigator.pop(dialogContext, value);
                      },
                      child: const Text('Preview'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (!context.mounted || employeeId == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Payroll TEST — not paid')),
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TestEmployeePayrollStagingPanel(
                          businessId: businessId,
                          employeeId: employeeId,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (canOpenSettings) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: BriskersColors.settings),
            title: Text(tr('settings')),
            subtitle: Text(tr('appOptions')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    businessId: businessId,
                    businessName: businessName,
                    roleCode: roleCode,
                    onBusinessNameChanged: onBusinessNameChanged,
                  ),
                ),
              );
            },
          ),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline, color: BriskersColors.settings),
          title: const Text('About Briskers'),
          subtitle: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Text(info == null ? 'App version and build number' : 'Version ${info.version} • Build ${info.buildNumber}');
            },
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final info = await PackageInfo.fromPlatform();
            if (!context.mounted) return;
            showAboutDialog(context: context, applicationName: 'Briskers', applicationVersion: 'Version ${info.version} (Build ${info.buildNumber})');
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(tr('signOut')),
          onTap: () => supabase.auth.signOut(),
        ),
      ],
    );
  }
}
