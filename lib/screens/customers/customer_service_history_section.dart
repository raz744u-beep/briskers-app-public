import 'package:flutter/material.dart';

import '../../core/job_status_style.dart';
import '../../services/briskers_api.dart';
import '../../widgets/job_compact_card.dart';
import '../jobs/job_detail_screen.dart';

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
  String _roleCode = 'office';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.customerServiceHistory(
          widget.businessId,
          widget.customerId,
        ),
        _api.myBusinesses(),
      ]);

      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final businesses =
          List<Map<String, dynamic>>.from(results[1] as List);
      final current = businesses.where(
        (business) => business['id']?.toString() == widget.businessId,
      );

      if (!mounted) return;
      setState(() {
        _jobs = rows;
        if (current.isNotEmpty) {
          _roleCode = current.first['role']?.toString() ?? 'office';
        }
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

  Widget _statusControl(Map<String, dynamic> job) {
    final color = colorFromHex(job['status_color']?.toString());
    final label = job['status_name']?.toString() ?? 'Status';

    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: job['id'].toString(),
          roleCode: _roleCode,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final count = _jobs.length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: true,
        leading: const Icon(
          Icons.history_outlined,
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
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
                children: _jobs
                    .map(
                      (job) => JobCompactCard(
                        job: job,
                        statusControl: _statusControl(job),
                        onOpen: () => _openJob(job),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
