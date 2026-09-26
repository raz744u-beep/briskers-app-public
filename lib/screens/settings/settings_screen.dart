import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import 'employees_settings_screen.dart';
import 'job_statuses_settings_screen.dart';
import 'shop_info_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront, color: BriskersColors.settings),
            title: const Text('Shop information'),
            subtitle: const Text(
              'Name, address, hours, phone, links and customer page',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopInfoSettingsScreen(
                    businessId: businessId,
                    fallbackBusinessName: businessName,
                    onBusinessNameChanged: onBusinessNameChanged,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(
              Icons.people_alt_outlined,
              color: BriskersColors.customers,
            ),
            title: const Text('Employees'),
            subtitle: const Text(
              'Personal information, positions and pay settings',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EmployeesSettingsScreen(
                    businessId: businessId,
                    isOwner: roleCode == 'owner',
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.rule_folder_outlined,
              color: BriskersColors.jobs,
            ),
            title: const Text('Job statuses'),
            subtitle: const Text(
              'Names, colors, icons and custom workflow statuses',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JobStatusesSettingsScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.receipt_long_outlined, color: BriskersColors.jobs),
            title: Text('Taxes & invoicing'),
            subtitle: Text('Tax defaults, invoice options and numbering — coming next'),
          ),
          const ListTile(
            leading: Icon(Icons.payments_outlined, color: BriskersColors.expenses),
            title: Text('Payment methods'),
            subtitle: Text('Accepted payment methods — coming next'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_outlined, color: BriskersColors.schedule),
            title: Text('Notifications'),
            subtitle: Text('Customer and employee notification options — coming next'),
          ),
        ],
      ),
    );
  }
}
