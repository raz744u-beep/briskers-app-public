import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class CustomerServiceHistorySection extends StatefulWidget {
  const CustomerServiceHistorySection({
    super.key,
    required this.businessId,
    required this.customerId,
  });

  final String businessId;
  final String customerId;

  @override
  State<CustomerServiceHistorySection> createState() =>
      _CustomerServiceHistorySectionState();
}

class _CustomerServiceHistorySectionState
    extends State<CustomerServiceHistorySection> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>> _jobs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.customerServiceHistory(
        widget.businessId,
        widget.customerId,
      );
      if (!mounted) return;
      setState(() {
        _jobs = rows;
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

  String _label(Object? raw) {
    final value = raw?.toString().replaceAll('_', ' ') ?? '';
    if (value.isEmpty) return '';
    return value
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _date(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '';
    return DateFormat('MMM d, yyyy').format(date.toLocal());
  }

  String _money(Object? raw) {
    final amount = num.tryParse(raw?.toString() ?? '');
    if (amount == null) return '';
    return NumberFormat.currency(symbol: '\$').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final count = _jobs.length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: false,
        leading: const Icon(
          Icons.history_outlined,
          color: BriskersColors.jobs,
        ),
        title: const Text(
          'Service History',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: _loading
            ? const Text('Loading service history...')
            : Text(count == 1 ? '1 job' : '$count jobs'),
        children: [
          const Divider(height: 1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else if (_jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No service history yet.'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                children: _jobs.map((job) {
                  final vehicle = '${job['vehicle'] ?? ''}'.trim();
                  final title = '${job['title'] ?? ''}'.trim();
                  final jobNumber = '${job['job_number'] ?? ''}'.trim();
                  final status = _label(job['status']);
                  final requested = '${job['requested_work'] ?? ''}'.trim();
                  final date = _date(job['completed_at'] ?? job['created_at']);
                  final documents = List<dynamic>.from(
                    job['documents'] ?? const [],
                  );
                  final heading = <String>[
                    if (vehicle.isNotEmpty) vehicle,
                    if (title.isNotEmpty) title,
                  ].join(' — ');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      leading: const Icon(
                        Icons.build_outlined,
                        color: BriskersColors.jobs,
                      ),
                      title: Text(
                        heading.isEmpty ? 'Service job' : heading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        <String>[
                          if (jobNumber.isNotEmpty) 'Job $jobNumber',
                          if (status.isNotEmpty) status,
                          if (date.isNotEmpty) date,
                        ].join(' • '),
                      ),
                      children: [
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (requested.isNotEmpty) ...[
                                Text(
                                  'Requested work',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(requested),
                                const SizedBox(height: 12),
                              ],
                              if (job['odometer_in'] != null)
                                Text('Mileage in: ${job['odometer_in']} mi'),
                              if (documents.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Documents',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge,
                                ),
                                const SizedBox(height: 4),
                                ...documents.map((raw) {
                                  final document =
                                      Map<String, dynamic>.from(raw as Map);
                                  final kind = _label(document['kind']);
                                  final number =
                                      '${document['document_number'] ?? ''}'
                                          .trim();
                                  final docStatus =
                                      _label(document['status']);
                                  final total =
                                      _money(document['total_amount']);

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    leading: Icon(
                                      document['kind'] == 'invoice'
                                          ? Icons.receipt_long_outlined
                                          : Icons.request_quote_outlined,
                                      color: document['kind'] == 'invoice'
                                          ? BriskersColors.invoices
                                          : BriskersColors.estimates,
                                    ),
                                    title: Text(
                                      <String>[
                                        kind,
                                        if (number.isNotEmpty) number,
                                      ].join(' '),
                                    ),
                                    subtitle: docStatus.isEmpty
                                        ? null
                                        : Text(docStatus),
                                    trailing:
                                        total.isEmpty ? null : Text(total),
                                  );
                                }),
                              ] else
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'No estimates or invoices for this job.',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
