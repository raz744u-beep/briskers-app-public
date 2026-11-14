import 'package:flutter/material.dart';
import '../core/job_status_style.dart';

/// Customer-safe visit presentation: no rates, wages or internal cost fields.
class CustomerServiceVisitCard extends StatefulWidget {
  const CustomerServiceVisitCard({
    super.key,
    required this.date,
    required this.jobNumber,
    required this.vehicle,
    required this.status,
    required this.completed,
    required this.pending,
    required this.invoices,
    required this.onJob,
  });
  final String date, jobNumber, vehicle, status;
  final List<String> completed, pending;
  final List<({String number, VoidCallback open})> invoices;
  final VoidCallback? onJob;
  @override
  State<CustomerServiceVisitCard> createState() =>
      _CustomerServiceVisitCardState();
}

class _CustomerServiceVisitCardState extends State<CustomerServiceVisitCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final color = operationalJobStatusColor(
      widget.status == 'paid' ? 'completed' : widget.status,
      null,
    );
    final label = switch (widget.status.toLowerCase()) {
      'paid' => 'Paid',
      'completed' => 'Completed',
      'closed' => 'Closed',
      'in_progress' || 'in progress' => 'In Progress',
      _ => 'Open',
    };
    Widget link(String text, VoidCallback action) => TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
      ),
    );
    Widget bullets(String title, List<String> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final text in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(text)),
              ],
            ),
          ),
      ],
    );
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onJob != null)
                              link(widget.jobNumber, widget.onJob!),
                            for (final invoice in widget.invoices)
                              link(invoice.number, invoice.open),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const Divider(),
                  if (widget.completed.isNotEmpty)
                    bullets('Completed work', widget.completed),
                  if (widget.pending.isNotEmpty)
                    bullets(
                      'Invoice work · completion not confirmed',
                      widget.pending,
                    ),
                  if (widget.completed.isEmpty && widget.pending.isEmpty)
                    const Text('No repair descriptions saved for this visit.'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
