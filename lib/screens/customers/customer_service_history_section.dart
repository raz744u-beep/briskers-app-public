import 'dart:async';

import '../../services/local_job_retirement.dart';
import '../../services/local_job_repository.dart';
import '../../local/local_database_provider.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/job_status_style.dart';
import '../../core/document_presentation.dart';
import '../../core/vehicle_invoice_repair_search.dart';
import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/job_summary_visibility.dart';
import '../../services/customer_document_summary_service.dart';
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
    this.roleCode = 'viewer',
    this.initiallyExpanded = false,
    this.initialVehicleId,
  });

  final String businessId;
  final String customerId;
  final List<dynamic> vehicles;
  final String roleCode;
  final bool initiallyExpanded;
  final String? initialVehicleId;

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

  late JobSummaryVisibility _jobVisibility;
  StreamSubscription<({String businessId, Set<String> jobIds})>? _retirement;
  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _expenses = const [];
  final Map<String, Future<Map<String, dynamic>>> _documentSummaries = {};
  bool _loading = true;
  String? _error;
  String get _roleCode => widget.roleCode;
  String? _selectedVehicleId;
  String _view = 'jobs';
  final TextEditingController _repairSearch = TextEditingController();
  String _repairQuery = '';
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
    if (widget.initialVehicleId != null &&
        widget.vehicles.whereType<Map>().any((v) =>
          v['id']?.toString() == widget.initialVehicleId)) {
      _selectedVehicleId = widget.initialVehicleId;
      _view = 'invoices';
    }
    _listenForQuarantine();
    _retirement = LocalJobRetirement.events.listen((event) {
      if (event.businessId != widget.businessId || !mounted) return;
      unawaited(
        _refreshRetiredDocuments().then((_) {
          if (mounted && event.businessId == widget.businessId) {
            unawaited(_load());
          }
        }),
      );
    });
    _load();
  }

  void _listenForQuarantine() {
    _jobVisibility = JobSummaryVisibility(
      businessId: widget.businessId,
      onQuarantine: (jobIds) {
        if (!mounted) return;
        setState(() {
          _jobs = JobSummaryVisibility.withoutJobs(_jobs, jobIds);
          _loading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _repairSearch.dispose();
    _jobVisibility.dispose();
    _retirement?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomerServiceHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId) {
      _jobVisibility.dispose();
      _jobs = const [];
      _documents = const [];
      _expenses = const [];
      _loading = true;
      _listenForQuarantine();
      _load();
    }
  }

  Future<List<Map<String, dynamic>>> _filterRetiredDocuments(
    String businessId,
    Iterable<Map<String, dynamic>> rows,
  ) async {
    final blocked = await LocalJobRetirement.blockedDocumentIds(
      localDatabase,
      businessId,
    );
    return rows
        .where(
          (row) =>
              !blocked.contains('${row['id'] ?? row['document_id'] ?? ''}'),
        )
        .toList();
  }

  Future<void> _refreshRetiredDocuments() async {
    final businessId = widget.businessId;
    try {
      final documents = await _filterRetiredDocuments(businessId, _documents);
      if (!mounted || widget.businessId != businessId) return;
      setState(() {
        _documents = documents;
        _documentSummaries.clear();
      });
    } catch (_) {
      if (mounted && widget.businessId == businessId) {
        setState(() => _documents = const []);
      }
    }
  }

  Future<bool> _showCachedHistory(
    JobSummaryVisibility visibility, int generation,
    String businessId, String customerId,
  ) async {
    final cached = await _cache.load(businessId, customerId, 'service_history');
    final data = cached is Map ? Map<String, dynamic>.from(cached)
        : <String, dynamic>{};
    final localJobs = await LocalJobRepository().forCustomer(businessId, customerId);
    final localDocuments = await CustomerDocumentSummaryService().forCustomer(
      businessId, customerId, includeClosed: true);
    List<Map<String, dynamic>> merge(Object? raw, List<Map<String, dynamic>> local) {
      final byId = <String, Map<String, dynamic>>{};
      for (final row in [...(raw is List ? raw : const []).whereType<Map>(), ...local]) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = {...?byId[id], ...Map<String, dynamic>.from(row)};
      }
      return byId.values.toList();
    }
    data['jobs'] = merge(data['jobs'], localJobs);
    data['documents'] = merge(data['documents'], localDocuments);
    final jobs = await visibility.filter(
      List<dynamic>.from(data['jobs'] ?? const [])
          .whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
      cached: true,
    );
    final documents = await _filterRetiredDocuments(businessId,
      List<dynamic>.from(data['documents'] ?? const [])
          .whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
    );
    if (!mounted || !visibility.isCurrent(generation)) return true;
    setState((){
      _jobs = jobs;
      _documents = documents;
      _expenses = List<dynamic>.from(data['expenses'] ?? const [])
          .whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();

      _loading = false;
      _error = null;
    });
    return true;
  }

  Future<void> _load() async {
    _documentSummaries.clear();
    final visibility = _jobVisibility;
    final generation = visibility.beginLoad();
    final businessId = widget.businessId;
    final customerId = widget.customerId;
    final offline = BriskersConnectionModeController.instance.forceOffline;
    try {
      // Publish durable records first on every connection mode. A failed
      // remote refresh must never clear the already usable history.
      await _showCachedHistory(visibility, generation, businessId, customerId);
      if (offline) return;

      final snapshotGeneration = await visibility.captureSnapshotGeneration();
      if (!mounted || !visibility.isCurrent(generation)) return;
      final results = await Future.wait<dynamic>([
        _api.customerServiceHistory(businessId, customerId),
        _api.myBusinesses(),
      ]);
      final rows = await visibility.filter(
          List<Map<String, dynamic>>.from(results[0] as List),
      );
      final businesses = List<Map<String, dynamic>>.from(results[1] as List);
      final current = businesses.where(
        (business) => business['id']?.toString() == businessId,
      );
      final role = current.isEmpty
          ? 'office' : current.first['role']?.toString() ?? 'office';
      List<Map<String, dynamic>> documents = const [];
      List<Map<String, dynamic>> expenses = const [];
      if (<String>{'owner', 'manager', 'office'}.contains(role)) {
        try {
          final financial = await _api.customerFinancialHistory(businessId, customerId,
          );
          documents = List<dynamic>.from(financial['documents'] ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
          expenses = List<dynamic>.from(financial['expenses'] ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
        } catch (_) {
          documents = _documents;
          expenses = _expenses;
        }
      }
      if (!mounted || !visibility.isCurrent(generation)) return;
      documents = await _filterRetiredDocuments(businessId, documents);
      if (!mounted || !visibility.isCurrent(generation)) return;
      await _cache.save(businessId, customerId, 'service_history', {
        'jobs': JobSummaryVisibility.stampSnapshot(rows, snapshotGeneration),
        'documents': documents,
        'expenses': expenses,
        'role': role,
      });
      if (!mounted || !visibility.isCurrent(generation)) return;
      await _showCachedHistory(visibility, generation, businessId, customerId);
    } catch (error) {
      if (!mounted || !visibility.isCurrent(generation)) return;
      try {
        if (await _showCachedHistory(visibility, generation, businessId, customerId,
        )) {
          return;
        }
      } catch (_) {
        // Do not publish a cache whose Job access could not be checked.
      }
      if (!mounted || !visibility.isCurrent(generation)) return;
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
        const SnackBar(content: Text('No completed jobs are available to match.'),
        ),
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
      setState(() => _error = 'Could not scan the selected photo folder. $error',
      );
      return;
    }
    if (picked == null || !mounted) return;

    final files = picked
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final matches = _historicalMatcher.exactMatches(
      completedJobs,
      files);
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
            '${previewLines.isEmpty ? '' : '\n\n${previewLines.join('\n')}'}'
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

  List<Map<String, dynamic>> get _visibleInvoices {
    // Browsing the unfiltered list is the primary history workflow.
    // Search is a convenience and must never determine record existence.
    final invoices = _documents
        .where((row) => row['kind']?.toString() == 'invoice')
        .where(_matchesVehicle)
        .where((row) => VehicleInvoiceRepairSearch.matches(row, _repairQuery))
        .toList();
    invoices.sort((a, b) {
      final first = DateTime.tryParse(a['document_date']?.toString() ?? '');
      final second = DateTime.tryParse(b['document_date']?.toString() ?? '');
      if (first == null) return second == null ? 0 : 1;
      if (second == null) return -1;
      return second.compareTo(first);
    });
    return invoices;
  }

  List<Map<String, dynamic>> get _unmatchedCustomerInvoices => _documents
      .where((row) => row['kind']?.toString() == 'invoice')
      .where((row) => (row['vehicle_id']?.toString().trim() ?? '').isEmpty)
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
          roleCode: _roleCode,
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
                  fontWeight: FontWeight.w800),
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
                  fontWeight: FontWeight.w800),
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
                          fontWeight: FontWeight.w800),
                      ),
                      if (_view == choice.$1) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.check),
                      ],
                    ],
                  ),
                  onTap: () => Navigator.pop(sheetContext, choice.$1),
                ),
            ),
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
                  fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700),
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

  /// Show each invoice even when its line-item detail has not cached yet.
  /// Expand to inspect every available repair without opening each invoice.
  Widget _invoiceRepairRow(Map<String, dynamic> document) {
    final id = document['id']?.toString() ?? '';
    final number = document['document_number']?.toString().trim() ?? '';
    final date = _shortDate(document['document_date']);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('repair-history-invoice-$id'),
      future: _documentSummaries.putIfAbsent(
        id,
        () => CustomerDocumentSummaryService().hydrate(
          widget.businessId, document),
      ),
      builder: (context, snapshot) {
        final detail = snapshot.hasData && snapshot.data!.isNotEmpty
            ? snapshot.data! : document;
        final repairs = VehicleInvoiceRepairSearch.repairDescriptions(detail);
        final status = DocumentPresentation(detail).statusLabel;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: ExpansionTile(
            key: ValueKey('repair-history-expand-$id'),
            leading: const Icon(Icons.receipt_long_outlined,
                color: BriskersColors.invoices),
            title: Text(number.isEmpty
                ? 'Invoice pending sync' : 'Invoice #$number',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date.isNotEmpty) Text(date),
                Text(repairs.isEmpty
                    ? 'Open invoice to view repairs'
                    : repairs.length == 1
                        ? repairs.first
                        : '${repairs.first} (+${repairs.length - 1} more)',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                if (status.isNotEmpty) Text(status),
              ],
            ),
            children: [
              const Divider(height: 1),
              if (repairs.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Repair descriptions not saved on this phone. '
                        'The invoice remains available to open.'),
                  ),
                )
              else
                for (final repair in repairs)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.build_outlined, size: 18),
                    title: Text(repair),
                  ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openDocument(document),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open invoice'),
                ),
              ),
            ],
          ),
        );
      },
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
        if (label == 'invoices') return _invoiceRepairRow(document);
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
          subtitle: FutureBuilder<Map<String, dynamic>>(
            future: _documentSummaries.putIfAbsent(document['id'].toString(),
              () => CustomerDocumentSummaryService().hydrate(widget.businessId, document,
              ),
            ),
            builder: (context, snapshot) => Text(
              <String>[
                if (label == 'invoices')
                  VehicleInvoiceRepairSearch.summary(snapshot.hasData
                      ? snapshot.data! : document),
                if (snapshot.hasData) DocumentPresentation(snapshot.data!).statusLabel,
                if (jobNumber.isNotEmpty) 'Job $jobNumber',
                if (vehicle.isNotEmpty) vehicle,
                if (date.isNotEmpty) date,
              ].join(' • '),
            ),
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
        final unmatched = _unmatchedCustomerInvoices;
        return Column(
          children: [
            _documentsList(_visibleInvoices, 'invoices'),
            if (_selectedVehicleId != null && unmatched.isNotEmpty)
              ExpansionTile(
                leading: const Icon(Icons.help_outline),
                title: Text('Unmatched customer invoices (${unmatched.length})'),
                subtitle: const Text('Vehicle not confirmed — review separately'),
                children: [
                  _documentsList(unmatched, 'invoices'),
                ],
              ),
          ],
        );
      case 'expenses':
        return _expensesList();
      case 'jobs':
      default:
        return _jobsList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _view == 'invoices'
        ? _visibleInvoices.length : _visibleJobs.length;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
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
                    color: Theme.of(context).colorScheme.error),
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
            if (_view == 'invoices') Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: SearchBar(
                key: const ValueKey('vehicle-repair-history-search'),
                controller: _repairSearch,
                hintText: 'Search repairs, parts or invoice #',
                leading: const Icon(Icons.search),
                trailing: [
                  if (_repairQuery.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear repair search',
                      onPressed: () {
                        _repairSearch.clear();
                        setState(() => _repairQuery = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
                ],
                onChanged: (value) => setState(() => _repairQuery = value),
              ),
            ),
            const Divider(height: 1),
            _selectedHistory(),
          ],
        ],
      ),
    );
  }
}

