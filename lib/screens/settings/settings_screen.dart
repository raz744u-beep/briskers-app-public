import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import 'catalog_settings_screen.dart';
import 'employees_settings_screen.dart';
import 'job_statuses_settings_screen.dart';
import 'item_categories_settings_screen.dart';
import 'payment_methods_settings_screen.dart';
import 'shop_info_settings_screen.dart';
import 'tax_invoicing_settings_screen.dart';

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
          ListTile(
            leading: const Icon(
              Icons.inventory_2_outlined,
              color: BriskersColors.invoices,
            ),
            title: const Text('Items / Catalog'),
            subtitle: const Text(
              'Parts, labor, services, prices, taxability and categories',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CatalogSettingsScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.category_outlined,
              color: BriskersColors.invoices,
            ),
            title: const Text('Item Categories'),
            subtitle: const Text(
              'Edit the category list used by catalog items',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemCategoriesSettingsScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.receipt_long_outlined,
              color: BriskersColors.jobs,
            ),
            title: const Text('Taxes & Invoicing'),
            subtitle: const Text(
              'Default sales tax rate and invoice tax behavior',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaxInvoicingSettingsScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.payments_outlined,
              color: BriskersColors.expenses,
            ),
            title: const Text('Payment Methods'),
            subtitle: const Text(
              'Cash, cards, Zelle and other accepted methods',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentMethodsSettingsScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
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
