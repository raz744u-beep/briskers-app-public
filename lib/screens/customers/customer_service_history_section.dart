import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/job_status_style.dart';
import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/historical_photo_matcher.dart';
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
  static const _cache = CustomerDetailCache();
  static const _androidFileChannel = MethodChannel('com.briskers/expenseiq');
  static const _historicalMatcher = HistoricalPhotoMatcher();

  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _expenses = const [];
  bool _loading = true;
  String? _error;
  String _roleCode = 'office';
  String? _selectedVehicleId;
  String _view = 'jobs';
  bool _historicalImporting = false;
  int _historicalImportDone = 0;
  int _historicalImportTotal = 0;

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
    final offline = BriskersConnectionModeController.instance.forceOffline;

    if (offline) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'service_history',
      );
      if (cached is Map) {
        final data = Map<String, dynamic>.from(cached);
        if (!mounted) return;
        setState(() {
          _jobs = List<dynamic>.from(data['jobs'] ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _documents = List<dynamic>.from(data['documents'] ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _expenses = List<dynamic>.from(data['expenses'] ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _roleCode = data['role']?.toString() ?? 'office';
          _loading = false;
          _error = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }

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
      final role = current.isEmpty
          ? 'office'
          : current.first['role']?.toString() ?? 'office';

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

      await _cache.save(
        widget.businessId,
        widget.customerId,
        'service_history',
        <String, dynamic>{
          'jobs': rows,
          'documents': documents,
          'expenses': expenses,
          'role': role,
        },
      );

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
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'service_history',
      );
      if (cached is Map) {
        final data = Map<String, dynamic>.from(cached);
        if (!mounted) return;
        setState(() {
          _jobs = List<dynamic>.from(data['jobs'] ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _documents = List<dynamic>.from(data['documents'] ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _expenses = List<dynamic>.from(data['expenses'] ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          _roleCode = data['role']?.toString() ?? 'office';
          _loading = false;
          _error = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _historicalFileName(Map<String, dynamic> file) =>
      file['name']?.toString().trim() ?? 'historical-photo.jpg';

  String _historicalMimeType(Map<String, dynamic> file) {
    final mime = file['mime_type']?.toString().trim().toLowerCase() ?? '';
    if (mime == 'image/png' || mime == 'image/webp' || mime == 'image/jpeg') {
      return mime;
    }
    final name = _historicalFileName(file).toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _importHistoricalJobPhotos() async {
    if (_historicalImporting || _roleCode != 'owner' || !Platform.isAndroid) {
      return;
    }

    if (BriskersConnectionModeController.instance.forceOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Historical photo import needs a connection so the recovered photos can be copied into Briskers storage.',
          ),
        ),
      );
      return;
    }

    final completedJobs = _jobs.where((job) {
      return job['status']?.toString().toLowerCase() == 'completed';
    }).toList();
    if (completedJobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No completed jobs are available to match.')),
      );
      return;
    }

    List<dynamic>? picked;
    try {
      picked = await _androidFileChannel.invokeMethod<List<dynamic>>(
        'pickHistoricalPhotoFolder',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not scan the selected photo folder. $error');
      return;
    }
    if (picked == null || !mounted) return;

    final files = picked
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final matches = _historicalMatcher.exactMatches(
      completedJobs,
      files,
    );
    final matchedUris = matches
        .map((match) => match.file['uri']?.toString() ?? '')
        .where((uri) => uri.isNotEmpty)
        .toSet();
    final unmatched = files
        .where((file) => !matchedUris.contains(file['uri']?.toString() ?? ''))
        .length;

    final byJob = <String, List<HistoricalPhotoMatch>>{};
    for (final match in matches) {
      final jobId = match.job['id']?.toString() ?? '';
      if (jobId.isEmpty) continue;
      byJob.putIfAbsent(jobId, () => []).add(match);
    }

    if (!mounted) return;
    final previewLines = byJob.entries.map((entry) {
      final first = entry.value.first;
      final jobNumber = first.job['job_number']?.toString() ?? 'Job';
      return '$jobNumber: ${entry.value.length} photo(s)';
    }).take(12).toList();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import historical job photos?'),
        content: SingleChildScrollView(
          child: Text(
            'Scanned ${files.length} image file(s).\n'
            'Exact completed-job matches: ${matches.length}\n'
            'Jobs matched: ${byJob.length}\n'
            'Unmatched files left untouched: $unmatched'
            '${previewLines.isEmpty ? '' : '\n\n' + previewLines.join('\n')}'
            '\n\nOnly exact job-number matches will be imported. '
            'Photos are copied into Briskers private storage and tagged as historical MobileBiz photos.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: matches.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('Import matched photos'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() {
      _historicalImporting = true;
      _historicalImportDone = 0;
      _historicalImportTotal = matches.length;
      _error = null;
    });

    var imported = 0;
    var skipped = 0;
    var failed = 0;

    for (final entry in byJob.entries) {
      final jobId = entry.key;
      final group = entry.value;
      final existingNames = <String>{};

      try {
        final inspection = await _api.jobPreInspection(
          widget.businessId,
          jobId,
        );
        final photos = List<dynamic>.from(
          inspection?['photos'] ?? const <dynamic>[],
        );
        for (final raw in photos.whereType<Map>()) {
          final name = raw['filename']?.toString().trim().toLowerCase() ?? '';
          if (name.isNotEmpty) existingNames.add(name);
        }
      } catch (_) {
        // Import can still continue; the upload path will report any failure.
      }

      for (final match in group) {
        final file = match.file;
        final filename = _historicalFileName(file);
        final lowerName = filename.toLowerCase();
        try {
          if (existingNames.contains(lowerName)) {
            skipped += 1;
          } else {
            final uri = file['uri']?.toString() ?? '';
            if (uri.isEmpty) throw StateError('Photo URI is missing.');
            final bytes = await _androidFileChannel.invokeMethod<Uint8List>(
              'readHistoricalPhotoFile',
              {'uri': uri},
            );
            if (bytes == null || bytes.isEmpty) {
              throw StateError('Could not read $filename.');
            }

            final jobNumber = match.job['job_number']?.toString() ?? '';
            await _api.uploadJobPreInspectionPhoto(
              widget.businessId,
              jobId,
              filename: filename,
              mimeType: _historicalMimeType(file),
              bytes: bytes,
              note: jobNumber.isEmpty
                  ? 'Historical MobileBiz photo'
                  : 'Historical MobileBiz photo • $jobNumber',
            );
            existingNames.add(lowerName);
            imported += 1;
          }
        } catch (_) {
          failed += 1;
        }

        if (mounted) {
          setState(() => _historicalImportDone += 1);
        }
      }
    }

    if (!mounted) return;
    setState(() => _historicalImporting = false);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Historical photo import: $imported imported'
          '${skipped > 0 ? ', $skipped already present' : ''}'
          '${failed > 0 ? ', $failed failed' : ''}.',
        ),
      ),
    );
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
          cachedDetail: BriskersConnectionModeController.instance.forceOffline
              ? Map<String, dynamic>.from(expense)
              : null,
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

  Future<void> _chooseVehicle() async {
    final vehicles = widget.vehicles
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((vehicle) => (vehicle['id']?.toString() ?? '').isNotEmpty)
        .toList();

    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Vehicle',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('All vehicles'),
              trailing: _selectedVehicleId == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheetContext, '__all__'),
            ),
            ...vehicles.map((vehicle) {
              final id = vehicle['id'].toString();
              return ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(_vehicleLabel(vehicle)),
                trailing: _selectedVehicleId == id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheetContext, id),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;
    setState(() {
      _selectedVehicleId = selected == '__all__' ? null : selected;
    });
  }

  Future<void> _chooseHistoryView() async {
    final choices = <(String, String, int)>[
      ('jobs', 'Jobs', _visibleJobs.length),
      if (_canSeeFinancial)
        ('estimates', 'Estimates', _visibleEstimates.length),
      if (_canSeeFinancial)
        ('invoices', 'Invoices', _visibleInvoices.length),
      if (_canSeeFinancial)
        ('expenses', 'Expenses', _visibleExpenses.length),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'View',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...choices.map((choice) => ListTile(
                  title: Text(choice.$2),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${choice.$3}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_view == choice.$1) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.check),
                      ],
                    ],
                  ),
                  onTap: () => Navigator.pop(sheetContext, choice.$1),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;
    setState(() => _view = selected);
  }

  String get _selectedVehicleLabel {
    if (_selectedVehicleId == null) return 'All vehicles';
    for (final raw in widget.vehicles.whereType<Map>()) {
      final vehicle = Map<String, dynamic>.from(raw);
      if (vehicle['id']?.toString() == _selectedVehicleId) {
        return _vehicleLabel(vehicle);
      }
    }
    return 'All vehicles';
  }

  String get _selectedViewLabel {
    switch (_view) {
      case 'estimates':
        return 'Estimates (${_visibleEstimates.length})';
      case 'invoices':
        return 'Invoices (${_visibleInvoices.length})';
      case 'expenses':
        return 'Expenses (${_visibleExpenses.length})';
      case 'jobs':
      default:
        return 'Jobs (${_visibleJobs.length})';
    }
  }

  Widget _selectorBar({
    required String label,
    required String value,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleSelector() {
    final vehicleCount = widget.vehicles
        .whereType<Map>()
        .where((raw) => (raw['id']?.toString() ?? '').isNotEmpty)
        .length;

    if (vehicleCount <= 1) return const SizedBox.shrink();

    return Column(
      children: [
        _selectorBar(
          label: 'Vehicle',
          value: _selectedVehicleLabel,
          onTap: _chooseVehicle,
          icon: Icons.directions_car_outlined,
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _historyTypeSelector() {
    return Column(
      children: [
        _selectorBar(
          label: 'View',
          value: _selectedViewLabel,
          onTap: _chooseHistoryView,
          icon: Icons.view_list_outlined,
        ),
        const Divider(height: 1),
      ],
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
            if (_roleCode == 'owner' && Platform.isAndroid) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _historicalImporting
                        ? null
                        : _importHistoricalJobPhotos,
                    icon: _historicalImporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(
                      _historicalImporting
                          ? 'Importing $_historicalImportDone of $_historicalImportTotal...'
                          : 'Import historical job photos',
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
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
