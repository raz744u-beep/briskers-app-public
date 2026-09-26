import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class CustomerComplaintEditScreen extends StatefulWidget {
  const CustomerComplaintEditScreen({
    super.key,
    required this.businessId,
    required this.jobId,
    required this.job,
    required this.initialValue,
  });

  final String businessId;
  final String jobId;
  final Map<String, dynamic> job;
  final String initialValue;

  @override
  State<CustomerComplaintEditScreen> createState() =>
      _CustomerComplaintEditScreenState();
}

class _CustomerComplaintEditScreenState
    extends State<CustomerComplaintEditScreen> {
  static const _api = BriskersApi();

  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final customerId = widget.job['customer_id']?.toString() ?? '';
    if (customerId.isEmpty) {
      setState(() => _error = 'This job is missing its customer reference.');
      return;
    }

    final plannedHours =
        num.tryParse(widget.job['planned_hours']?.toString() ?? '') ?? 0;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.updateJob(
        widget.businessId,
        widget.jobId,
        customerId: customerId,
        vehicleId: widget.job['vehicle_id']?.toString(),
        title: widget.job['title']?.toString() ?? '',
        requestedWork: _controller.text.trim(),
        plannedHours: plannedHours,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10),
        title: const Text('Customer complaint'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Edit only the customer complaint / requested work for this job.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Enter customer complaint...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
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
            label: Text(_saving ? 'Saving...' : 'Save customer complaint'),
          ),
        ],
      ),
    );
  }
}
