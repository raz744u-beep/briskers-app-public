import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class WorkSummaryEditScreen extends StatefulWidget {
  const WorkSummaryEditScreen({
    super.key,
    required this.businessId,
    required this.jobId,
    required this.initialValue,
  });

  final String businessId;
  final String jobId;
  final String initialValue;

  @override
  State<WorkSummaryEditScreen> createState() => _WorkSummaryEditScreenState();
}

class _WorkSummaryEditScreenState extends State<WorkSummaryEditScreen> {
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

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.updateCurrentVisitWorkSummary(
        widget.businessId,
        widget.jobId,
        workSummary: _controller.text.trim(),
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
        title: const Text('Work performed'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Diagnosis, work performed, findings, parts replaced, and anything the next technician should know.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Enter work performed...',
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
            label: Text(_saving ? 'Saving...' : 'Save work performed'),
          ),
        ],
      ),
    );
  }
}
