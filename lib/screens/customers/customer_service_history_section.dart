import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/job_status_style.dart';
import '../../services/briskers_api.dart';
import '../../widgets/job_compact_card.dart';
import '../expenses/expense_detail_screen.dart';
import '../jobs/job_detail_screen.dart';
import '../jobs/job_document_screen.dart';

class CustomerServiceHistorySection extends StatefulWidget {
  const CustomerServiceHistorySection({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.vehicles,
  });

  final String businessId;
  final String customerId;
  final List<dynamic> vehicles;

  @override
  State<CustomerServiceHistorySection> createState() =>
      _CustomerServiceHistorySectionState();
}

class _CustomerServiceHistorySectionState
    extends State<CustomerServiceHistorySection> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _expenses = const [];
  bool _loading = true;
  String? _error;
  String _roleCode = 'office';
  String? _selectedVehicleId;
  String _view = 'jobs';

  bool get _canSeeFinancial =>
      _roleCode == 'owner' ||
      _roleCode == 'manager' ||
      _roleCode == 'office';

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
      final role =
          current.isEmpty ? 'office' : current.first['role']?.toString() ?? 'office';

      List<Map<String, dynamic>> documents = const [];
      List<Map<String, dynamic>> expenses = const [];
      if (<String>{'owner', 'manager', 'office'}.contains(role)) {
        try {
          final financial = await _api.customerFinancialHistory(
            widget.businessId,
            widget.customerId,
          );
          documents = List<dynamic>.from(
            financial['documents'] ?? const [],
          ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
          expenses = List<dynamic>.from(
            financial['expenses'] ?? const [],
          ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        } catch (_) {
          documents = const [];
          expenses = const [];
        }
      }

      if (!mounted) return;
      setState(() {
        _jobs = rows;
        _documents = documents;
        _expenses = expenses;
        _roleCode = role;
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

  bool _matchesVehicle(Map<String, dynamic> row) {
    final selected = _selectedVehicleId;
    if (selected == null) return true;
    return row['vehicle_id']?.toString() == selected;
  }

  List<Map<String, dynamic>> get _visibleJobs =>
      _jobs.where(_matchesVehicle).toList();

  List<Map<String, dynamic>> get _visibleEstimates => _documents
      .where((row) => row['kind']?.toString() == 'estimate')
      .where(_matchesVehicle)
      .toList();

  List<Map<String, dynamic>> get _visibleInvoices => _documents
      .where((row) => row['kind']?.toString() == 'invoice')
      .where(_matchesVehicle)
      .toList();

  List<Map<String, dynamic>> get _visibleExpenses =>
      _expenses.where(_matchesVehicle).toList();

  String _vehicleLabel(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      vehicle['make']?.toString().trim() ?? '',
      vehicle['model']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
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

  Future<void> _openDocument(Map<String, dynamic> document) async {
    final id = document['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: id,
          isOwner: _roleCode == 'owner',
          canManageExpenses: _canSeeFinancial,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openExpense(Map<String, dynamic> expense) async {
    final id = expense['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(
          businessId: widget.businessId,
          transactionId: id,
        ),
      ),
    );
    await _load();
  }

  String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(value);
  }

  String _shortDate(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    return DateFormat('MMM d, yyyy').format(parsed.toLocal());
  }

  Widget _vehicleSelector() {
    final vehicles = widget.vehicles
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((vehicle) => (vehicle['id']?.toString() ?? '').isNotEmpty)
        .toList();

    if (vehicles.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            'Vehicle',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('All vehicles'),
                  selected: _selectedVehicleId == null,
                  onSelected: (_) {
                    setState(() => _selectedVehicleId = null);
                  },
                ),
              ),
              ...vehicles.map((vehicle) {
                final id = vehicle['id'].toString();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_vehicleLabel(vehicle)),
                    selected: _selectedVehicleId == id,
                    onSelected: (_) {
                      setState(() => _selectedVehicleId = id);
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyTypeSelector() {
    final choices = <(String, String, int)>[
      ('jobs', 'Jobs', _visibleJobs.length),
      if (_canSeeFinancial)
        ('estimates', 'Estimates', _visibleEstimates.length),
      if (_canSeeFinancial)
        ('invoices', 'Invoices', _visibleInvoices.length),
      if (_canSeeFinancial)
        ('expenses', 'Expenses', _visibleExpenses.length),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: choices.map((choice) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('${choice.$2} ${choice.$3}'),
              selected: _view == choice.$1,
              onSelected: (_) => setState(() => _view = choice.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _jobsList() {
    final jobs = _visibleJobs;
    if (jobs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No jobs for this vehicle.'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        children: jobs
            .map(
              (job) => JobCompactCard(
                job: job,
                statusControl: _statusControl(job),
                onOpen: () => _openJob(job),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _documentsList(List<Map<String, dynamic>> documents, String label) {
    if (documents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No $label for this vehicle.'),
        ),
      );
    }

    return Column(
      children: documents.map((document) {
        final number = document['document_number']?.toString() ?? '';
        final jobNumber = document['job_number']?.toString() ?? '';
        final vehicle = document['vehicle']?.toString() ?? '';
        final date = _shortDate(document['document_date']);
        return ListTile(
          leading: Icon(
            label == 'estimates'
                ? Icons.request_quote_outlined
                : Icons.receipt_long_outlined,
            color: label == 'estimates'
                ? BriskersColors.estimates
                : BriskersColors.invoices,
          ),
          title: Text(
            '${label == 'estimates' ? 'Estimate' : 'Invoice'} #$number',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            <String>[
              if (jobNumber.isNotEmpty) 'Job $jobNumber',
              if (vehicle.isNotEmpty) vehicle,
              if (date.isNotEmpty) date,
            ].join(' • '),
          ),
          trailing: Text(
            _money(document['total_amount']),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          onTap: () => _openDocument(document),
        );
      }).toList(),
    );
  }

  Widget _expensesList() {
    final expenses = _visibleExpenses;
    if (expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No expenses for this vehicle.'),
        ),
      );
    }

    return Column(
      children: expenses.map((expense) {
        final counterparty =
            expense['counterparty']?.toString() ?? 'Expense';
        final remarks = expense['remarks']?.toString().trim() ?? '';
        final jobNumber = expense['job_number']?.toString() ?? '';
        final documentNumber = expense['document_number']?.toString() ?? '';
        final vehicle = expense['vehicle']?.toString() ?? '';
        final date = _shortDate(expense['transaction_date']);
        return ListTile(
          leading: const Icon(
            Icons.payments_outlined,
            color: BriskersColors.expenses,
          ),
          title: Text(
            counterparty,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            <String>[
              if (documentNumber.isNotEmpty) 'Invoice #$documentNumber',
              if (jobNumber.isNotEmpty) 'Job $jobNumber',
              if (vehicle.isNotEmpty) vehicle,
              if (remarks.isNotEmpty) remarks,
              if (date.isNotEmpty) date,
            ].join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _money(expense['amount']),
            style: const TextStyle(
              color: BriskersColors.expenses,
              fontWeight: FontWeight.w800,
            ),
          ),
          onTap: () => _openExpense(expense),
        );
      }).toList(),
    );
  }

  Widget _selectedHistory() {
    switch (_view) {
      case 'estimates':
        return _documentsList(_visibleEstimates, 'estimates');
      case 'invoices':
        return _documentsList(_visibleInvoices, 'invoices');
      case 'expenses':
        return _expensesList();
      case 'jobs':
      default:
        return _jobsList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _visibleJobs.length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: true,
        leading: const Icon(Icons.history_outlined),
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
          else ...[
            _vehicleSelector(),
            _historyTypeSelector(),
            const Divider(height: 1),
            _selectedHistory(),
          ],
        ],
      ),
    );
  }
}
