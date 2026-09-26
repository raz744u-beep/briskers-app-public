import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/briskers_colors.dart';
import '../../core/employee_role_style.dart';
import '../../core/job_status_style.dart';
import '../../services/briskers_api.dart';
import 'job_document_screen.dart';

class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({
    super.key,
    required this.businessId,
    required this.jobId,
    required this.roleCode,
  });

  final String businessId;
  final String jobId;
  final String roleCode;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _job;
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _statuses = const [];
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _findings = const [];
  final ImagePicker _picker = ImagePicker();

  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _busy = false;
  bool _complaintExpanded = false;
  bool _workExpanded = false;
  String? _error;

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  bool get _canSeeFinancial => _canManage;
  bool get _mechanic => widget.roleCode == 'mechanic';
  bool get _owner => widget.roleCode == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final job = await _api.jobDetail(widget.businessId, widget.jobId);
      final statuses = await _api.jobStatuses(widget.businessId);

      List<Map<String, dynamic>> employees = const [];
      List<Map<String, dynamic>> documents = const [];
      List<Map<String, dynamic>> findings = const [];

      if (_canManage) {
        try {
          employees = await _api.assignableEmployees(widget.businessId);
        } catch (_) {
          employees = const [];
        }
      }

      if (_canSeeFinancial) {
        try {
          documents = await _api.jobDocuments(
            widget.businessId,
            widget.jobId,
          );
        } catch (_) {
          documents = const [];
        }
      }

      final vehicleId = job['vehicle_id']?.toString();
      if (vehicleId != null && vehicleId.isNotEmpty) {
        try {
          findings = await _api.vehicleFindings(
            widget.businessId,
            vehicleId,
          );
        } catch (_) {
          findings = const [];
        }
      }

      if (!mounted) return;
      setState(() {
        _job = job;
        _employees = employees;
        _statuses = statuses;
        _documents = documents;
        _findings = findings;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(Object? raw) {
    final amount = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(amount);
  }

  String _dateTime(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '';
    return DateFormat('MMM d, yyyy • h:mm a').format(date.toLocal());
  }

  String _hours(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  Future<void> _updateCore({
    required String customerId,
    required String? vehicleId,
    required num plannedHours,
    required String requestedWork,
  }) async {
    if (_job == null) return;
    await _api.updateJob(
      widget.businessId,
      widget.jobId,
      customerId: customerId,
      vehicleId: vehicleId,
      title: _job!['title']?.toString() ?? 'Job',
      requestedWork: requestedWork,
      plannedHours: plannedHours,
    );
  }

  Future<Map<String, dynamic>?> _pickCustomer() async {
    final customers = await _api.customers(widget.businessId, limit: 200);
    if (!mounted) return null;
    var query = '';
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = customers.where((customer) {
            final name = customer['display_name']?.toString() ?? '';
            return query.isEmpty ||
                name.toLowerCase().contains(query.toLowerCase());
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select customer',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search customers',
                      ),
                      onChanged: (value) => setSheetState(() => query = value.trim()),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final customer = visible[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(customer['display_name']?.toString() ?? ''),
                          subtitle: Text(
                            '${customer['vehicle_count'] ?? 0} vehicle(s)',
                          ),
                          onTap: () => Navigator.pop(sheetContext, customer),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _pickVehicleForCustomer(
    String customerId,
  ) async {
    final detail = await _api.customerDetail(widget.businessId, customerId);
    final vehicles = List<dynamic>.from(detail['vehicles'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    if (!mounted) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Select vehicle',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            if (vehicles.isEmpty)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('This customer has no vehicles yet.'),
              ),
            ...vehicles.map((vehicle) {
              final label = <String>[
                if (vehicle['year'] != null) vehicle['year'].toString(),
                if ((vehicle['make']?.toString() ?? '').isNotEmpty)
                  vehicle['make'].toString(),
                if ((vehicle['model']?.toString() ?? '').isNotEmpty)
                  vehicle['model'].toString(),
              ].join(' ');
              return ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(label.isEmpty ? 'Vehicle' : label),
                subtitle: (vehicle['vin']?.toString() ?? '').isEmpty
                    ? null
                    : Text('VIN: ${vehicle['vin']}'),
                onTap: () => Navigator.pop(sheetContext, vehicle),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _changeCustomerVehicle() async {
    if (!_canManage || _job == null || _busy) return;
    final customer = await _pickCustomer();
    if (customer == null || !mounted) return;
    final customerId = customer['id']?.toString() ?? '';
    if (customerId.isEmpty) return;

    final vehicle = await _pickVehicleForCustomer(customerId);
    if (vehicle == null) return;

    await _run(() => _updateCore(
          customerId: customerId,
          vehicleId: vehicle['id']?.toString(),
          plannedHours: num.tryParse(_job!['planned_hours']?.toString() ?? '') ?? 0,
          requestedWork: _job!['requested_work']?.toString() ?? '',
        ));
  }

  Future<void> _changeVehicle() async {
    if (!_canManage || _job == null || _busy) return;
    final customerId = _job!['customer_id']?.toString() ?? '';
    if (customerId.isEmpty) return;
    final vehicle = await _pickVehicleForCustomer(customerId);
    if (vehicle == null) return;

    await _run(() => _updateCore(
          customerId: customerId,
          vehicleId: vehicle['id']?.toString(),
          plannedHours: num.tryParse(_job!['planned_hours']?.toString() ?? '') ?? 0,
          requestedWork: _job!['requested_work']?.toString() ?? '',
        ));
  }

  Future<void> _changePlannedHours() async {
    if (!_canManage || _job == null || _busy) return;
    final controller = TextEditingController(
      text: _hours(_job!['planned_hours']),
    );
    final value = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Planned time'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Hours',
            suffixText: 'hr',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final hours = num.tryParse(controller.text.trim());
              if (hours != null && hours >= 0) {
                Navigator.pop(dialogContext, hours);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || _job == null) return;

    await _run(() => _updateCore(
          customerId: _job!['customer_id'].toString(),
          vehicleId: _job!['vehicle_id']?.toString(),
          plannedHours: value,
          requestedWork: _job!['requested_work']?.toString() ?? '',
        ));
  }

  Future<String?> _editTextSheet({
    required String title,
    required String initialValue,
    required String hint,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: 9,
                decoration: InputDecoration(hintText: hint),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, controller.text.trim()),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _changeStatus(String code) async {
    if (!_canManage || _job == null) return;
    if (code == _job!['status']?.toString()) return;

    String? note;
    if (_job!['status']?.toString() == 'completed' &&
        code == 'needs_recheck') {
      var reason = '';
      note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reopen job'),
          content: TextFormField(
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            onChanged: (value) => reason = value,
            decoration: const InputDecoration(
              labelText: 'Reason for recheck',
              hintText: 'Example: Customer returned with the same noise',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, reason.trim()),
              child: const Text('Reopen'),
            ),
          ],
        ),
      );
      if (note == null) return;
    }

    await _run(() async {
      await _api.changeJobStatus(
        widget.businessId,
        widget.jobId,
        code,
        note: note,
      );
    });
  }

  Future<void> _changeAssignment() async {
    if (!_canManage || _busy) return;

    final assignments = List<dynamic>.from(
      _job?['assignments'] ?? const [],
    );
    final currentId = assignments.isEmpty
        ? null
        : Map<String, dynamic>.from(assignments.first as Map)['employee_id']
            ?.toString();

    final selected = await showModalBottomSheet<String?>(
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'Assign mechanic / employee',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_off_outlined),
                  ),
                  title: const Text('Unassigned'),
                  trailing: currentId == null
                      ? const Icon(Icons.check, color: BriskersColors.jobs)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, ''),
                ),
                const Divider(),
                ..._employees.map((employee) {
                  final position =
                      employee['position_name']?.toString() ?? 'Employee';
                  final roleStyle = employeeRoleStyle(position);
                  final id = employee['id']?.toString() ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          roleStyle.color.withValues(alpha: 0.14),
                      child: Icon(roleStyle.icon, color: roleStyle.color),
                    ),
                    title: Text(employee['name']?.toString() ?? ''),
                    subtitle: Text(position),
                    trailing: id == currentId
                        ? const Icon(Icons.check, color: BriskersColors.jobs)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, id),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    await _run(() async {
      if (selected.isEmpty) {
        await _api.clearJobAssignments(widget.businessId, widget.jobId);
      } else {
        await _api.setPrimaryJobEmployee(
          widget.businessId,
          widget.jobId,
          selected,
        );
      }
    });
  }

  Future<void> _requestJob() async {
    if (!_mechanic) return;
    await _run(() async {
      await _api.requestJobAssignment(widget.businessId, widget.jobId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job request sent to the office.'),
          ),
        );
      }
    });
  }

  Future<void> _decideRequest(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    if (!_canManage) return;
    await _run(() async {
      await _api.decideJobAssignmentRequest(
        widget.businessId,
        request['id'].toString(),
        approve: approve,
      );
    });
  }

  Future<void> _editComplaint() async {
    if (!_canManage || _job == null || _busy) return;
    final value = await _editTextSheet(
      title: 'Customer complaint',
      initialValue: _job!['requested_work']?.toString() ?? '',
      hint: 'What did the customer ask us to check or repair?',
    );
    if (value == null || _job == null) return;

    await _run(() => _updateCore(
          customerId: _job!['customer_id'].toString(),
          vehicleId: _job!['vehicle_id']?.toString(),
          plannedHours: num.tryParse(_job!['planned_hours']?.toString() ?? '') ?? 0,
          requestedWork: value,
        ));
  }

  Future<void> _editWorkSummary() async {
    final visits = List<dynamic>.from(_job?['visits'] ?? const []);
    if (visits.isEmpty || _busy) return;
    final current = Map<String, dynamic>.from(visits.first as Map);
    if (current['closed_at'] != null) return;

    final value = await _editTextSheet(
      title: 'Work performed',
      initialValue: current['work_summary']?.toString() ?? '',
      hint: 'Describe the work completed on this visit.',
    );
    if (value == null) return;

    await _run(() => _api.updateCurrentVisitWorkSummary(
          widget.businessId,
          widget.jobId,
          workSummary: value,
        ));
  }

  String _imageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addFinding() async {
    if (!_canManage || _job == null || _busy) return;
    if ((_job!['vehicle_id']?.toString() ?? '').isEmpty) {
      setState(() => _error = 'Select a vehicle before adding a finding.');
      return;
    }

    final controller = TextEditingController();
    var includeOnInvoice = false;
    final photos = <XFile>[];

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add vehicle finding',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Finding',
                      hintText: 'Example: Oil leak visible around valve cover',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include on invoice notes'),
                    value: includeOnInvoice,
                    onChanged: (value) => setSheetState(
                      () => includeOnInvoice = value == true,
                    ),
                  ),
                  if (photos.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        photos.length == 1
                            ? '1 photo selected'
                            : '${photos.length} photos selected',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _picker.pickMultiImage(
                              imageQuality: 88,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (picked.isNotEmpty) {
                              setSheetState(() => photos.addAll(picked));
                            }
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final photo = await _picker.pickImage(
                              source: ImageSource.camera,
                              imageQuality: 88,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (photo != null) {
                              setSheetState(() => photos.add(photo));
                            }
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (controller.text.trim().isEmpty) return;
                        Navigator.pop(sheetContext, true);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add finding'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final body = controller.text.trim();
    controller.dispose();
    if (save != true || body.isEmpty) return;

    await _run(() async {
      final findingId = await _api.createVehicleFinding(
        widget.businessId,
        widget.jobId,
        body: body,
        includeOnInvoice: includeOnInvoice,
      );
      for (final photo in photos) {
        await _api.uploadCustomerNotePhoto(
          widget.businessId,
          findingId,
          filename: photo.name,
          mimeType: _imageMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }
    });
  }

  Future<void> _toggleFindingInvoice(
    Map<String, dynamic> finding,
    bool include,
  ) async {
    await _run(() => _api.setVehicleFindingInvoiceFlag(
          widget.businessId,
          finding['id'].toString(),
          include,
        ));
  }

  Future<void> _resolveFinding(Map<String, dynamic> finding) async {
    await _run(() => _api.resolveVehicleFinding(
          widget.businessId,
          finding['id'].toString(),
          widget.jobId,
        ));
  }

  Future<void> _reopenFinding(Map<String, dynamic> finding) async {
    await _run(() => _api.reopenVehicleFinding(
          widget.businessId,
          finding['id'].toString(),
        ));
  }

  Future<void> _deleteFinding(Map<String, dynamic> finding) async {
    if (!_owner) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete finding?'),
        content: const Text(
          'Delete this finding permanently? Normally a repaired issue should be marked Resolved instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _api.deleteVehicleFinding(
          widget.businessId,
          finding['id'].toString(),
        ));
  }

  Future<void> _createEstimate() async {
    if (!_canSeeFinancial) return;
    String? id;
    await _run(() async {
      id = await _api.createEstimate(widget.businessId, widget.jobId);
    });
    if (!mounted || id == null) return;
    await _openDocument(id!);
  }

  Future<void> _createInvoice() async {
    if (!_canSeeFinancial) return;
    String? id;
    await _run(() async {
      id = await _api.createInvoice(widget.businessId, widget.jobId);
    });
    if (!mounted || id == null) return;
    await _openDocument(id!);
  }

  Future<void> _openDocument(String documentId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: documentId,
          isOwner: _owner,
        ),
      ),
    );
    await _load();
  }

  void _scrollFinancialActionsIntoView() {
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || !_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<Map<String, dynamic>> _availableStatuses() {
    final current = _job?['status']?.toString();
    if (current == 'completed') {
      return _statuses
          .where((status) => status['code']?.toString() == 'needs_recheck')
          .toList();
    }
    return _statuses;
  }

  Widget _statusControl() {
    final color = colorFromHex(_job?['status_color']?.toString());
    final icon = jobStatusIcon(_job?['status_icon']?.toString());
    final name = _job?['status_name']?.toString() ?? 'Status';

    final child = Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_canManage) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, color: color, size: 17),
          ],
        ],
      ),
    );

    if (!_canManage || _busy) return child;

    return PopupMenuButton<String>(
      tooltip: 'Change job status',
      padding: EdgeInsets.zero,
      onSelected: _changeStatus,
      itemBuilder: (context) => _availableStatuses().map((status) {
        final itemColor = colorFromHex(status['color_hex']?.toString());
        return PopupMenuItem<String>(
          value: status['code']?.toString(),
          child: Row(
            children: [
              Icon(
                jobStatusIcon(status['icon_key']?.toString()),
                color: itemColor,
              ),
              const SizedBox(width: 10),
              Text(status['name']?.toString() ?? ''),
            ],
          ),
        );
      }).toList(),
      child: child,
    );
  }

  Widget _summaryCard({
    required String customerName,
    required String vehicle,
    required String vin,
    required String title,
    required Map<String, dynamic>? assignment,
  }) {
    final employeeName = assignment == null
        ? 'Unassigned'
        : assignment['employee_name']?.toString() ?? 'Assigned';
    final employeePosition =
        assignment?['position']?.toString() ?? 'Employee';
    final roleStyle = employeeRoleStyle(employeePosition);
    final statusColor = colorFromHex(_job?['status_color']?.toString());
    final cardTint = Color.alphaBlend(
      statusColor.withValues(alpha: 0.12),
      const Color(0xFFFCFCFB),
    );

    Widget editableRow({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
      String? subtitle,
      VoidCallback? onTap,
    }) {
      final enabled = onTap != null && !_busy;
      return InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: color.withValues(alpha: 0.13),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right, size: 22),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  heightFactor: 0.88,
                  child: Opacity(
                    opacity: 0.27,
                    child: Image.asset(
                      'assets/job_car_watermark.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                editableRow(
                  icon: Icons.person_outline,
                  color: statusColor,
                  label: 'Customer',
                  value: customerName.isEmpty ? 'Customer' : customerName,
                  onTap: _canManage ? _changeCustomerVehicle : null,
                ),
                Divider(color: statusColor.withValues(alpha: 0.20)),
                editableRow(
                  icon: Icons.directions_car_outlined,
                  color: statusColor,
                  label: 'Vehicle',
                  value: vehicle.isEmpty ? 'No vehicle' : vehicle,
                  subtitle: vin.isEmpty ? 'VIN: Not entered' : 'VIN: $vin',
                  onTap: _canManage ? _changeVehicle : null,
                ),
                Divider(color: statusColor.withValues(alpha: 0.20)),
                if (title.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _canManage && !_busy ? _changeAssignment : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                roleStyle.icon,
                                color: roleStyle.color,
                                size: 21,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      employeePosition,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      employeeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_canManage)
                                const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 42,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: statusColor.withValues(alpha: 0.25),
                    ),
                    SizedBox(
                      width: 125,
                      child: InkWell(
                        onTap: _canManage && !_busy ? _changePlannedHours : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                color: statusColor,
                                size: 21,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Planned time',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '${_hours(_job!['planned_hours'])} hr',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_canManage)
                                const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _findingsCard() {
    final open = _findings
        .where((finding) => finding['status']?.toString() == 'open')
        .toList();
    final resolved = _findings
        .where((finding) => finding['status']?.toString() == 'resolved')
        .toList();

    Widget findingTile(Map<String, dynamic> finding) {
      final isOpen = finding['status']?.toString() == 'open';
      final attachments = List<dynamic>.from(
        finding['attachments'] ?? const [],
      );
      final foundJob = finding['found_job_number']?.toString() ?? '';
      final resolvedJob =
          finding['resolved_job_number']?.toString() ?? '';
      final created = _dateTime(finding['created_at']);
      final resolvedAt = _dateTime(finding['resolved_at']);

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isOpen
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: isOpen ? Colors.deepOrange : Colors.green,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    finding['body']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_owner)
                  PopupMenuButton<String>(
                    tooltip: 'Finding actions',
                    onSelected: (value) {
                      if (value == 'delete') _deleteFinding(finding);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete finding'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              <String>[
                if (foundJob.isNotEmpty) 'Found $foundJob',
                if (created.isNotEmpty) created,
                if (attachments.isNotEmpty)
                  attachments.length == 1
                      ? '1 photo'
                      : '${attachments.length} photos',
                if (!isOpen && resolvedJob.isNotEmpty)
                  'Resolved $resolvedJob',
                if (!isOpen && resolvedAt.isNotEmpty) resolvedAt,
              ].join(' • '),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
            if (isOpen && _canManage) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Include on invoice',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      value: finding['include_on_invoice'] == true,
                      onChanged: _busy
                          ? null
                          : (value) => _toggleFindingInvoice(
                                finding,
                                value == true,
                              ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                        _busy ? null : () => _resolveFinding(finding),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Resolve'),
                  ),
                ],
              ),
            ] else if (!isOpen && _canManage) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed:
                      _busy ? null : () => _reopenFinding(finding),
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Reopen'),
                ),
              ),
            ],
            const Divider(height: 1),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: open.isNotEmpty,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.12),
          child: const Icon(
            Icons.car_repair_outlined,
            color: Colors.deepOrange,
          ),
        ),
        title: const Text(
          'Vehicle findings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          open.isEmpty
              ? 'No open findings'
              : open.length == 1
                  ? '1 open finding'
                  : '${open.length} open findings',
        ),
        trailing: _canManage
            ? IconButton(
                tooltip: 'Add finding',
                onPressed: _busy ? null : _addFinding,
                icon: const Icon(Icons.add_circle_outline),
              )
            : null,
        children: [
          if (open.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No unresolved issues are recorded for this vehicle.'),
              ),
            )
          else
            ...open.map(findingTile),
          if (resolved.isNotEmpty)
            ExpansionTile(
              initiallyExpanded: false,
              title: Text(
                resolved.length == 1
                    ? 'Resolved finding'
                    : 'Resolved findings (${resolved.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: resolved.map(findingTile).toList(),
            ),
        ],
      ),
    );
  }

  Widget _previewCard({
    required IconData icon,
    required String title,
    required String text,
    required bool expanded,
    required VoidCallback onToggle,
    VoidCallback? onEdit,
    String emptyText = 'Nothing entered yet.',
  }) {
    final displayText = text.trim().isEmpty ? emptyText : text.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: BriskersColors.jobs.withValues(alpha: 0.12),
                child: Icon(icon, color: BriskersColors.jobs, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 23,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      displayText,
                      maxLines: expanded ? null : 2,
                      overflow:
                          expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (expanded && onEdit != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _busy ? null : onEdit,
                          icon: const Icon(Icons.edit_note_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10),
          title: const Text('Job'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_job == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10),
          title: const Text('Job'),
        ),
        body: Center(child: Text(_error ?? 'Job not found.')),
      );
    }

    final assignments = List<dynamic>.from(_job!['assignments'] ?? const []);
    final assignment = assignments.isEmpty
        ? null
        : Map<String, dynamic>.from(assignments.first as Map);

    final requests = List<dynamic>.from(
      _job!['pending_requests'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final visits = List<dynamic>.from(_job!['visits'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    final currentVisit = visits.isEmpty ? null : visits.first;
    final customerName = _job!['customer_name']?.toString().trim() ?? '';
    final vehicle = _job!['vehicle']?.toString().trim() ?? '';
    final vin = _job!['vehicle_vin']?.toString().trim() ?? '';
    final jobNumber = _job!['job_number']?.toString().trim() ?? '';
    final jobTitle = _job!['title']?.toString().trim() ?? '';
    final complaint = _job!['requested_work']?.toString().trim() ?? '';
    final workSummary =
        currentVisit?['work_summary']?.toString().trim() ?? '';
    final unassigned = _job!['is_unassigned'] == true;
    final statusColor = colorFromHex(_job!['status_color']?.toString());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: statusColor.withValues(alpha: 0.08),
        titleSpacing: 0,
        title: Text(
          jobNumber.isEmpty ? 'Job' : 'Job $jobNumber',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 21,
          ),
        ),
        actions: [
          Center(child: _statusControl()),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
          children: [
            _summaryCard(
              customerName: customerName,
              vehicle: vehicle,
              vin: vin,
              title: jobTitle,
              assignment: assignment,
            ),
            const SizedBox(height: 10),
            _findingsCard(),
            if (_mechanic && unassigned) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _requestJob,
                  icon: const Icon(Icons.pan_tool_alt_outlined),
                  label: const Text('Request this job'),
                ),
              ),
            ],
            if (_canManage && requests.isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: BriskersColors.jobs,
                  ),
                  title: Text(
                    requests.length == 1
                        ? '1 mechanic requested this job'
                        : '${requests.length} mechanics requested this job',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  children: requests.map((request) {
                    final position =
                        request['position']?.toString() ?? 'Mechanic';
                    final roleStyle = employeeRoleStyle(position);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            roleStyle.color.withValues(alpha: 0.14),
                        child: Icon(roleStyle.icon, color: roleStyle.color),
                      ),
                      title: Text(
                        request['employee_name']?.toString() ?? '',
                      ),
                      subtitle: Text(position),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Deny',
                            onPressed: _busy
                                ? null
                                : () => _decideRequest(request, false),
                            icon: const Icon(Icons.close),
                          ),
                          IconButton(
                            tooltip: 'Assign',
                            onPressed: _busy
                                ? null
                                : () => _decideRequest(request, true),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              color: BriskersColors.jobs,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _previewCard(
              icon: Icons.description_outlined,
              title: 'Customer complaint',
              text: complaint,
              expanded: _complaintExpanded,
              onToggle: () => setState(
                () => _complaintExpanded = !_complaintExpanded,
              ),
              onEdit: _canManage ? _editComplaint : null,
              emptyText: 'No customer complaint entered.',
            ),
            const SizedBox(height: 10),
            _previewCard(
              icon: Icons.build_outlined,
              title: 'Work performed',
              text: workSummary,
              expanded: _workExpanded,
              onToggle: () => setState(
                () => _workExpanded = !_workExpanded,
              ),
              onEdit: currentVisit != null &&
                      currentVisit['closed_at'] == null
                  ? _editWorkSummary
                  : null,
              emptyText: 'No work performed entered yet.',
            ),
            if (visits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(
                    Icons.history_outlined,
                    color: BriskersColors.jobs,
                  ),
                  title: const Text(
                    'Work / Visit history',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    visits.length == 1
                        ? '1 shop visit'
                        : '${visits.length} shop visits',
                  ),
                  children: visits.map((visit) {
                    final mechanics = List<dynamic>.from(
                      visit['mechanics'] ?? const [],
                    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

                    final names = mechanics
                        .map((item) => item['employee_name']?.toString() ?? '')
                        .where((name) => name.isNotEmpty)
                        .join(', ');

                    final summary =
                        visit['work_summary']?.toString().trim() ?? '';
                    final reason = visit['reason']?.toString().trim() ?? '';
                    final opened = _dateTime(visit['opened_at']);
                    final closed = _dateTime(visit['closed_at']);

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Visit ${visit['visit_number']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (opened.isNotEmpty)
                            Text(
                              closed.isEmpty
                                  ? 'Started $opened'
                                  : '$opened → $closed',
                            ),
                          if (names.isNotEmpty) Text('Mechanic: $names'),
                          if (reason.isNotEmpty) Text('Reason: $reason'),
                          if (summary.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(summary),
                          ],
                          const Divider(height: 18),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            if (_canSeeFinancial) ...[
              const SizedBox(height: 10),
              Card(
                child: ExpansionTile(
                  initiallyExpanded: false,
                  onExpansionChanged: (expanded) {
                    if (expanded) _scrollFinancialActionsIntoView();
                  },
                  leading: const Icon(
                    Icons.description_outlined,
                    color: BriskersColors.invoices,
                  ),
                  title: const Text(
                    'Estimate / Invoice',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _documents.isEmpty
                        ? 'No documents yet'
                        : '${_documents.length} document(s)',
                  ),
                  children: [
                    ..._documents.map((document) {
                      final estimate =
                          document['kind']?.toString() == 'estimate';
                      final color = estimate
                          ? BriskersColors.estimates
                          : BriskersColors.invoices;
                      final number =
                          document['document_number']?.toString() ?? '';
                      final paid = num.tryParse(
                            document['paid_amount']?.toString() ?? '',
                          ) ??
                          0;
                      final pending = num.tryParse(
                            document['pending_payment']?.toString() ?? '',
                          ) ??
                          0;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.14),
                          child: Icon(
                            estimate
                                ? Icons.request_quote_outlined
                                : Icons.receipt_long_outlined,
                            color: color,
                          ),
                        ),
                        title: Text(
                          number.isEmpty
                              ? (estimate ? 'Estimate' : 'Invoice')
                              : (estimate
                                  ? 'Estimate #$number'
                                  : 'Invoice #$number'),
                        ),
                        subtitle: Text(
                          <String>[
                            _money(document['total_amount']),
                            if (document['converted'] == true) 'Converted',
                            if (!estimate && paid > 0)
                              'Paid ${_money(paid)}',
                            if (!estimate && pending > 0)
                              'Payment entered ${_money(pending)}',
                          ].join(' • '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDocument(
                          document['id'].toString(),
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _createEstimate,
                              icon: const Icon(
                                Icons.request_quote_outlined,
                                color: BriskersColors.estimates,
                              ),
                              label: const Text('Estimate'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _createInvoice,
                              icon: const Icon(
                                Icons.receipt_long_outlined,
                                color: BriskersColors.invoices,
                              ),
                              label: const Text('Invoice'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
