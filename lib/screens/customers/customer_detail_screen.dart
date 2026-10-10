import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/briskers_colors.dart';
import '../../core/connection_mode.dart';
import '../../core/formatters.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/local_customer_repository.dart';
import '../../services/offline_customer_vehicle_admin_service.dart';
import '../../services/offline_document_draft_service.dart';
import '../../local/local_database_provider.dart';
import '../appointments/appointment_create_screen.dart';
import '../jobs/job_create_screen.dart';
import '../jobs/job_document_screen.dart';
import '../jobs/blank_invoice_setup_screen.dart';
import '../jobs/estimate_job_setup_screen.dart';
import 'customer_quick_actions.dart';
import 'customer_problem_flag_card.dart';
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
    required this.roleCode,
  });

  final String businessId;
  final String customerId;
  final String roleCode;

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
  final OfflineDocumentDraftService _offlineDrafts = OfflineDocumentDraftService();

  Map<String, dynamic>? _data;
  String? _error;
  bool _onlineReady = false;
  bool _showingLocal = false;

  bool get _canEditLocal => _data != null && _canManageQuickActions;
  bool get _canManageQuickActions => canManageCustomerActions(widget.roleCode);
  final GlobalKey _notesSectionKey = GlobalKey();
  bool _expandQuickNotes = false;

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
      'appointments': appointments,
      'history': history,
    };
  }


  Widget _offlineCountCard({
    required IconData icon,
    required String title,
    required String emptyText,
    required List<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic>)? label
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
      // Full customer/vehicle dataset sync belongs to the background Sync Now
      // workflow, not to opening every individual customer profile.
      if (!await _localCustomers.hasBootstrap(widget.businessId)) {
        await _sync.pull(widget.businessId);
      }
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
          fetchedDetail: fullDetail,
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

  Future<void> _createInvoiceForCustomer() async {
    if (_data == null || !_canManageQuickActions) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const <String, dynamic>{},
    );
    final vehicles = List<dynamic>.from(_data?['vehicles'] ?? const []);
    final invoiceId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BlankInvoiceSetupScreen(
          businessId: widget.businessId,
          initialCustomerId: widget.customerId,
          initialCustomerName: customer['name']?.toString() ?? 'Customer',
          initialVehicles: vehicles,
        ),
      ),
    );
    if (!mounted || invoiceId == null || invoiceId.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: _canManageQuickActions,
          initialAction: 'add_item',
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _createEstimateForCustomer() async {
    if (_data == null || !_canManageQuickActions) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const <String, dynamic>{},
    );
    final vehicles = List<dynamic>.from(_data?['vehicles'] ?? const []);
    String? jobId;
    try {
      if (BriskersConnectionModeController.instance.forceOffline) {
        final documentId=await Navigator.push<String>(
          context,MaterialPageRoute(builder:(_)=>BlankInvoiceSetupScreen(
            businessId:widget.businessId,
            kind:'estimate',
            initialCustomerId:widget.customerId,
            initialCustomerName:customer['name']?.toString() ?? 'Customer',
            initialVehicles:vehicles,
          )),
        );
        if (!mounted || documentId==null) return;
        await Navigator.push<void>(context,MaterialPageRoute(
          builder:(_)=>JobDocumentScreen(
            businessId:widget.businessId,
            documentId:documentId,
            isOwner:widget.roleCode=='owner',
            canManageExpenses:_canManageQuickActions,
            initialAction:'add_item',
          ),
        ));
        return;
      }
      final history = await _api.customerServiceHistory(
        widget.businessId, widget.customerId,
      );
      if (!mounted) return;
      final active = history.where((job) {
        final status = job['status']?.toString() ?? '';
        return status != 'completed' && status != 'cancelled';
      }).toList();

      if (active.isNotEmpty) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Create estimate'),
                  subtitle: Text('Existing Job or standalone estimate.'),
                ),
                ListTile(
                  leading: const Icon(Icons.build_outlined),
                  title: const Text('Existing customer job'),
                  onTap: () => Navigator.pop(sheetContext, 'existing'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('New Estimate (no Job)'),
                  onTap: () => Navigator.pop(sheetContext, 'new'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'existing') {
          final picked = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.65,
                child: ListView(
                  children: [
                    const ListTile(title: Text('Select an active job')),
                    for (final job in active)
                      ListTile(
                        leading: const Icon(Icons.build_outlined),
                        title: Text(
                          '${job['job_number'] ?? ''} • ${job['title'] ?? 'Job'}',
                        ),
                        subtitle: Text(job['vehicle']?.toString() ?? ''),
                        onTap: () => Navigator.pop(sheetContext, job),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (!mounted || picked == null) return;
          jobId = picked['id']?.toString();
        }
      }

      if (jobId == null) {
        final documentId=await Navigator.push<String>(
          context,
          MaterialPageRoute(builder:(_)=>BlankInvoiceSetupScreen(
            businessId:widget.businessId,
            kind:'estimate',
            initialCustomerId:widget.customerId,
            initialCustomerName:customer['name']?.toString() ?? 'Customer',
            initialVehicles:vehicles,
          )),
        );
        if (!mounted || documentId==null || documentId.isEmpty) return;
        await Navigator.push<void>(
          context,MaterialPageRoute(builder:(_)=>JobDocumentScreen(
            businessId:widget.businessId,
            documentId:documentId,
            isOwner:widget.roleCode=='owner',
            canManageExpenses:_canManageQuickActions,
            initialAction:'add_item',
          )),
        );
        if (mounted) await _load();
        return;
      }
      if (jobId == null || jobId.isEmpty) {
        throw StateError('No job was selected for the estimate.');
      }
      final documentId = await _api.createEstimate(widget.businessId, jobId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDocumentScreen(
            businessId: widget.businessId,
            documentId: documentId,
            isOwner: widget.roleCode == 'owner',
            canManageExpenses: _canManageQuickActions,
            initialAction: 'add_item',
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create estimate: $error')),
      );
    }
  }

  Future<void> _createOfflineEstimateForCustomer() async {
    final saved = await localDatabase.customSelect(
      '''
      SELECT id, job_number, title, vehicle_label
      FROM local_jobs
      WHERE business_id=? AND customer_id=?
        AND status NOT IN ('completed','cancelled')
      ORDER BY created_at DESC
      LIMIT 50
      ''',
      variables: [
        Variable<String>(widget.businessId),
        Variable<String>(widget.customerId),
      ],
    ).get();
    if (!mounted) return;
    if (saved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'To create an estimate offline, this customer needs an existing saved active job. Creating a new job requires an internet connection.',
        )),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.60,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Offline estimate'),
                subtitle: Text('Choose a saved active job.'),
              ),
              for (final job in saved)
                ListTile(
                  leading: const Icon(Icons.build_outlined),
                  title: Text(
                    '${job.readNullable<String>('job_number') ?? ''} • '
                    '${job.read<String>('title')}',
                  ),
                  subtitle: Text(
                    job.readNullable<String>('vehicle_label') ?? '',
                  ),
                  onTap: () => Navigator.pop(
                    sheetContext,job.read<String>('id'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final documentId = await _offlineDrafts.createEstimate(
      widget.businessId,selected,
    );
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: documentId,
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: _canManageQuickActions,
          initialAction: 'add_item',
        ),
      ),
    );
    if (mounted) await _load();
  }

  void _openCustomerNoteComposer() {
    setState(() => _expandQuickNotes = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _notesSectionKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0.08,
        );
      }
    });
  }

  Future<void> _showQuickActions() async {
    if (_data == null || !_canManageQuickActions) return;
    final action = await showModalBottomSheet<CustomerQuickAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => CustomerQuickActionsSheet(
        roleCode: widget.roleCode,
        offline: BriskersConnectionModeController.instance.forceOffline,
        onSelected: (choice) => Navigator.pop(sheetContext, choice),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case CustomerQuickAction.appointment:
        await _scheduleAppointment();
      case CustomerQuickAction.job:
        await _createJob();
      case CustomerQuickAction.estimate:
        await _createEstimateForCustomer();
      case CustomerQuickAction.invoice:
        await _createInvoiceForCustomer();
      case CustomerQuickAction.vehicle:
        await _addVehicle();
      case CustomerQuickAction.note:
        _openCustomerNoteComposer();
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
      floatingActionButton: _data == null || !_canManageQuickActions
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
                  CustomerProblemFlagCard(
                    customerId: widget.customerId,
                    flagged: customer['problem_flag'] == true,
                    note: customer['problem_flag_note']?.toString() ?? '',
                    canEdit: _canEditLocal,
                    onEdit: _editProblemFlag,
                  ),
                  const SizedBox(height: 18),
                  CustomerVehiclesSection(
                    vehicles: vehicles,
                    onAdd: _addVehicle,
                    onEdit: _editVehicle,
                    enabled: _canEditLocal,
                  ),
                  const SizedBox(height: 18),
                  CustomerVehicleFindingsSection(
                    businessId: widget.businessId,
                    customerId: widget.customerId,
                    vehicles: vehicles,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    key: _notesSectionKey,
                    child: KeyedSubtree(
                      key: ValueKey(_expandQuickNotes),
                      child: CustomerNotesSection(
                        businessId: widget.businessId,
                        customerId: widget.customerId,
                        initiallyExpanded: _expandQuickNotes,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (BriskersConnectionModeController.instance.forceOffline)
                    _offlineCustomerSections()
                  else ...[
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
                    if (_onlineReady && widget.roleCode == 'owner') ...[
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
