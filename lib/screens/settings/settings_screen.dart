import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../core/briskers_i18n.dart';
import '../../core/connection_mode.dart';
import '../../widgets/briskers_page_header.dart';
import '../kiosk/kiosk_checkin_screen.dart';
import 'catalog_settings_screen.dart';
import 'employees_settings_screen.dart';
import 'expense_settings_screen.dart';
import 'job_statuses_settings_screen.dart';
import 'kiosk_checkin_settings_screen.dart';
import 'invoice_statuses_settings_screen.dart';
import 'language_settings_screen.dart';
import 'local_sync_status_screen.dart';
import 'item_categories_settings_screen.dart';
import 'payment_methods_settings_screen.dart';
import 'receipt_training_samples_screen.dart';
import 'shop_info_settings_screen.dart';
import 'tax_invoicing_settings_screen.dart';
import 'warranty_payment_calculator_screen.dart';
import 'warranty_workflow_settings_screen.dart';

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

  Future<void> _chooseConnectionMode(BuildContext context) async {
    final controller = BriskersConnectionModeController.instance;
    final selected = await showModalBottomSheet<BriskersConnectionMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Connection Mode',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Temporary testing control. Auto is the normal production mode.',
              ),
            ),
            for (final mode in BriskersConnectionMode.values)
              RadioListTile<BriskersConnectionMode>(
                value: mode,
                groupValue: controller.mode,
                title: Text(
                  switch (mode) {
                    BriskersConnectionMode.auto => 'Auto',
                    BriskersConnectionMode.online => 'Force Online',
                    BriskersConnectionMode.offline => 'Force Offline',
                  },
                ),
                subtitle: Text(
                  switch (mode) {
                    BriskersConnectionMode.auto =>
                      'Use local data first and sync online when available.',
                    BriskersConnectionMode.online =>
                      'Require server calls so online/API problems are visible.',
                    BriskersConnectionMode.offline =>
                      'Block Briskers server calls and test only local/offline behavior.',
                  },
                ),
                onChanged: (value) => Navigator.pop(sheetContext, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await controller.setMode(selected);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connection mode: ${controller.label}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: BriskersPageTitle(title: tr('settings'), logoHeight: 40),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.translate, color: BriskersColors.settings),
            title: Text(tr('language')),
            subtitle: Text(tr('languageSubtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LanguageSettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.storage_outlined,
              color: BriskersColors.settings,
            ),
            title: Text(tr('localDatabaseSync')),
            subtitle: Text(tr('localDatabaseSyncSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocalSyncStatusScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          if (roleCode == 'owner' || roleCode == 'office')
            AnimatedBuilder(
              animation: BriskersConnectionModeController.instance,
              builder: (context, _) {
                final controller =
                    BriskersConnectionModeController.instance;
                final icon = switch (controller.mode) {
                  BriskersConnectionMode.auto => Icons.sync_alt,
                  BriskersConnectionMode.online => Icons.cloud_done_outlined,
                  BriskersConnectionMode.offline => Icons.cloud_off_outlined,
                };
                return ListTile(
                  leading: Icon(icon, color: BriskersColors.settings),
                  title: const Text('Connection Mode'),
                  subtitle: Text(
                    '${controller.label} • temporary testing control',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseConnectionMode(context),
                );
              },
            ),
          ListTile(
            leading: const Icon(
              Icons.calculate_outlined,
              color: BriskersColors.invoices,
            ),
            title: Text(tr('warrantyPaymentCalculator')),
            subtitle: Text(tr('warrantyPaymentCalculatorSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WarrantyPaymentCalculatorScreen(),
                ),
              );
            },
          ),
          if (roleCode == 'owner') ...[
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.shield_outlined,
                color: BriskersColors.invoices,
              ),
              title: const Text('Warranty & invoice notes'),
              subtitle: const Text(
                'Warranty companies, standard notes and disclaimer templates',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WarrantyWorkflowSettingsScreen(
                      businessId: businessId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.storefront,
                color: BriskersColors.settings,
              ),
            title: Text(tr('shopInformation')),
            subtitle: Text(tr('shopInformationSub')),
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
              Icons.touch_app_outlined,
              color: BriskersColors.schedule,
            ),
            title: Text(tr('kioskCheckIn')),
            subtitle: Text(tr('kioskCheckInSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => KioskCheckInSettingsScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          ListTile(
              leading: const Icon(
                Icons.play_circle_outline,
                color: BriskersColors.schedule,
              ),
              title: Text(tr('startKioskMode')),
              subtitle: Text(tr('startKioskModeSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KioskCheckInScreen(
                      businessId: businessId,
                      businessName: businessName,
                      allowExit: true,
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
            title: Text(tr('employees')),
            subtitle: Text(tr('employeesSub')),
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
            title: Text(tr('jobStatuses')),
            subtitle: Text(tr('jobStatusesSub')),
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
          ListTile(
            leading: const Icon(
              Icons.receipt_long_outlined,
              color: BriskersColors.invoices,
            ),
            title: Text(tr('invoiceStatuses')),
            subtitle: Text(tr('invoiceStatusesSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceStatusesSettingsScreen(
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
            title: Text(tr('itemsCatalog')),
            subtitle: Text(tr('itemsCatalogSub')),
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
            title: Text(tr('itemCategories')),
            subtitle: Text(tr('itemCategoriesSub')),
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
            title: Text(tr('taxesInvoicing')),
            subtitle: Text(tr('taxesInvoicingSub')),
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
              Icons.psychology_outlined,
              color: BriskersColors.expenses,
            ),
            title: Text(tr('aiReceiptSamples')),
            subtitle: Text(tr('aiReceiptSamplesSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptTrainingSamplesScreen(
                    businessId: businessId,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              color: BriskersColors.expenses,
            ),
            title: Text(tr('transactionsSetup')),
            subtitle: Text(tr('transactionsSetupSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpenseSettingsScreen(
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
            title: Text(tr('paymentMethods')),
            subtitle: Text(tr('paymentMethodsSub')),
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
          ListTile(
            leading: const Icon(
              Icons.notifications_outlined,
              color: BriskersColors.schedule,
            ),
            title: Text(tr('notifications')),
            subtitle: Text(tr('notificationsSub')),
          ),
          ],
        ],
      ),
    );
  }
}
