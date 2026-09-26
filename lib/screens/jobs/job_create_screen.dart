import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class JobCreateScreen extends StatefulWidget {
  const JobCreateScreen({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.vehicles,
  });

  final String businessId;
  final String customerId;
  final String customerName;
  final List<dynamic> vehicles;

  @override
  State<JobCreateScreen> createState() => _JobCreateScreenState();
}

class _JobCreateScreenState extends State<JobCreateScreen> {
  static const _api = BriskersApi();

  final _title = TextEditingController();
  final _requestedWork = TextEditingController();
  final _plannedHours = TextEditingController(text: '0');

  List<Map<String, dynamic>> _employees = const [];
  String? _vehicleId;
  String? _employeeId;
  String? _createdJobId;
  bool _loadingEmployees = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.vehicles.length == 1) {
      final only = Map<String, dynamic>.from(widget.vehicles.first as Map);
      _vehicleId = only['id']?.toString();
    }
    _loadEmployees();
  }

  @override
  void dispose() {
    _title.dispose();
    _requestedWork.dispose();
    _plannedHours.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await _api.assignableEmployees(widget.businessId);
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loadingEmployees = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEmployees = false);
    }
  }

  String _vehicleName(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) '${vehicle['year']}',
      '${vehicle['make'] ?? ''}'.trim(),
      '${vehicle['model'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty && _createdJobId == null) {
      setState(() => _error = 'Job title is required.');
      return;
    }

    final plannedHours = num.tryParse(_plannedHours.text.trim());
    if (plannedHours == null || plannedHours < 0) {
      setState(() => _error = 'Enter a valid planned time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final jobId = _createdJobId ??
          await _api.createJob(
            widget.businessId,
            customerId: widget.customerId,
            vehicleId: _vehicleId,
            title: title,
            description: _requestedWork.text.trim().isEmpty
                ? null
                : _requestedWork.text.trim(),
          );

      _createdJobId = jobId;

      await _api.updateJob(
        widget.businessId,
        jobId,
        customerId: widget.customerId,
        vehicleId: _vehicleId,
        title: title,
        requestedWork: _requestedWork.text.trim().isEmpty
            ? null
            : _requestedWork.text.trim(),
        plannedHours: plannedHours,
      );

      if (_employeeId != null) {
        await _api.setPrimaryJobEmployee(
          widget.businessId,
          jobId,
          _employeeId!,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _createdJobId == null
            ? error.toString()
            : 'The job was created, but the mechanic assignment failed. '
                'You can finish the assignment from the Jobs screen.\n$error';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = widget.vehicles
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10),
        title: const Text('Create job'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: BriskersColors.customers.withValues(alpha: 0.08),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    BriskersColors.customers.withValues(alpha: 0.14),
                child: const Icon(
                  Icons.person_outline,
                  color: BriskersColors.customers,
                ),
              ),
              title: Text(
                widget.customerName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Customer'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _vehicleId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Vehicle',
              prefixIcon: Icon(
                Icons.directions_car_outlined,
                color: BriskersColors.vehicles,
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No vehicle selected'),
              ),
              ...vehicles.map(
                (vehicle) => DropdownMenuItem<String?>(
                  value: vehicle['id']?.toString(),
                  child: Text(
                    _vehicleName(vehicle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: _createdJobId == null
                ? (value) => setState(() => _vehicleId = value)
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            enabled: _createdJobId == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Job title *',
              hintText: 'Example: Diagnose check engine light',
              prefixIcon: Icon(
                Icons.build_outlined,
                color: BriskersColors.jobs,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _requestedWork,
            enabled: _createdJobId == null,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Requested work / complaint',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _plannedHours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Planned / assigned time',
              helperText: 'Estimated labor time the mechanic should see.',
              suffixText: 'hours',
              prefixIcon: Icon(
                Icons.timer_outlined,
                color: BriskersColors.jobs,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Assignment',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: BriskersColors.jobs,
                ),
          ),
          const SizedBox(height: 8),
          if (_loadingEmployees)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String?>(
              initialValue: _employeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Mechanic / employee',
                helperText: 'Optional — you can assign or change this later.',
                prefixIcon: Icon(
                  Icons.engineering_outlined,
                  color: BriskersColors.jobs,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Unassigned'),
                ),
                ..._employees.map(
                  (employee) => DropdownMenuItem<String?>(
                    value: employee['id']?.toString(),
                    child: Text(
                      '${employee['name'] ?? ''} — '
                      '${employee['position_name'] ?? 'Employee'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _employeeId = value),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.jobs,
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving...'
                  : _createdJobId == null
                      ? 'Create job'
                      : 'Finish assignment',
            ),
          ),
        ],
      ),
    );
  }
}
