import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/supabase_config.dart';
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
    final canOpenSettings = roleCode == 'owner' || roleCode == 'manager';

    return ListView(
      children: [
        const ListTile(
          leading: Icon(Icons.receipt_long, color: BriskersColors.expenses),
          title: Text('Expenses & income'),
          subtitle: Text('Coming in the next build'),
        ),
        const ListTile(
          leading: Icon(Icons.calendar_month, color: BriskersColors.schedule),
          title: Text('Schedule'),
          subtitle: Text('Appointments are now available from the bottom bar'),
        ),
        if (owner)
          const ListTile(
            leading: Icon(Icons.analytics, color: BriskersColors.reports),
            title: Text('Reports & profitability'),
            subtitle: Text('Owner only — coming in the next build'),
          ),
        if (canOpenSettings) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: BriskersColors.settings),
            title: const Text('Settings'),
            subtitle: const Text('Shop information and app options'),
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
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => supabase.auth.signOut(),
        ),
      ],
    );
  }
}
