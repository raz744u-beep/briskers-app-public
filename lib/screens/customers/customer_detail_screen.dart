import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../core/formatters.dart';
import '../../services/briskers_api.dart';
import '../appointments/appointment_create_screen.dart';
import '../jobs/job_create_screen.dart';
import 'customer_account_section.dart';
import 'customer_appointments_section.dart';
import 'customer_notes_section.dart';
import 'customer_service_history_section.dart';
import 'customer_vehicles_section.dart';
import 'edit_customer_screen.dart';
import 'new_vehicle_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.businessId,
    required this.customerId,
  });

  final String businessId;
  final String customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  static const _api = BriskersApi();
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.customerDetail(
        widget.businessId,
        widget.customerId,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCustomerScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customer: customer,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _addVehicle() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewVehicleScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editVehicle(Map<String, dynamic> vehicle) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewVehicleScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          vehicle: vehicle,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _scheduleAppointment() async {
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    final vehicles = List<dynamic>.from(
      _data?['vehicles'] ?? const [],
    );

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentCreateScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customerName: customer['name']?.toString() ?? 'Customer',
          vehicles: vehicles,
        ),
      ),
    );

    if (changed == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment scheduled.')),
        );
      }
    }
  }

  Future<void> _createJob() async {
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    final vehicles = List<dynamic>.from(
      _data?['vehicles'] ?? const [],
    );

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JobCreateScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customerName: customer['name']?.toString() ?? 'Customer',
          vehicles: vehicles,
        ),
      ),
    );

    if (changed == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job created.')),
        );
      }
    }
  }

  Widget _quickActionIcon(IconData icon, Color color) {
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.14),
      child: Icon(icon, color: color),
    );
  }

  void _showPlannedAction(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$name is the next workflow step to be connected.',
        ),
      ),
    );
  }

  Future<void> _showQuickActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                ListTile(
                  leading: _quickActionIcon(
                    Icons.calendar_month_outlined,
                    BriskersColors.appointments,
                  ),
                  title: const Text('Schedule appointment'),
                  onTap: () => Navigator.pop(sheetContext, 'appointment'),
                ),
                ListTile(
                  leading: _quickActionIcon(
                    Icons.build_outlined,
                    BriskersColors.jobs,
                  ),
                  title: const Text('Create job'),
                  onTap: () => Navigator.pop(sheetContext, 'job'),
                ),
                ListTile(
                  leading: _quickActionIcon(
                    Icons.request_quote_outlined,
                    BriskersColors.estimates,
                  ),
                  title: const Text('Create estimate'),
                  onTap: () => Navigator.pop(sheetContext, 'estimate'),
                ),
                ListTile(
                  leading: _quickActionIcon(
                    Icons.receipt_long_outlined,
                    BriskersColors.invoices,
                  ),
                  title: const Text('Create invoice'),
                  onTap: () => Navigator.pop(sheetContext, 'invoice'),
                ),
                ListTile(
                  leading: _quickActionIcon(
                    Icons.directions_car_outlined,
                    BriskersColors.vehicles,
                  ),
                  title: const Text('Add vehicle'),
                  onTap: () => Navigator.pop(sheetContext, 'vehicle'),
                ),
                ListTile(
                  leading: _quickActionIcon(
                    Icons.note_add_outlined,
                    BriskersColors.notes,
                  ),
                  title: const Text('Add note'),
                  onTap: () => Navigator.pop(sheetContext, 'note'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'vehicle':
        await _addVehicle();
        break;
      case 'appointment':
        await _scheduleAppointment();
        break;
      case 'job':
        await _createJob();
        break;
      case 'estimate':
        _showPlannedAction('Estimate creation');
        break;
      case 'invoice':
        _showPlannedAction('Invoice creation');
        break;
      case 'note':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Open Customer notes to add a note for now.',
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    final vehicles = List<dynamic>.from(
      _data?['vehicles'] ?? const [],
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: BriskersColors.customers.withValues(alpha: 0.12),
        title: Text(
          '${customer['name'] ?? 'Customer'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: _data == null
          ? null
          : FloatingActionButton(
              onPressed: _showQuickActions,
              tooltip: 'Customer actions',
              child: const Icon(Icons.add),
            ),
      body: _data == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(
                        '${customer['name'] ?? ''}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ('${customer['phone'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                formatUsPhone('${customer['phone']}'),
                              ),
                            ),
                          if ('${customer['email'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('${customer['email']}'),
                            ),
                          const SizedBox(height: 2),
                          const Text('Tap to edit'),
                        ],
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editCustomer(customer),
                    ),
                  ),
                  const SizedBox(height: 18),
                  CustomerNotesSection(
                    businessId: widget.businessId,
                    customerId: widget.customerId,
                  ),
                  const SizedBox(height: 18),
                  CustomerVehiclesSection(
                    vehicles: vehicles,
                    onAdd: _addVehicle,
                    onEdit: _editVehicle,
                  ),
                  const SizedBox(height: 18),
                  CustomerAppointmentsSection(
                    businessId: widget.businessId,
                    customerId: widget.customerId,
                  ),
                  const SizedBox(height: 18),
                  CustomerServiceHistorySection(
                    businessId: widget.businessId,
                    customerId: widget.customerId,
                  ),
                  const SizedBox(height: 18),
                  CustomerAccountSection(
                    businessId: widget.businessId,
                    customerId: widget.customerId,
                    onDeleted: () => Navigator.pop(context, true),
                  ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
    );
  }
}
