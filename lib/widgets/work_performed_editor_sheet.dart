import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;

import '../core/briskers_colors.dart';
import '../core/module_modal_theme.dart';
import '../core/briskers_i18n.dart';
import '../services/invoice_labor_work_summary.dart';

class WorkPerformedEditorSheet extends StatefulWidget {
  const WorkPerformedEditorSheet({
    super.key,
    required this.initialValue,
    this.loadInvoiceLabor,
    this.fillOnOpen = false,
  });
  final String initialValue;
  final Future<String?> Function()? loadInvoiceLabor;
  final bool fillOnOpen;

  @override
  State<WorkPerformedEditorSheet> createState() =>
      _WorkPerformedEditorSheetState();
}

class _WorkPerformedEditorSheetState extends State<WorkPerformedEditorSheet>
    with ModuleModalState<WorkPerformedEditorSheet> {
  @override
  Color get modalAccent => BriskersColors.jobs;

  @override
  void initState() {
    super.initState();
    if (widget.fillOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fill();
      });
    }
  }

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  bool _loading = false;
  bool _fetching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fill() async {
    if (_loading || widget.loadInvoiceLabor == null) return;
    setState(() {
      _loading = true;
      _fetching = true;
      _error = null;
    });
    try {
      var text = await widget.loadInvoiceLabor!();
      if (!mounted || text == null) return;
      setState(() => _fetching = false);
      if (text.trim().isEmpty) {
        setState(
          () => _error = 'This invoice has no labor descriptions to copy.',
        );
        return;
      }
      if (_controller.text.trim().isNotEmpty &&
          _controller.text.trim() != text.trim()) {
        final action = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Add invoice labor?'),
            content: const Text(
              'Append new descriptions to your text or replace it. You can edit the result before saving.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'append'),
                child: const Text('Append'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'replace'),
                child: const Text('Replace text'),
              ),
            ],
          ),
        );
        if (!mounted || action == null) return;
        if (action == 'append') {
          text = appendInvoiceLaborWorkSummary(_controller.text, text);
        }
      }
      _controller.value = TextEditingValue(
        text: text.trim(),
        selection: TextSelection.collapsed(offset: text.trim().length),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Invoice labor could not be loaded. Your text has been kept.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('workPerformed'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (widget.loadInvoiceLabor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _fill,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long_outlined),
                label: const Text('Fill from Invoice Labor'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 4,
            maxLines: 9,
            cursorColor: BriskersColors.jobs,
            decoration: InputDecoration(
              hintText: tr('workPerformedHint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading
                ? null
                : () => Navigator.pop(context, _controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.jobs,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
