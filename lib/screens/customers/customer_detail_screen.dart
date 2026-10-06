import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/briskers_colors.dart';
import '../../core/connection_mode.dart';
import '../../core/formatters.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/local_customer_repository.dart';
import '../../services/offline_customer_vehicle_admin_service.dart';
import '../appointments/appointment_create_screen.dart';
import '../jobs/job_create_screen.dart';
import 'customer_account_section.dart';
import 'customer_appointments_section.dart';
import 'customer_notes_section.dart';
import 'customer_service_history_section.dart';
import 'customer_vehicles_section.dart';
import 'customer_vehicle_findings_section.dart';
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
  static const _sectionCache = CustomerDetailCache();
  final CustomerVehicleSyncService _sync =
      CustomerVehicleSyncService();
  final LocalCustomerRepository _localCustomers =
      LocalCustomerRepository();
  final OfflineCustomerVehicleAdminService _offlineAdmin =
      OfflineCustomerVehicleAdminService();

  Map<String, dynamic>? _data;
  String? _error;
  bool _onlineReady = false;
  bool _showingLocal = false;

  bool get _canEditLocal => _data != null;

  Future<Map<String, dynamic>> _loadOfflineSections() async {
    Future<List<Map<String, dynamic>>> listSection(String key) async {
      final raw = await _sectionCache.load(
        widget.businessId,
        widget.customerId,
        key,
      );
      return raw is List
          ? raw
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
    }

    final findings = await listSection('findings');
    final notes = await listSection('notes');
    final appointments = await listSection('appointments');

    final historyRaw = await _sectionCache.load(
      widget.businessId,
      widget.customerId,
      'service_history',
    );
    final history = historyRaw is Map
        ? Map<String, dynamic>.from(historyRaw)
        : <String, dynamic>{};

    return <String, dynamic>{
      'findings': findings,
      'notes': notes,
      'appointments': appointments,
      'history': history,
    };
  }

  Widget _offlineCountCard({
    required IconData icon,
    required String title,
    required String emptyText,
    required List<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic>)? label,
  }) {
    return Card(
      child: ExpansionTile(
        maintainState: false,
        leading: Icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          rows.isEmpty
              ? emptyText
              : rows.length == 1
                  ? '1 saved item'
                  : '${rows.length} saved items',
        ),
        children: rows.isEmpty
            ? const <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No saved data yet.'),
                  ),
                ),
              ]
            : rows.map((row) {
                final text = label?.call(row) ?? '';
                return ListTile(
                  dense: true,
                  title: Text(
                    text.isEmpty ? 'Saved item' : text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget _offlineCustomerSections() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadOfflineSections(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading saved customer details...'),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final findings = List<Map<String, dynamic>>.from(
          data['findings'] ?? const <Map<String, dynamic>>[],
        );
        final notes = List<Map<String, dynamic>>.from(
          data['notes'] ?? const <Map<String, dynamic>>[],
        );
        final appointments = List<Map<String, dynamic>>.from(
          data['appointments'] ?? const <Map<String, dynamic>>[],
        );
        final history = Map<String, dynamic>.from(
          data['history'] ?? const <String, dynamic>{},
        );
        final jobs = List<dynamic>.from(history['jobs'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final documents = List<dynamic>.from(history['documents'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final expenses = List<dynamic>.from(history['expenses'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();

        return Column(
          children: [
            _offlineCountCard(
              icon: Icons.car_repair_outlined,
              title: 'Vehicle Findings',
              emptyText: 'No saved findings',
              rows: findings,
              label: (row) => row['body']?.toString() ?? 'Vehicle finding',
            ),
            const SizedBox(height: 18),
            _offlineCountCard(
              icon: Icons.note_alt_outlined,
              title: 'Notes',
              emptyText: 'No saved notes',
              rows: notes,
              label: (row) => row['body']?.toString() ?? 'Customer note',
            ),
            const SizedBox(height: 18),
            _offlineCountCard(
              icon: Icons.calendar_month_outlined,
              title: 'Appointments',
              emptyText: 'No saved appointments',
              rows: appointments,
              label: (row) {
                final title = row['title']?.toString().trim() ?? '';
                final starts = row['starts_at']?.toString().trim() ?? '';
                return [starts, title].where((x) => x.isNotEmpty).join(' • ');
              },
            ),
            const SizedBox(height: 18),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text(
                  'Service History',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${jobs.length} jobs • ${documents.length} documents • ${expenses.length} expenses',
                ),
                children: [
                  if (jobs.isEmpty && documents.isEmpty && expenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No saved service history yet.'),
                      ),
                    )
                  else ...[
                    for (final job in jobs.take(12))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.build_outlined),
                        title: Text(
                          [
                            job['job_number']?.toString() ?? '',
                            job['title']?.toString() ?? '',
                          ].where((x) => x.isNotEmpty).join(' — '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (jobs.length > 12)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('+ ${jobs.length - 12} more jobs saved'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }


  String get _detailCacheKey =>
      'briskers_customer_detail_${widget.businessId}_${widget.customerId}';

  Future<Map<String, dynamic>?> _cachedFullDetail() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_detailCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveFullDetail(Map<String, dynamic> detail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detailCacheKey, jsonEncode(detail));
  }


  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var localShown = false;
    final forceOnline =
        BriskersConnectionModeController.instance.forceOnline;
    final forceOffline =
        BriskersConnectionModeController.instance.forceOffline;

    if (!forceOnline) {
      try {
        final cached = await _cachedFullDetail();
        final local = cached ??
            await _localCustomers.customerDetail(
              widget.businessId,
              widget.customerId,
            );
        if (local != null && mounted) {
          localShown = true;
          setState(() {
            _data = local;
            _showingLocal = true;
            _onlineReady = false;
            _error = null;
          });
        }
      } catch (_) {
        // The online refresh below can still populate the local cache.
      }
    }

    if (forceOffline) {
      if (mounted && localShown) {
        setState(() {
          _onlineReady = false;
          _showingLocal = true;
          _error = null;
        });
      }
      return;
    }

    try {
      try {
        await _offlineAdmin.flush(widget.businessId);
      } catch (_) {
        // Pending edits stay queued if the connection is not ready yet.
      }
      await _sync.pull(widget.businessId);
      Map<String, dynamic>? fullDetail;
      try {
        fullDetail = await _api.customerDetail(
          widget.businessId,
          widget.customerId,
        );
        await _saveFullDetail(fullDetail);
        await _sync.refreshCustomer(
          widget.businessId,
          widget.customerId,
        );
      } catch (_) {
        // The regular local snapshot is still usable if a focused refresh fails.
      }
      final bootstrapped =
          await _localCustomers.hasBootstrap(widget.businessId);
      final local = fullDetail ??
          await _localCustomers.customerDetail(
            widget.businessId,
            widget.customerId,
          );

      if (!mounted) return;
      setState(() {
        _data = local;
        _onlineReady = bootstrapped && local != null;
        _showingLocal = !_onlineReady && local != null;
        _error = local == null
            ? (bootstrapped
                ? 'Customer not found.'
                : 'Customer access is not available for this account.')
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _onlineReady = false;
        if (localShown && !forceOnline) {
          _showingLocal = true;
          _error = null;
        } else {
          _error = error.toString();
        }
      });
    }
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    if (!_canEditLocal) return;
    final saved = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCustomerScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customer: customer,
        ),
      ),
    );
    if (saved == null || !mounted) return;

    setState(() {
      final data = Map<String, dynamic>.from(_data ?? const {});
      final current = Map<String, dynamic>.from(
        data['customer'] ?? const {},
      );
      current.addAll(saved);
      data['customer'] = current;
      _data = data;
    });

    await _load();
  }

  Future<void> _editProblemFlag() async {
    if (!_canEditLocal) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    bool flagged = customer['problem_flag'] == true;
    final controller = TextEditingController(
      text: customer['problem_flag_note']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Problem customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Flag this customer'),
                  value: flagged,
                  onChanged: (value) =>
                      setDialogState(() => flagged = value == true),
                ),
                if (flagged) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 6,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Reason / note',
                      hintText: 'Example: Non-paying customer',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _offlineAdmin.queueProblemFlag(
        widget.businessId,
        widget.customerId,
        flagged: flagged,
        note: flagged ? controller.text.trim() : null,
      );
      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await _offlineAdmin.flush(widget.businessId);
        } catch (_) {}
      }
      await _load();
    }
    controller.dispose();
  }

  Future<void> _addVehicle() async {
    if (!_canEditLocal) return;
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
    if (!_canEditLocal) return;
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
    if (!_onlineReady) return;
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
    if (!_onlineReady) return;
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
    if (!_onlineReady) return;
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
    final addressRaw = customer['billing_address'];
    final address = addressRaw is Map
        ? Map<String, dynamic>.from(addressRaw)
        : <String, dynamic>{};
    final addressLine1 = address['line1']?.toString().trim() ?? '';
    final addressLine2 = address['line2']?.toString().trim() ?? '';
    final addressCity = address['city']?.toString().trim() ?? '';
    final addressState = address['state']?.toString().trim() ?? '';
    final addressZip =
        (address['postal_code'] ?? address['zip'])?.toString().trim() ?? '';
    final addressText = <String>[
      if (addressLine1.isNotEmpty) addressLine1,
      if (addressLine2.isNotEmpty) addressLine2,
      if (addressCity.isNotEmpty ||
          addressState.isNotEmpty ||
          addressZip.isNotEmpty)
        <String>[
          if (addressCity.isNotEmpty) addressCity,
          if (addressState.isNotEmpty) addressState,
          if (addressZip.isNotEmpty) addressZip,
        ].join(' '),
    ].join('\n');

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: BriskersColors.customers.withValues(alpha: 0.12),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '${customer['name'] ?? 'Customer'}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (customer['problem_flag'] == true) ...[
              const SizedBox(width: 6),
              const Icon(Icons.flag, color: Colors.red, size: 20),
            ],
          ],
        ),
      ),
      floatingActionButton: _data == null || !_onlineReady
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
                  if (_showingLocal)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: BriskersColors.customers.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 18),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Showing saved customer and vehicle data • edits save locally and sync when reconnected',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${customer['name'] ?? ''}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (customer['problem_flag'] == true)
                            const Icon(Icons.flag, color: Colors.red),
                        ],
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
                          if (addressText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 17),
                                  const SizedBox(width: 5),
                                  Expanded(child: Text(addressText)),
                                ],
                              ),
                            ),
                          if (_canEditLocal) ...[
                            const SizedBox(height: 2),
                            const Text('Tap to edit'),
                          ],
                        ],
                      ),
                      trailing: _canEditLocal
                          ? const Icon(Icons.edit_outlined)
                          : null,
                      onTap: _canEditLocal
                          ? () => _editCustomer(customer)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: const Text(
                            'Problem customer',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Show a red flag beside this customer throughout Briskers.',
                          ),
                          value: customer['problem_flag'] == true,
                          onChanged:
                              _canEditLocal ? (_) => _editProblemFlag() : null,
                        ),
                        if (customer['problem_flag'] == true)
                          ListTile(
                            leading: const Icon(
                              Icons.flag,
                              color: Colors.red,
                            ),
                            title: const Text('Flag reason / note'),
                            subtitle: Text(
                              (customer['problem_flag_note']?.toString() ?? '')
                                      .trim()
                                      .isEmpty
                                  ? 'Tap to add a reason'
                                  : customer['problem_flag_note'].toString(),
                            ),
                            trailing: _canEditLocal
                                ? const Icon(Icons.edit_outlined)
                                : null,
                            onTap:
                                _canEditLocal ? _editProblemFlag : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  CustomerVehiclesSection(
                    vehicles: vehicles,
                    onAdd: _addVehicle,
                    onEdit: _editVehicle,
                    enabled: _canEditLocal,
                  ),
                  const SizedBox(height: 18),
                  if (BriskersConnectionModeController.instance.forceOffline)
                    _offlineCustomerSections()
                  else ...[
                    CustomerVehicleFindingsSection(
                      businessId: widget.businessId,
                      customerId: widget.customerId,
                      vehicles: vehicles,
                    ),
                    const SizedBox(height: 18),
                    CustomerNotesSection(
                      businessId: widget.businessId,
                      customerId: widget.customerId,
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
                      vehicles: vehicles,
                    ),
                    if (_onlineReady) ...[
                      const SizedBox(height: 18),
                      CustomerAccountSection(
                        businessId: widget.businessId,
                        customerId: widget.customerId,
                        onDeleted: () =>
                            Navigator.pop(context, true),
                      ),
                    ],
                  ],
                  const SizedBox(height: 96),
                ],
              ),
            ),
    );
  }
}
