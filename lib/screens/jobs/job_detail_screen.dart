import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/briskers_colors.dart';
import '../../core/employee_role_style.dart';
import '../../core/job_status_style.dart';
import '../../services/briskers_api.dart';
import '../expenses/expense_detail_screen.dart';
import '../expenses/expense_entry_screen.dart';
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
  Map<String, dynamic>? _profitability;
  Map<String, dynamic>? _preInspection;
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _statuses = const [];
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _findings = const [];
  List<Map<String, dynamic>> _jobExpenses = const [];
  final ImagePicker _picker = ImagePicker();

  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  VoidCallback? _modalRefresh;

  bool _jobCapability(String key) {
    final raw = _job?['capabilities'];
    if (raw is! Map) return false;
    return raw[key] == true;
  }

  bool get _canManage => _job == null
      ? widget.roleCode == 'owner' ||
          widget.roleCode == 'manager' ||
          widget.roleCode == 'office'
      : _jobCapability('manage_job');

  bool get _canSeeFinancial => _job == null
      ? widget.roleCode == 'owner' ||
          widget.roleCode == 'manager' ||
          widget.roleCode == 'office'
      : _jobCapability('view_financial');

  bool get _canRequestJob => _jobCapability('request_job');
  bool get _canEditWork => _jobCapability('edit_work');
  bool get _canEditFindings => _jobCapability('edit_findings');
  bool get _canEditInspection => _jobCapability('edit_inspection');
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
      final rawCapabilities = job['capabilities'];
      final capabilities = rawCapabilities is Map
          ? Map<String, dynamic>.from(rawCapabilities)
          : const <String, dynamic>{};
      bool capability(String key) => capabilities[key] == true;
      final canManage = capability('manage_job');
      final canSeeFinancial = capability('view_financial');

      List<Map<String, dynamic>> employees = const [];
      List<Map<String, dynamic>> documents = const [];
      List<Map<String, dynamic>> findings = const [];
      List<Map<String, dynamic>> jobExpenses = const [];
      Map<String, dynamic>? profitability;
      Map<String, dynamic>? preInspection;

      if (canManage) {
        try {
          employees = await _api.assignableEmployees(widget.businessId);
        } catch (_) {
          employees = const [];
        }
      }

      if (canSeeFinancial) {
        try {
          documents = await _api.jobDocuments(
            widget.businessId,
            widget.jobId,
          );
        } catch (_) {
          documents = const [];
        }

        try {
          final transactions = await _api.transactions(
            widget.businessId,
            limit: 1000,
          );
          jobExpenses = transactions
              .where(
                (row) =>
                    row['direction']?.toString() == 'expense' &&
                    row['job_id']?.toString() == widget.jobId,
              )
              .toList();
        } catch (_) {
          jobExpenses = const [];
        }
      }

      if (_owner) {
        try {
          profitability = await _api.jobProfitability(
            widget.businessId,
            widget.jobId,
          );
        } catch (_) {
          profitability = null;
        }
      }

      try {
        preInspection = await _api.jobPreInspection(widget.businessId, widget.jobId);
      } catch (_) {
        preInspection = null;
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
        _profitability = profitability;
        _preInspection = preInspection;
        _employees = employees;
        _statuses = statuses;
        _documents = documents;
        _findings = findings;
        _jobExpenses = jobExpenses;
        _loading = false;
        _error = null;
      });
      _modalRefresh?.call();
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

  Future<void> _changeJobTitle() async {
    final job = _job;
    if (job == null || !_canManage || _busy) return;

    final controller = TextEditingController(
      text: job['title']?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit job name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Job name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = controller.text.trim();
              if (title.isNotEmpty) Navigator.pop(dialogContext, title);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;

    await _run(() async {
      await _api.updateJob(
        widget.businessId,
        widget.jobId,
        customerId: job['customer_id'].toString(),
        vehicleId: job['vehicle_id']?.toString(),
        title: value,
        requestedWork: job['requested_work']?.toString() ?? '',
        plannedHours:
            num.tryParse(job['planned_hours']?.toString() ?? '') ?? 0,
      );
    });
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
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer['display_name']?.toString() ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (customer['problem_flag'] == true)
                                const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                  size: 18,
                                ),
                            ],
                          ),
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
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('No vehicle'),
              subtitle: vehicles.isEmpty
                  ? const Text('This customer has no vehicles yet.')
                  : null,
              onTap: () => Navigator.pop(
                sheetContext,
                <String, dynamic>{'id': null},
              ),
            ),
            if (vehicles.isNotEmpty) const Divider(),
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

  Future<void> _changeCustomer() async {
    if (!_canManage || _job == null || _busy) return;
    final customer = await _pickCustomer();
    if (customer == null || !mounted) return;

    final customerId = customer['id']?.toString() ?? '';
    if (customerId.isEmpty) return;
    if (customerId == _job!['customer_id']?.toString()) return;

    final detail = await _api.customerDetail(widget.businessId, customerId);
    final vehicles = List<dynamic>.from(detail['vehicles'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    Map<String, dynamic>? vehicle;
    if (vehicles.length == 1) {
      vehicle = vehicles.first;
    } else if (vehicles.length > 1) {
      vehicle = await _pickVehicleForCustomer(customerId);
      if (vehicle == null) return;
    }

    await _run(() => _updateCore(
          customerId: customerId,
          vehicleId: vehicle?['id']?.toString(),
          plannedHours:
              num.tryParse(_job!['planned_hours']?.toString() ?? '') ?? 0,
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
              const SizedBox(height: 5),
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
    if (!_canRequestJob) return;
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
    if (!_canEditWork) return;
    final visits = List<dynamic>.from(_job?['visits'] ?? const []);
    if (visits.isEmpty || _busy) return;
    final current = Map<String, dynamic>.from(visits.first as Map);

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

  Future<void> _editPreInspectionDetails() async {
    if (_job == null || _busy || !_canEditInspection) return;
    final mileage = TextEditingController(text: _preInspection?['odometer']?.toString() ?? _job?['odometer_in']?.toString() ?? '');
    final notes = TextEditingController(text: _preInspection?['notes']?.toString() ?? '');
    final save = await showModalBottomSheet<bool>(context: context, showDragHandle: true, isScrollControlled: true, builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Align(alignment: Alignment.centerLeft, child: Text('Pre-inspection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        TextField(controller: mileage, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Arrival mileage')),
        const SizedBox(height: 6),
        TextField(controller: notes, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Inspection notes', hintText: 'Existing damage, warning lights, interior condition, etc.')),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('Save'))),
      ])),
    ));
    if (save == true) {
      await _run(() async { await _api.saveJobPreInspection(widget.businessId, widget.jobId, notes: notes.text.trim(), odometer: num.tryParse(mileage.text.trim())); });
    }
    mileage.dispose(); notes.dispose();
  }

  Future<void> _addPreInspectionPhotos() async {
    if (_busy || !_canEditInspection) return;
    final source = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take photo'), onTap: () => Navigator.pop(sheetContext, 'camera')),
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(sheetContext, 'gallery')),
    ])));
    if (source == null) return;
    final photos = <XFile>[];
    if (source == 'camera') {
      final p = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 1920, maxHeight: 1920);
      if (p != null) photos.add(p);
    } else {
      photos.addAll(await _picker.pickMultiImage(imageQuality: 88, maxWidth: 1920, maxHeight: 1920));
    }
    if (photos.isEmpty) return;
    await _run(() async {
      for (final photo in photos) {
        await _api.uploadJobPreInspectionPhoto(widget.businessId, widget.jobId, filename: photo.name, mimeType: _imageMime(photo.name), bytes: await photo.readAsBytes());
      }
    });
  }

  Future<void> _editPreInspectionPhotoNote(Map<String, dynamic> photo) async {
    final controller = TextEditingController(text: photo['note']?.toString() ?? '');
    final save = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Photo note'),
      content: TextField(controller: controller, autofocus: true, minLines: 2, maxLines: 5, decoration: const InputDecoration(hintText: 'Example: Scratch on left rear quarter panel')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))],
    ));
    if (save == true) await _run(() => _api.updateJobPreInspectionPhotoNote(widget.businessId, photo['id'].toString(), controller.text.trim()));
    controller.dispose();
  }

  Future<void> _deletePreInspectionPhoto(Map<String, dynamic> photo) async {
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Delete photo?'),
      content: const Text('Remove this photo from the pre-inspection?'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))],
    ));
    if (ok == true) await _run(() => _api.deleteJobPreInspectionPhoto(widget.businessId, photo['id'].toString()));
  }

  Future<void> _addFinding() async {
    if (!_canEditFindings || _job == null || _busy) return;
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
                  const SizedBox(height: 6),
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
                  if (_canSeeFinancial)
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
                  const SizedBox(height: 6),
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
        await _api.uploadVehicleFindingPhoto(
          widget.businessId,
          findingId,
          filename: photo.name,
          mimeType: _imageMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }
    });
  }

  Future<void> _editFinding(Map<String, dynamic> finding) async {
    if (finding['can_edit'] != true || _busy) return;
    final controller = TextEditingController(
      text: finding['body']?.toString() ?? '',
    );
    final save = await showModalBottomSheet<bool>(
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
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Edit finding',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(labelText: 'Finding'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final body = controller.text.trim();
    controller.dispose();
    if (save != true || body.isEmpty) return;
    await _run(() => _api.updateVehicleFinding(
          widget.businessId,
          finding['id'].toString(),
          body: body,
        ));
  }

  Future<void> _addPhotosToFinding(Map<String, dynamic> finding) async {
    if (!_canEditFindings || _busy) return;
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final photos = <XFile>[];
    if (source == 'camera') {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo != null) photos.add(photo);
    } else {
      photos.addAll(
        await _picker.pickMultiImage(
          imageQuality: 88,
          maxWidth: 1920,
          maxHeight: 1920,
        ),
      );
    }
    if (photos.isEmpty) return;

    await _run(() async {
      for (final photo in photos) {
        await _api.uploadVehicleFindingPhoto(
          widget.businessId,
          finding['id'].toString(),
          filename: photo.name,
          mimeType: _imageMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }
    });
  }

  Future<void> _deleteFindingPhoto(
    Map<String, dynamic> finding,
    Map<String, dynamic> attachment,
  ) async {
    if (!_owner || _busy) return;
    final attachmentId = attachment['attachment_id']?.toString() ?? '';
    if (attachmentId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('Remove this picture from the finding?'),
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

    await _run(
      () => _api.deleteVehicleFindingPhoto(
        widget.businessId,
        finding['id'].toString(),
        attachmentId,
        bucket: attachment['bucket']?.toString() ?? 'briskers-private',
        key: attachment['key']?.toString() ?? '',
      ),
    );
  }

  Future<void> _replaceFindingPhoto(
    Map<String, dynamic> finding,
    Map<String, dynamic> attachment,
  ) async {
    if (!_owner || _busy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take replacement photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose replacement from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo == null) return;

    final attachmentId = attachment['attachment_id']?.toString() ?? '';
    await _run(() async {
      await _api.uploadVehicleFindingPhoto(
        widget.businessId,
        finding['id'].toString(),
        filename: photo.name,
        mimeType: _imageMime(photo.name),
        bytes: await photo.readAsBytes(),
      );
      if (attachmentId.isNotEmpty) {
        await _api.deleteVehicleFindingPhoto(
          widget.businessId,
          finding['id'].toString(),
          attachmentId,
          bucket: attachment['bucket']?.toString() ?? 'briskers-private',
          key: attachment['key']?.toString() ?? '',
        );
      }
    });
  }

  Future<void> _addFindingToJob(Map<String, dynamic> finding) async {
    await _run(() => _api.addVehicleFindingToJob(
          widget.businessId,
          finding['id'].toString(),
          widget.jobId,
        ));
  }

  Future<void> _removeFindingFromJob(Map<String, dynamic> finding) async {
    await _run(() => _api.removeVehicleFindingFromJob(
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


  List<Map<String, dynamic>> _availableStatuses() => _statuses;

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
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_canManage) ...[
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, color: color, size: 17),
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
              const SizedBox(width: 8),
              Text(status['name']?.toString() ?? ''),
            ],
          ),
        );
      }).toList(),
      child: child,
    );
  }

  String? _completedPaymentLabel() {
    if (_job?['status']?.toString() != 'completed') return null;

    final invoices = _documents
        .where((row) => row['kind']?.toString() == 'invoice')
        .toList();
    if (invoices.isEmpty) return 'Invoice needed';

    num total = 0;
    num paid = 0;
    num pending = 0;
    for (final invoice in invoices) {
      total += num.tryParse(invoice['total_amount']?.toString() ?? '') ?? 0;
      paid += num.tryParse(invoice['paid_amount']?.toString() ?? '') ?? 0;
      pending +=
          num.tryParse(invoice['pending_payment']?.toString() ?? '') ?? 0;
    }

    if (total <= 0 || paid >= total - 0.005) return 'Paid';
    if (pending > 0 && paid + pending >= total - 0.005) {
      return 'Awaiting payment clearance';
    }
    return 'Awaiting payment';
  }

  Widget _completedPaymentBanner() {
    final label = _completedPaymentLabel();
    if (label == null) return const SizedBox.shrink();

    final paid = label == 'Paid';
    final invoiceNeeded = label == 'Invoice needed';
    final color = paid
        ? const Color(0xFF169B62)
        : invoiceNeeded
            ? const Color(0xFFC62828)
            : const Color(0xFFE58A00);
    final icon = paid
        ? Icons.check_circle_outline
        : invoiceNeeded
            ? Icons.receipt_long_outlined
            : Icons.hourglass_bottom_outlined;

    return Card(
      margin: EdgeInsets.zero,
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: const Text(
          'Financial status',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(label),
      ),
    );
  }

  Widget _summaryCard({
    required String customerName,
    required String vehicle,
    required String vin,
    required String jobTitle,
    required Map<String, dynamic>? assignment,
  }) {
    final employeeName = assignment == null
        ? 'Unassigned'
        : assignment['employee_name']?.toString() ?? 'Assigned';
    final employeePosition =
        assignment?['position']?.toString() ?? 'Mechanic';
    final roleStyle = employeeRoleStyle(employeePosition);
    final statusColor = colorFromHex(_job?['status_color']?.toString());
    final cardTint = Color.alphaBlend(
      statusColor.withValues(alpha: 0.12),
      const Color(0xFFFCFCFB),
    );

    Widget infoRow({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
      String? subtitle,
      bool problemFlag = false,
      VoidCallback? onTap,
    }) {
      final enabled = onTap != null && !_busy;
      return InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 5, 5, 5),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.13),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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
              if (problemFlag) ...[
                const SizedBox(width: 5),
                const Icon(Icons.flag, color: Colors.red, size: 19),
              ],
              if (enabled) const Icon(Icons.chevron_right, size: 22),
            ],
          ),
        ),
      );
    }

    Widget bottomCell({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
      VoidCallback? onTap,
    }) {
      final enabled = onTap != null && !_busy;
      return InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.8,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled) const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                  heightFactor: 0.82,
                  child: Opacity(
                    opacity: 0.18,
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
            padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoRow(
                  icon: Icons.person_outline,
                  color: statusColor,
                  label: 'Customer',
                  value: customerName.isEmpty ? 'Customer' : customerName,
                  problemFlag: _job?['customer_problem_flag'] == true,
                  onTap: _canManage ? _changeCustomer : null,
                ),
                Divider(
                  height: 1,
                  color: statusColor.withValues(alpha: 0.20),
                ),
                infoRow(
                  icon: Icons.directions_car_outlined,
                  color: statusColor,
                  label: 'Vehicle',
                  value: vehicle.isEmpty ? 'No vehicle' : vehicle,
                  subtitle:
                      vin.isEmpty ? 'VIN: Not entered' : 'VIN: $vin',
                  onTap: _canManage ? _changeVehicle : null,
                ),
                Divider(
                  height: 1,
                  color: statusColor.withValues(alpha: 0.20),
                ),
                InkWell(
                  onTap: _canManage && !_busy ? _changeJobTitle : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 4, 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            jobTitle.isEmpty ? 'Job' : jobTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                            ),
                          ),
                        ),
                        if (_canManage)
                          const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: bottomCell(
                        icon: roleStyle.icon,
                        color: roleStyle.color,
                        label: 'Mechanic',
                        value: employeeName,
                        onTap: _canManage ? _changeAssignment : null,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      color: statusColor.withValues(alpha: 0.24),
                    ),
                    Expanded(
                      child: bottomCell(
                        icon: Icons.timer_outlined,
                        color: statusColor,
                        label: 'Planned time',
                        value: '${_hours(_job!['planned_hours'])} hr',
                        onTap: _canManage ? _changePlannedHours : null,
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

  Future<void> _showFindingPhoto(
    Map<String, dynamic> attachment,
  ) async {
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';
    if (bucket.isEmpty || key.isEmpty) return;

    try {
      final url = await _api.signedAttachmentUrl(bucket, key);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filled(
                  tooltip: 'Close photo',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Widget _findingPhotoThumbnail(
    Map<String, dynamic> finding,
    Map<String, dynamic> attachment,
  ) {
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    Widget controls(Widget image) => SizedBox(
          width: 82,
          height: 82,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: bucket.isEmpty || key.isEmpty
                    ? null
                    : () => _showFindingPhoto(attachment),
                child: image,
              ),
              if (attachment['can_delete'] == true)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      color: Theme.of(context).colorScheme.surface,
                      tooltip: 'Photo actions',
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 18,
                      ),
                      onSelected: (value) {
                        if (value == 'replace') {
                          _replaceFindingPhoto(finding, attachment);
                        }
                        if (value == 'delete') {
                          _deleteFindingPhoto(finding, attachment);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'replace',
                          child: Text('Replace photo'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete photo'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );

    if (bucket.isEmpty || key.isEmpty) {
      return controls(
        const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.deepOrange,
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return controls(
            const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return controls(
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.network(
              snapshot.data!,
              width: 82,
              height: 82,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.deepOrange,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _findingsDrawer() {
    final open = _findings
        .where((finding) => finding['status']?.toString() == 'open')
        .toList();
    final inJob = _findings
        .where((finding) => finding['status']?.toString() == 'in_job')
        .toList();
    final resolved = _findings
        .where((finding) => finding['status']?.toString() == 'resolved')
        .toList();

    Widget findingRow(Map<String, dynamic> finding) {
      final status = finding['status']?.toString() ?? 'open';
      final repairJobId = finding['repair_job_id']?.toString() ?? '';
      final repairJob = finding['repair_job_number']?.toString() ?? '';
      final inThisJob = status == 'in_job' && repairJobId == widget.jobId;
      final attachments = List<dynamic>.from(finding['attachments'] ?? const []);

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  status == 'resolved'
                      ? Icons.check_circle_outline
                      : status == 'in_job'
                          ? Icons.handyman_outlined
                          : Icons.warning_amber_rounded,
                  color: status == 'resolved'
                      ? Colors.green
                      : status == 'in_job'
                          ? BriskersColors.jobs
                          : Colors.deepOrange,
                  size: 21,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    finding['body']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_canEditFindings || finding['can_edit'] == true || _owner)
                  PopupMenuButton<String>(
                    tooltip: 'Finding actions',
                    onSelected: (value) {
                      if (value == 'edit') _editFinding(finding);
                      if (value == 'photo') _addPhotosToFinding(finding);
                      if (value == 'delete') _deleteFinding(finding);
                    },
                    itemBuilder: (_) => [
                      if (finding['can_edit'] == true)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit finding'),
                        ),
                      if (_canEditFindings)
                        const PopupMenuItem(
                          value: 'photo',
                          child: Text('Add photos'),
                        ),
                      if (_owner)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete finding'),
                        ),
                    ],
                  ),
              ],
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: attachments
                    .map(
                      (raw) => _findingPhotoThumbnail(
                        finding,
                        Map<String, dynamic>.from(raw as Map),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (status == 'open' && _canManage)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Repair on this job'),
                subtitle: const Text(
                  'Completing the job will mark it resolved.',
                ),
                value: false,
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == true) _addFindingToJob(finding);
                      },
              )
            else if (inThisJob && _canManage)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Repair on this job'),
                subtitle: const Text('Checked'),
                value: true,
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == false) _removeFindingFromJob(finding);
                      },
              )
            else if (status == 'in_job')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  repairJob.isEmpty ? 'In another job' : 'In $repairJob',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            else if (status == 'resolved' && _canManage)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _reopenFinding(finding),
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Reopen'),
                ),
              ),
            const Divider(height: 1),
          ],
        ),
      );
    }

    final active = [...open, ...inJob];
    return _JobDrawerSurface(
      color: Colors.deepOrange,
      child: Column(
        children: [
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No unresolved findings for this vehicle.'),
              ),
            )
          else
            ...active.map(findingRow),
          if (resolved.isNotEmpty)
            ExpansionTile(
              title: Text(
                resolved.length == 1
                    ? '1 resolved finding'
                    : '${resolved.length} resolved findings',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              children: resolved.map(findingRow).toList(),
            ),
        ],
      ),
    );
  }

  Future<void> _addJobExpense() async {
    final job = _job;
    if (job == null) return;
    final number = job['job_number']?.toString().trim() ?? '';
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          jobId: widget.jobId,
          contextLabel: number.isEmpty ? 'This job' : 'Job $number',
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _addQuickJobExpense() async {
    final job = _job;
    if (job == null) return;

    try {
      final data = await _api.transactionOptions(widget.businessId);
      final quick = List<dynamic>.from(data['quick_templates'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((row) => row['direction']?.toString() == 'expense')
          .toList();

      if (!mounted) return;
      if (quick.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No expense quick transactions are defined yet. Add them in Settings.',
            ),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Quick expense',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('This expense will stay linked to this job.'),
              ),
              ...quick.map(
                (item) => ListTile(
                  leading: const Icon(
                    Icons.bolt,
                    color: BriskersColors.expenses,
                  ),
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: Text(
                    <String>[
                      if ((item['vendor']?.toString() ?? '').isNotEmpty)
                        item['vendor'].toString(),
                      item['category']?.toString() ?? '',
                      item['account']?.toString() ?? '',
                    ].where((value) => value.isNotEmpty).join(' • '),
                  ),
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;

      final number = job['job_number']?.toString().trim() ?? '';
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ExpenseEntryScreen(
            businessId: widget.businessId,
            jobId: widget.jobId,
            contextLabel: number.isEmpty ? 'This job' : 'Job $number',
            initialDirection: 'expense',
            quickTemplate: selected,
          ),
        ),
      );
      if (changed == true) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _showNewMenu() async {
    final size = MediaQuery.sizeOf(context);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        size.width - 260,
        size.height - 430,
        18,
        92,
      ),
      items: [
        if (_canEditFindings)
          const PopupMenuItem(
            value: 'inspection',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Pre-inspection'),
            ),
          ),
        if (_canEditFindings)
          const PopupMenuItem(
            value: 'finding',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_circle_outline),
              title: Text('New finding'),
            ),
          ),
        if (_canSeeFinancial)
          const PopupMenuItem(
            value: 'estimate',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.request_quote_outlined,
                color: BriskersColors.estimates,
              ),
              title: Text('New estimate'),
            ),
          ),
        if (_canSeeFinancial)
          const PopupMenuItem(
            value: 'invoice',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.receipt_long_outlined,
                color: BriskersColors.invoices,
              ),
              title: Text('New invoice'),
            ),
          ),
        if (_canManage)
          const PopupMenuItem(
            value: 'expense',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.add_card_outlined,
                color: BriskersColors.expenses,
              ),
              title: Text('New expense'),
            ),
          ),
        if (_canManage)
          const PopupMenuItem(
            value: 'quick_expense',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.bolt,
                color: BriskersColors.expenses,
              ),
              title: Text('Quick expense'),
            ),
          ),
      ],
    );

    if (choice == 'inspection') { if (_preInspection == null) await _editPreInspectionDetails(); if (mounted) await _openSectionModal('inspection'); }
    if (choice == 'finding') await _addFinding();
    if (choice == 'estimate') await _createEstimate();
    if (choice == 'invoice') await _createInvoice();
    if (choice == 'expense') await _addJobExpense();
    if (choice == 'quick_expense') await _addQuickJobExpense();
  }

  Future<void> _openExpense(String transactionId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(
          businessId: widget.businessId,
          transactionId: transactionId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _editJobExpense(String transactionId) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          editTransactionId: transactionId,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _deleteJobExpense(String transactionId) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text(
          'This expense will be removed from normal views and from this job.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => _api.voidManualTransaction(
        widget.businessId,
        transactionId,
      ),
    );
  }

  Widget _jobExpenseThumbnail(Map<String, dynamic> attachment) {
    const size = 52.0;
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BriskersColors.expenses.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.receipt_long_outlined),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: snapshot.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: BriskersColors.expenses.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  Widget _jobExpensesDrawer() {
    if (_jobExpenses.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No expenses are linked to this job yet.'),
          ),
          if (_canManage)
            OutlinedButton.icon(
              onPressed: _busy ? null : _addJobExpense,
              icon: const Icon(Icons.add_card_outlined),
              label: const Text('Add expense'),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._jobExpenses.map((expense) {
          final id = expense['id']?.toString() ?? '';
          final vendor = expense['counterparty']?.toString().trim() ?? '';
          final category = expense['category']?.toString().trim() ?? '';
          final remarks = expense['remarks']?.toString().trim() ?? '';
          final date = expense['transaction_date']?.toString().trim() ?? '';
          final receiptCount =
              int.tryParse(expense['receipt_count']?.toString() ?? '') ?? 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    const Color(0xFFC62828).withValues(alpha: 0.10),
                child: const Icon(
                  Icons.north_east,
                  color: Color(0xFFC62828),
                ),
              ),
              title: Text(
                vendor.isEmpty ? 'Expense' : vendor,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                <String>[
                  if (remarks.isNotEmpty) remarks,
                  if (category.isNotEmpty || date.isNotEmpty)
                    <String>[
                      if (category.isNotEmpty) category,
                      if (date.isNotEmpty) date,
                    ].join(' • '),
                  if (receiptCount > 0)
                    receiptCount == 1
                        ? '1 receipt photo'
                        : '$receiptCount receipt photos',
                ].join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '-${_money(expense['amount'])}',
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_canManage)
                    PopupMenuButton<String>(
                      tooltip: 'Expense actions',
                      onSelected: (value) async {
                        if (value == 'edit') await _editJobExpense(id);
                        if (value == 'delete') await _deleteJobExpense(id);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit expense'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete expense'),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
              onTap: id.isEmpty ? null : () => _openExpense(id),
            ),
          );
        }),
        if (_canManage) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _busy ? null : _addJobExpense,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Add expense'),
          ),
        ],
      ],
    );
  }

  Widget _profitabilityDrawer() {
    final data = _profitability;
    if (!_owner || data == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Profitability is not available.'),
      );
    }

    num value(String key) =>
        num.tryParse(data[key]?.toString() ?? '') ?? 0;

    final revenue = value('revenue');
    final salesTax = value('sales_tax');
    final directCost = value('direct_cost');
    final mechanicCost = value('mechanic_cost');
    final profit = value('profit');
    final margin =
        num.tryParse(data['margin_percent']?.toString() ?? '') ?? 0;
    final expenses = List<dynamic>.from(data['expenses'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    Widget amountRow(
      String label,
      num amount, {
      bool emphasized = false,
    }) {
      return Container(
        margin: EdgeInsets.only(bottom: emphasized ? 12 : 2),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: emphasized ? 16 : 11,
        ),
        decoration: emphasized
            ? BoxDecoration(
                color: Colors.green.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.28),
                ),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: emphasized ? 18 : 16,
                  fontWeight:
                      emphasized ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              _money(amount),
              style: TextStyle(
                fontSize: emphasized ? 22 : 17,
                fontWeight: FontWeight.w900,
                color: emphasized ? Colors.green.shade700 : null,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Job financial summary',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${margin.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            amountRow('Revenue before sales tax', revenue),
            amountRow('Parts / direct expenses', directCost),
            amountRow('Mechanic labor', mechanicCost),
            const Divider(height: 18),
            amountRow('Gross profit', profit, emphasized: true),
            amountRow('Sales tax collected', salesTax),
            if (expenses.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Job expenses',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              ...expenses.map((expense) {
                final id = expense['transaction_id']?.toString() ?? '';
                final vendor = expense['vendor']?.toString().trim() ?? '';
                final category = expense['category']?.toString().trim() ?? '';
                final memo = expense['memo']?.toString().trim() ?? '';
                final attachments =
                    List<dynamic>.from(expense['attachments'] ?? const [])
                        .map((raw) => Map<String, dynamic>.from(raw as Map))
                        .toList();

                return Card(
                  margin: const EdgeInsets.only(top: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    leading: attachments.isEmpty
                        ? CircleAvatar(
                            backgroundColor: BriskersColors.expenses
                                .withValues(alpha: 0.10),
                            child: const Icon(Icons.receipt_long_outlined),
                          )
                        : _jobExpenseThumbnail(attachments.first),
                    title: Text(
                      vendor.isEmpty ? 'Expense' : vendor,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      <String>[
                        if (memo.isNotEmpty) memo,
                        if (category.isNotEmpty) category,
                        if (attachments.isNotEmpty)
                          attachments.length == 1
                              ? '1 receipt photo'
                              : '${attachments.length} receipt photos',
                      ].join('\n'),
                    ),
                    trailing: Text(
                      _money(expense['amount']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    isThreeLine: memo.isNotEmpty || attachments.isNotEmpty,
                    onTap: id.isEmpty ? null : () => _openExpense(id),
                  ),
                );
              }),
            ],
            if (_canManage) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _addJobExpense,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Add expense'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _complaintDrawer(String complaint) {
    return _JobDrawerSurface(
      color: BriskersColors.customers,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              complaint.isEmpty
                  ? 'No customer complaint entered.'
                  : complaint,
            ),
            if (_canManage) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _editComplaint,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workPerformedDrawer(
    String workSummary,
    Map<String, dynamic>? currentVisit,
  ) {
    return _JobDrawerSurface(
      color: BriskersColors.jobs,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              workSummary.isEmpty
                  ? 'No work performed entered yet.'
                  : workSummary,
            ),
            if (currentVisit != null && _canEditWork) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _editWorkSummary,
                  icon: Icon(
                    workSummary.isEmpty
                        ? Icons.add_circle_outline
                        : Icons.edit_outlined,
                  ),
                  label: Text(workSummary.isEmpty ? 'Add' : 'Edit'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workHistoryDrawer(List<Map<String, dynamic>> visits) {
    return _JobDrawerSurface(
      color: const Color(0xFF6842C2),
      child: visits.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No visit history yet.'),
            )
          : Column(
              children: visits.map((visit) {
                final mechanics = List<dynamic>.from(
                  visit['mechanics'] ?? const [],
                ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
                final names = mechanics
                    .map((item) => item['employee_name']?.toString() ?? '')
                    .where((name) => name.isNotEmpty)
                    .join(', ');
                final summary = visit['work_summary']?.toString().trim() ?? '';
                final reason = visit['reason']?.toString().trim() ?? '';
                final opened = _dateTime(visit['opened_at']);
                final closed = _dateTime(visit['closed_at']);

                return ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text(
                    'Visit ${visit['visit_number']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    <String>[
                      if (opened.isNotEmpty)
                        closed.isEmpty ? 'Started $opened' : '$opened → $closed',
                      if (names.isNotEmpty) 'Mechanic: $names',
                      if (reason.isNotEmpty) reason,
                      if (summary.isNotEmpty) summary,
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                );
              }).toList(),
            ),
    );
  }

  Widget _documentsDrawer() {
    return _JobDrawerSurface(
      color: BriskersColors.invoices,
      child: _documents.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No estimate or invoice linked yet.'),
            )
          : Column(
              children: _documents.map((document) {
                final estimate = document['kind']?.toString() == 'estimate';
                final color = estimate
                    ? BriskersColors.estimates
                    : BriskersColors.invoices;
                final number = document['document_number']?.toString() ?? '';
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(_money(document['total_amount'])),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDocument(document['id'].toString()),
                );
              }).toList(),
            ),
    );
  }

  Widget _preInspectionPhotoTile(Map<String, dynamic> photo) {
    final bucket = photo['bucket']?.toString() ?? '';
    final key = photo['key']?.toString() ?? '';
    final note = photo['note']?.toString().trim() ?? '';
    final captured = _dateTime(photo['captured_at']);
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        leading: SizedBox(width: 58, height: 48, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: FutureBuilder<String>(
          future: bucket.isEmpty || key.isEmpty ? Future<String>.value('') : _api.signedAttachmentUrl(bucket, key),
          builder: (context, snapshot) {
            final url = snapshot.data ?? '';
            if (url.isEmpty) return const ColoredBox(color: Color(0x11000000), child: Icon(Icons.photo_outlined));
            return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined));
          },
        ))),
        title: Text(note.isEmpty ? 'No photo note' : note, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: captured.isEmpty ? null : Text(captured),
        onTap: bucket.isEmpty || key.isEmpty ? null : () => _showFindingPhoto(photo),
        trailing: (photo['can_edit_note'] == true || photo['can_delete'] == true)
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'note') _editPreInspectionPhotoNote(photo);
                  if (value == 'delete') _deletePreInspectionPhoto(photo);
                },
                itemBuilder: (_) => [
                  if (photo['can_edit_note'] == true)
                    const PopupMenuItem(
                      value: 'note',
                      child: Text('Edit note'),
                    ),
                  if (photo['can_delete'] == true)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete photo'),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _preInspectionDrawer() {
    final data = _preInspection;
    final photos = data == null ? <Map<String, dynamic>>[] : List<dynamic>.from(data['photos'] ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final date = data == null ? '' : _dateTime(data['inspected_at']);
    final notes = data?['notes']?.toString().trim() ?? '';
    final odometer = data?['odometer']?.toString().trim() ?? '';
    return _JobDrawerSurface(
      color: const Color(0xFF6B4BC3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (data == null) const Padding(padding: EdgeInsets.all(6), child: Text('No pre-inspection has been recorded for this job yet.')),
          if (data != null) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text(<String>[if (date.isNotEmpty) date, if (odometer.isNotEmpty) 'Mileage $odometer'].join(' • '), style: const TextStyle(fontWeight: FontWeight.w700))),
            if (notes.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(6, 8, 6, 2), child: Text(notes)),
            if (photos.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No inspection photos yet.')),
            ...photos.map(_preInspectionPhotoTile),
          ],
          const SizedBox(height: 6),
          if (_canEditInspection)
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _editPreInspectionDetails, icon: Icon(data == null ? Icons.play_arrow : Icons.edit_outlined), label: Text(data == null ? 'Start inspection' : 'Edit details'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: _busy ? null : _addPreInspectionPhotos, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add photos'))),
            ]),
        ]),
      ),
    );
  }

  Widget _drawerForSection(
    String key, {
    required String complaint,
    required String workSummary,
    required Map<String, dynamic>? currentVisit,
    required List<Map<String, dynamic>> visits,
  }) {
    switch (key) {
      case 'complaint':
        return _complaintDrawer(complaint);
      case 'inspection':
        return _preInspectionDrawer();
      case 'findings':
        return _findingsDrawer();
      case 'work':
        return _workPerformedDrawer(workSummary, currentVisit);
      case 'history':
        return _workHistoryDrawer(visits);
      case 'documents':
        return _documentsDrawer();
      case 'expenses':
        return _jobExpensesDrawer();
      default:
        return _profitabilityDrawer();
    }
  }

  String _sectionTitle(String key) {
    switch (key) {
      case 'inspection':
        return 'Pre-Inspection';
      case 'complaint':
        return 'Customer Complaint';
      case 'findings':
        return 'Vehicle Findings';
      case 'work':
        return 'Work Performed';
      case 'history':
        return 'Work / Visit History';
      case 'documents':
        return 'Estimate / Invoice';
      case 'expenses':
        return 'Job Expenses';
      default:
        return 'Job Profitability';
    }
  }

  IconData _sectionIcon(String key) {
    switch (key) {
      case 'inspection':
        return Icons.search;
      case 'complaint':
        return Icons.description_outlined;
      case 'findings':
        return Icons.car_repair_outlined;
      case 'work':
        return Icons.build_outlined;
      case 'history':
        return Icons.history_outlined;
      case 'documents':
        return Icons.receipt_long_outlined;
      case 'expenses':
        return Icons.payments_outlined;
      default:
        return Icons.analytics_outlined;
    }
  }

  Color _sectionColor(String key) {
    switch (key) {
      case 'inspection':
        return const Color(0xFF6B4BC3);
      case 'complaint':
        return BriskersColors.customers;
      case 'findings':
        return Colors.deepOrange;
      case 'work':
        return const Color(0xFF15988F);
      case 'history':
        return const Color(0xFF2585D8);
      case 'documents':
        return const Color(0xFFE5A400);
      case 'expenses':
        return const Color(0xFFC62828);
      default:
        return BriskersColors.reports;
    }
  }

  Future<void> _openSectionModal(String key) async {
    if (_job == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _modalRefresh = () {
              if (mounted) setModalState(() {});
            };

            final visits = List<dynamic>.from(
              _job?['visits'] ?? const [],
            ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
            final currentVisit = visits.isEmpty ? null : visits.first;
            final complaint =
                _job?['requested_work']?.toString().trim() ?? '';
            final workSummary =
                currentVisit?['work_summary']?.toString().trim() ?? '';
            final color = _sectionColor(key);

            return FractionallySizedBox(
              heightFactor: 0.94,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: color.withValues(alpha: 0.13),
                          child: Icon(
                            _sectionIcon(key),
                            color: color,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _sectionTitle(key),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (key == 'findings' && _canEditFindings)
                          TextButton.icon(
                            onPressed: _busy ? null : _addFinding,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Finding'),
                          ),
                        if (key == 'expenses' && _canManage)
                          IconButton(
                            tooltip: 'Add expense',
                            onPressed: _busy ? null : _addJobExpense,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        if (key == 'documents' && _canSeeFinancial)
                          PopupMenuButton<String>(
                            tooltip: 'Create document',
                            onSelected: (value) async {
                              if (value == 'estimate') await _createEstimate();
                              if (value == 'invoice') await _createInvoice();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'estimate',
                                child: Text('New estimate'),
                              ),
                              PopupMenuItem(
                                value: 'invoice',
                                child: Text('New invoice'),
                              ),
                            ],
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                      child: _drawerForSection(
                        key,
                        complaint: complaint,
                        workSummary: workSummary,
                        currentVisit: currentVisit,
                        visits: visits,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    _modalRefresh = null;
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10), title: const Text('Job')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_job == null) {
      return Scaffold(appBar: AppBar(backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10), title: const Text('Job')), body: Center(child: Text(_error ?? 'Job not found.')));
    }

    final assignments = List<dynamic>.from(_job!['assignments'] ?? const []);
    final assignment = assignments.isEmpty ? null : Map<String, dynamic>.from(assignments.first as Map);
    final requests = List<dynamic>.from(_job!['pending_requests'] ?? const []).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final visits = List<dynamic>.from(_job!['visits'] ?? const []).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final currentVisit = visits.isEmpty ? null : visits.first;
    final customerName = _job!['customer_name']?.toString().trim() ?? '';
    final vehicle = _job!['vehicle']?.toString().trim() ?? '';
    final vin = _job!['vehicle_vin']?.toString().trim() ?? '';
    final jobNumber = _job!['job_number']?.toString().trim() ?? '';
    final jobTitle = _job!['title']?.toString().trim() ?? '';
    final complaint = _job!['requested_work']?.toString().trim() ?? '';
    final workSummary = currentVisit?['work_summary']?.toString().trim() ?? '';
    final unassigned = _job!['is_unassigned'] == true;
    final statusColor = colorFromHex(_job!['status_color']?.toString());
    final activeFindings = _findings.where((finding) => finding['status']?.toString() != 'resolved').length;

    int? badge(int value) => value > 0 ? value : null;
    final complaintCount = complaint.isEmpty ? 0 : 1;
    final inspectionCount = _preInspection == null ? 0 : 1;
    final workCount = workSummary.isEmpty ? 0 : 1;

    Widget categoryTile(
      String key,
      String label,
      IconData icon,
      Color color,
      int? count,
    ) {
      return _JobCategoryTile(
        label: label,
        icon: icon,
        color: color,
        count: count,
        onTap: () => _openSectionModal(key),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: statusColor.withValues(alpha: 0.08), centerTitle: false, titleSpacing: 0,
        title: Text(jobNumber.isEmpty ? 'Job' : 'Job $jobNumber', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        actions: [
          Center(child: _statusControl()),
          PopupMenuButton<String>(tooltip: 'Job menu', onSelected: (value) { if (value == 'refresh') _load(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'refresh', child: Text('Refresh'))]),
        ],
      ),
      floatingActionButton: (_canEditFindings || _canManage) ? FloatingActionButton.extended(
        onPressed: _busy ? null : _showNewMenu, backgroundColor: BriskersColors.jobs, foregroundColor: Colors.white, icon: const Icon(Icons.add), label: const Text('New', style: TextStyle(fontWeight: FontWeight.w800)),
      ) : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(controller: _scrollController, padding: const EdgeInsets.fromLTRB(10, 5, 10, 74), children: [
          _summaryCard(
            customerName: customerName,
            vehicle: vehicle,
            vin: vin,
            jobTitle: jobTitle,
            assignment: assignment,
          ),
          if (_job?['status']?.toString() == 'completed') ...[
            const SizedBox(height: 8),
            _completedPaymentBanner(),
          ],
          if (_canRequestJob && unassigned) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _requestJob,
              icon: const Icon(Icons.pan_tool_alt_outlined),
              label: const Text('Request this job'),
            ),
          ],
          if (_canManage && requests.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(
                  requests.length == 1
                      ? '1 mechanic requested this job'
                      : '${requests.length} mechanics requested this job',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                children: requests.map((request) => ListTile(
                  title: Text(request['employee_name']?.toString() ?? ''),
                  subtitle: Text(
                    request['position']?.toString() ?? 'Mechanic',
                  ),
                  trailing: Wrap(
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
                )).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: categoryTile(
                      'inspection',
                      'Pre-Inspection',
                      Icons.search,
                      const Color(0xFF6B4BC3),
                      badge(inspectionCount),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryTile(
                      'complaint',
                      'Customer Complaint',
                      Icons.description_outlined,
                      BriskersColors.customers,
                      badge(complaintCount),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryTile(
                      'findings',
                      'Vehicle Findings',
                      Icons.car_repair_outlined,
                      Colors.deepOrange,
                      badge(activeFindings),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryTile(
                      'work',
                      'Work Performed',
                      Icons.build_outlined,
                      const Color(0xFF15988F),
                      badge(workCount),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: categoryTile(
                      'history',
                      'Work / Visit History',
                      Icons.history_outlined,
                      const Color(0xFF2585D8),
                      badge(visits.length),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryTile(
                      'documents',
                      'Estimate / Invoice',
                      Icons.receipt_long_outlined,
                      const Color(0xFFE5A400),
                      badge(_documents.length),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryTile(
                      'expenses',
                      'Job Expenses',
                      Icons.payments_outlined,
                      const Color(0xFFC62828),
                      badge(_jobExpenses.length),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryTile(
                      'profit',
                      'Job Profitability',
                      Icons.analytics_outlined,
                      BriskersColors.reports,
                      null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ]),
      ),
      ),
    );
  }

}


class _JobCategoryTile extends StatelessWidget {
  const _JobCategoryTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 7, 5, 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: color.withValues(alpha: 0.13),
                    child: Icon(icon, color: color, size: 19),
                  ),
                  if (count != null && count! > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.2,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobDrawerSurface extends StatelessWidget {
  const _JobDrawerSurface({
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: color.withValues(alpha: 0.045),
      child: child,
    );
  }
}
