import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';

/// The executable customer shortcuts. Adding a new choice requires updating
/// both the screen dispatcher and the action audit tests.
enum CustomerQuickAction {
  appointment,
  job,
  estimate,
  invoice,
  vehicle,
  note,
}

const customerQuickActions = CustomerQuickAction.values;

bool canManageCustomerActions(String roleCode) =>
    const {'owner', 'office', 'manager'}.contains(roleCode);

String customerQuickActionLabel(CustomerQuickAction action) => switch (action) {
  CustomerQuickAction.appointment => 'Schedule appointment',
  CustomerQuickAction.job => 'Create job',
  CustomerQuickAction.estimate => 'Create estimate',
  CustomerQuickAction.invoice => 'Create invoice',
  CustomerQuickAction.vehicle => 'Add vehicle',
  CustomerQuickAction.note => 'Add note',
};

String customerQuickActionDestination(CustomerQuickAction action) =>
    switch (action) {
      CustomerQuickAction.appointment => 'appointment_create',
      CustomerQuickAction.job => 'job_create',
      CustomerQuickAction.estimate => 'estimate_create',
      CustomerQuickAction.invoice => 'blank_invoice_create',
      CustomerQuickAction.vehicle => 'vehicle_create',
      CustomerQuickAction.note => 'customer_note_composer',
    };

IconData customerQuickActionIcon(CustomerQuickAction action) => switch (action) {
  CustomerQuickAction.appointment => Icons.calendar_month_outlined,
  CustomerQuickAction.job => Icons.build_outlined,
  CustomerQuickAction.estimate => Icons.request_quote_outlined,
  CustomerQuickAction.invoice => Icons.receipt_long_outlined,
  CustomerQuickAction.vehicle => Icons.directions_car_outlined,
  CustomerQuickAction.note => Icons.note_add_outlined,
};

Color customerQuickActionColor(CustomerQuickAction action) => switch (action) {
  CustomerQuickAction.appointment => BriskersColors.appointments,
  CustomerQuickAction.job => BriskersColors.jobs,
  CustomerQuickAction.estimate => BriskersColors.estimates,
  CustomerQuickAction.invoice => BriskersColors.invoices,
  CustomerQuickAction.vehicle => BriskersColors.vehicles,
  CustomerQuickAction.note => BriskersColors.notes,
};

class CustomerQuickActionsSheet extends StatelessWidget {
  const CustomerQuickActionsSheet({
    super.key,
    required this.roleCode,
    required this.onSelected,
    this.offline = false,
  });

  final String roleCode;
  final ValueChanged<CustomerQuickAction> onSelected;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    if (!canManageCustomerActions(roleCode)) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Customer actions are not available for this role.'),
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final action in customerQuickActions)
              ListTile(
                key: ValueKey('customer-action-${action.name}'),
                leading: CircleAvatar(
                  backgroundColor: customerQuickActionColor(action)
                      .withValues(alpha: 0.14),
                  child: Icon(
                    customerQuickActionIcon(action),
                    color: customerQuickActionColor(action),
                  ),
                ),
                title: Text(customerQuickActionLabel(action)),
                subtitle: offline && (action == CustomerQuickAction.appointment ||
                    action == CustomerQuickAction.job)
                    ? const Text('Requires an internet connection') : null,
                onTap: offline && (action == CustomerQuickAction.appointment ||
                    action == CustomerQuickAction.job)
                    ? null : () => onSelected(action),
              ),
          ],
        ),
      ),
    );
  }
}
