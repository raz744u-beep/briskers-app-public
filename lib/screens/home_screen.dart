import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/connection_mode.dart';
import '../services/briskers_api.dart';
import '../services/local_job_repository.dart';
import '../services/local_document_repository.dart';
import '../services/offline_document_draft_service.dart';
import '../services/weather_service.dart';
import 'appointments/appointment_manage_screen.dart';
import 'customers/new_customer_screen.dart';
import 'documents_screen.dart';
import 'expenses/expense_entry_screen.dart';
import 'expenses_screen.dart';
import 'jobs/blank_invoice_setup_screen.dart';
import 'jobs/estimate_job_setup_screen.dart';
import 'jobs/identifix_estimate_import_screen.dart';
import 'jobs/job_document_screen.dart';
import 'jobs/job_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onCustomersTap,
    required this.onAppointmentsTap,
    required this.onJobsTap,
    required this.onInvoicesTap,
    required this.onMoreTap,
    required this.businessId,
    required this.roleCode,
    required this.jobsCount,
    this.appointmentsCount = 0,
    this.customersNewCount = 0,
    this.estimatesOpenCount = 0,
    this.invoicesOpenCount = 0,
    this.attentionRefreshToken = 0,
  });

  final VoidCallback onCustomersTap;
  final VoidCallback onAppointmentsTap;
  final VoidCallback onJobsTap;
  final VoidCallback onInvoicesTap;
  final VoidCallback onMoreTap;
  final String businessId;
  final String roleCode;
  final int jobsCount;
  final int appointmentsCount;
  final int customersNewCount;
  final int estimatesOpenCount;
  final int invoicesOpenCount;
  final int attentionRefreshToken;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _api = BriskersApi();
  final LocalJobRepository _localJobs = LocalJobRepository();
  final LocalDocumentRepository _localDocuments = LocalDocumentRepository();
  final OfflineDocumentDraftService _offlineDocumentDraft =
      OfflineDocumentDraftService();
  final BriskersWeatherService _weatherService = BriskersWeatherService();

  String? _expandedSection;
  Map<String, dynamic> _attention = const {};
  bool _attentionLoading = false;
  BriskersWeatherSnapshot? _weather;
  bool _weatherLoading = false;

  final Map<String, GlobalKey> _drawerKeys = {
    'customers': GlobalKey(),
    'appointments': GlobalKey(),
    'estimates': GlobalKey(),
    'invoices': GlobalKey(),
    'expenses': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _loadAttention();
    _loadWeather();
    BriskersConnectionModeController.instance.addListener(_onConnectionMode);
  }

  void _onConnectionMode() {
    if (mounted) _loadAttention();
  }

  @override
  void dispose() {
    BriskersConnectionModeController.instance.removeListener(_onConnectionMode);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.roleCode != widget.roleCode ||
        oldWidget.jobsCount != widget.jobsCount ||
        oldWidget.appointmentsCount != widget.appointmentsCount ||
        oldWidget.invoicesOpenCount != widget.invoicesOpenCount ||
        oldWidget.attentionRefreshToken != widget.attentionRefreshToken) {
      _loadAttention();
      if (oldWidget.businessId != widget.businessId ||
          oldWidget.attentionRefreshToken != widget.attentionRefreshToken) {
        _loadWeather();
      }
    }
  }

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  bool get _allowRecurring =>
      widget.roleCode == 'owner' || widget.roleCode == 'manager';

  IconData _weatherIcon(String key) {
    switch (key) {
      case 'sunny':
        return Icons.wb_sunny_outlined;
      case 'partly_cloudy':
        return Icons.wb_cloudy_outlined;
      case 'rain':
        return Icons.grain_outlined;
      case 'storm':
        return Icons.thunderstorm_outlined;
      case 'snow':
        return Icons.ac_unit_outlined;
      case 'fog':
        return Icons.foggy;
      default:
        return Icons.cloud_outlined;
    }
  }

  Future<void> _loadWeather({bool forceRefresh = false}) async {
    if (_weatherLoading) return;
    _weatherLoading = true;

    try {
      final cached = await _weatherService.loadCached(widget.businessId);
      if (mounted && cached != null) {
        setState(() => _weather = cached);
      }

      final weather = await _weatherService.load(
        widget.businessId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() => _weather = weather ?? _weather);
    } finally {
      _weatherLoading = false;
      if (mounted) setState(() {});
    }
  }

  int _attentionCount(String key) {
    final counts = _attention['counts'];
    if (counts is! Map) return 0;
    return int.tryParse(counts[key]?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> _attentionItems(String key) {
    final raw = _attention[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _loadAttention() async {
    if (_attentionLoading) return;
    _attentionLoading = true;

    try {
      final localJobs = await _localJobs.unassignedOpenJobs(
        widget.businessId,
        limit: 25,
      );
      final localCount =
          await _localJobs.unassignedOpenJobCount(widget.businessId);
      final localPending = await _localDocuments.pendingCloseAttention(
        widget.businessId,
      );

      if (mounted) {
        final currentCounts = _attention['counts'] is Map
            ? Map<String, dynamic>.from(_attention['counts'] as Map)
            : <String, dynamic>{};
        final next = Map<String, dynamic>.from(_attention)
          ..['unassigned_jobs'] = localJobs
          ..['pending_close_invoices'] = localPending['items']
          ..['counts'] = {
            ...currentCounts,
            'unassigned_jobs': localCount,
            'pending_close_invoices': localPending['count'],
          };
        setState(() => _attention = next);
      }

      if (BriskersConnectionModeController.instance.forceOffline) {
        return;
      }

      try {
        final data = await _api.needsAttention(widget.businessId);
        if (!mounted) return;
        setState(() => _attention = data);
      } catch (_) {
        // Keep the local unassigned-jobs result and the last server snapshot.
      }
    } finally {
      _attentionLoading = false;
    }
  }

  String _attentionTitle(String key) {
    switch (key) {
      case 'appointment_requests':
        return 'Appointment Requests';
      case 'pending_close_invoices':
        return 'Pending Close Invoices';
      case 'unassigned_jobs':
        return 'Unassigned Jobs';
      case 'unread_messages':
        return 'Unread Messages';
      default:
        return 'Needs Attention';
    }
  }

  IconData _attentionIcon(String key) {
    switch (key) {
      case 'appointment_requests':
        return Icons.calendar_month_outlined;
      case 'pending_close_invoices':
        return Icons.receipt_long_outlined;
      case 'unassigned_jobs':
        return Icons.build_outlined;
      case 'unread_messages':
        return Icons.chat_bubble_outline;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Future<void> _openAttentionJob(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: id,
          roleCode: widget.roleCode,
        ),
      ),
    );
    await _loadAttention();
  }

  Future<void> _showAttentionCategory(String key) async {
    if (key == 'unread_messages') {
      final count = _attentionCount(key);
      if (count <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chat read/unread tracking will be connected when the Chat section is built.',
            ),
          ),
        );
        return;
      }
      widget.onMoreTap();
      return;
    }

    final items = _attentionItems(key);
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No ${_attentionTitle(key).toLowerCase()} right now.',
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: [
              ListTile(
                leading: Icon(_attentionIcon(key)),
                title: Text(
                  _attentionTitle(key),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                trailing: Text(
                  '${_attentionCount(key)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = items[index];

                    if (key == 'appointment_requests') {
                      final customer =
                          item['customer_name']?.toString() ?? 'Customer';
                      final vehicle = item['vehicle']?.toString() ?? '';
                      final description =
                          item['description']?.toString() ?? '';
                      final preferred = DateTime.tryParse(
                        item['preferred_start']?.toString() ?? '',
                      )?.toLocal();
                      final date = preferred == null
                          ? ''
                          : DateFormat('MMM d, yyyy • h:mm a')
                              .format(preferred);
                      return ListTile(
                        leading: const Icon(Icons.pending_actions_outlined),
                        title: Text(customer),
                        subtitle: Text(
                          <String>[
                            if (vehicle.isNotEmpty) vehicle,
                            if (date.isNotEmpty) date,
                            if (description.isNotEmpty) description,
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          widget.onAppointmentsTap();
                        },
                      );
                    }

                    if (key == 'pending_close_invoices') {
                      final number =
                          item['document_number']?.toString() ?? '';
                      final customer =
                          item['customer_name']?.toString() ?? 'Customer';
                      final vehicle = item['vehicle']?.toString() ?? '';
                      final job = item['job_number']?.toString() ?? '';
                      return ListTile(
                        leading: const Icon(
                          Icons.receipt_long_outlined,
                          color: BriskersColors.invoices,
                        ),
                        title: Text(
                          number.isEmpty ? 'Invoice' : 'Invoice #$number',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          <String>[
                            customer,
                            if (vehicle.isNotEmpty) vehicle,
                            if (job.isNotEmpty) 'Job $job',
                          ].join(' • '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          final id = item['id']?.toString() ?? '';
                          if (id.isNotEmpty) await _openDocument(id);
                        },
                      );
                    }

                    final number = item['job_number']?.toString() ?? '';
                    final customer =
                        item['customer_name']?.toString() ?? 'Customer';
                    final vehicle = item['vehicle']?.toString() ?? '';
                    final title = item['title']?.toString() ?? '';
                    return ListTile(
                      leading: const Icon(
                        Icons.build_outlined,
                        color: BriskersColors.jobs,
                      ),
                      title: Text(
                        <String>[
                          if (number.isNotEmpty) number,
                          customer,
                        ].join(' • '),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        <String>[
                          if (vehicle.isNotEmpty) vehicle,
                          if (title.isNotEmpty) title,
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _openAttentionJob(item);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllAttention() async {
    final categories = <String>[
      'appointment_requests',
      'pending_close_invoices',
      'unassigned_jobs',
      'unread_messages',
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
                'Needs Attention',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...categories.map(
              (key) => ListTile(
                leading: Icon(_attentionIcon(key)),
                title: Text(_attentionTitle(key)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_attentionCount(key)}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _attentionCount(key) > 0
                            ? const Color(0xFFC62828)
                            : const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.pop(sheetContext, key),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;
    await _showAttentionCategory(selected);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _toggleSection(String section) {
    final opening = _expandedSection != section;
    setState(() {
      _expandedSection = opening ? section : null;
    });

    if (!opening) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final drawerContext = _drawerKeys[section]?.currentContext;
      if (drawerContext == null) return;
      Scrollable.ensureVisible(
        drawerContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.52,
      );
    });
  }

  Future<Map<String, dynamic>?> _pickActiveJob(String title) async {
    List<Map<String, dynamic>> jobs;
    try {
      jobs = await _localJobs.listJobs(widget.businessId, limit: 100);
    } catch (_) {
      jobs = const [];
    }

    jobs = jobs
        .where((job) {
          final status = job['status']?.toString() ?? '';
          return status != 'completed' && status != 'cancelled';
        })
        .toList();

    if (!mounted) return null;
    if (jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no active jobs to select.')),
      );
      return null;
    }

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.68,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('Select the job to continue'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    indent: 56,
                  ),
                  itemBuilder: (_, index) {
                    final job = jobs[index];
                    final number = job['job_number']?.toString() ?? '';
                    final customer =
                        job['customer_name']?.toString() ?? 'Customer';
                    final vehicle = job['vehicle']?.toString() ?? '';
                    final titleText = job['title']?.toString() ?? '';
                    return ListTile(
                      leading: const Icon(Icons.build_outlined),
                      title: Text(
                        <String>[
                          if (number.isNotEmpty) number,
                          customer,
                        ].join(' • '),
                      ),
                      subtitle: Text(
                        <String>[
                          if (vehicle.isNotEmpty) vehicle,
                          if (titleText.isNotEmpty) titleText,
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(sheetContext, job),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _chooseEstimateJob(String title) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Use an existing Job or create a new Pending approval Job.',
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.build_outlined,
                color: BriskersColors.jobs,
              ),
              title: const Text('Existing Job'),
              subtitle: const Text('Select one of the active jobs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheetContext, 'existing'),
            ),
            ListTile(
              leading: const Icon(
                Icons.add_circle_outline,
                color: BriskersColors.estimates,
              ),
              title: const Text('New Job for Estimate'),
              subtitle: const Text('Select customer, vehicle and brief title'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheetContext, 'new'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return null;
    if (choice == 'existing') {
      return _pickActiveJob(title);
    }

    if (BriskersConnectionModeController.instance.forceOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Creating a brand-new Job still requires a connection. '
            'Select Existing Job to create an estimate offline.',
          ),
        ),
      );
      return null;
    }

    return Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateJobSetupScreen(
          businessId: widget.businessId,
        ),
      ),
    );
  }

  Future<void> _openDocument(String documentId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: documentId,
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: _canManage,
        ),
      ),
    );
    await _loadAttention();
  }

  Future<void> _createEstimate() async {
    if (!_canManage) return;
    final job = await _chooseEstimateJob('New Estimate');
    if (job == null || !mounted) return;
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty) return;

    try {
      final documentId =
          BriskersConnectionModeController.instance.forceOffline
              ? await _offlineDocumentDraft.createEstimate(
                  widget.businessId,
                  jobId,
                )
              : await _api.createEstimate(widget.businessId, jobId);
      if (!mounted) return;
      await _openDocument(documentId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create estimate: $error')),
      );
    }
  }

  Future<void> _scanEstimate({
    required String sourceType,
    required String title,
  }) async {
    if (!_canManage) return;
    final job = await _chooseEstimateJob(title);
    if (job == null || !mounted) return;
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty) return;

    final documentId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => IdentifixEstimateImportScreen(
          businessId: widget.businessId,
          jobId: jobId,
          customerName:
              job['customer_name']?.toString().trim().isNotEmpty == true
                  ? job['customer_name'].toString()
                  : 'Customer',
          vehicle: job['vehicle']?.toString() ?? '',
          sourceType: sourceType,
        ),
      ),
    );

    if (!mounted || documentId == null || documentId.isEmpty) return;
    await _openDocument(documentId);
  }

  Future<void> _scanIdentifixEstimate() => _scanEstimate(
        sourceType: 'identifix',
        title: 'Scan from Identifix',
      );

  Future<void> _scanHandwrittenEstimate() => _scanEstimate(
        sourceType: 'handwritten',
        title: 'Scan Handwritten Estimate',
      );

  Future<void> _createInvoice() async {
    if (!_canManage) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'New Invoice',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Use an existing Job or create a new invoice for a customer.',
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.build_outlined,
                color: BriskersColors.jobs,
              ),
              title: const Text('Existing Job'),
              subtitle: const Text('Select one of the active jobs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheetContext, 'job'),
            ),
            ListTile(
              leading: const Icon(
                Icons.receipt_long_outlined,
                color: BriskersColors.invoices,
              ),
              title: const Text('New Invoice'),
              subtitle: const Text('Start a new invoice and choose a customer.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheetContext, 'blank'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'blank') {
      final invoiceId = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => BlankInvoiceSetupScreen(
            businessId: widget.businessId,
          ),
        ),
      );
      if (!mounted || invoiceId == null || invoiceId.isEmpty) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDocumentScreen(
            businessId: widget.businessId,
            documentId: invoiceId,
            isOwner: widget.roleCode == 'owner',
            canManageExpenses: _canManage,
            initialAction: 'edit',
          ),
        ),
      );
      return;
    }

    final job = await _pickActiveJob('New Invoice');
    if (job == null || !mounted) return;
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty) return;

    try {
      final documentId = await _api.createInvoice(widget.businessId, jobId);
      if (!mounted) return;
      await _openDocument(documentId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create invoice: $error')),
      );
    }
  }

  Future<void> _viewEstimates() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsScreen(
          businessId: widget.businessId,
          kind: 'estimate',
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: _canManage,
        ),
      ),
    );
  }

  Future<void> _newAppointment() async {
    if (!_canManage) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentManageScreen(
          businessId: widget.businessId,
        ),
      ),
    );
  }

  Future<void> _viewExpenses() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpensesScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
        ),
      ),
    );
  }

  Future<void> _newExpense({bool scan = false}) async {
    if (!_canManage) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          initialDirection: 'expense',
          allowRecurring: _allowRecurring,
          autoScanReceipt: scan,
        ),
      ),
    );
  }

  Future<void> _quickExpense() async {
    if (!_canManage) return;

    try {
      final data = await _api.transactionOptions(widget.businessId);
      final templates = List<dynamic>.from(
        data['quick_templates'] ?? const <dynamic>[],
      )
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .where((row) => row['direction']?.toString() == 'expense')
          .toList();

      if (!mounted) return;
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No quick expense templates are defined yet. Add them in Settings.',
            ),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Quick Expense',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ...templates.map(
                (item) => ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: Text(
                    <String>[
                      if ((item['vendor']?.toString() ?? '').isNotEmpty)
                        item['vendor'].toString(),
                      if ((item['category']?.toString() ?? '').isNotEmpty)
                        item['category'].toString(),
                      if ((item['account']?.toString() ?? '').isNotEmpty)
                        item['account'].toString(),
                    ].join(' • '),
                  ),
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              ),
            ],
          ),
        ),
      );

      if (!mounted || selected == null) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ExpenseEntryScreen(
            businessId: widget.businessId,
            initialDirection: 'expense',
            quickTemplate: selected,
            allowRecurring: _allowRecurring,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load quick expenses: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 158,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    right: -12,
                    top: 22,
                    width: 230,
                    child: Opacity(
                      opacity: 0.20,
                      child: Image.asset(
                        'assets/home_car.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 14, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/briskers_header_logo.png',
                              width: 176,
                              fit: BoxFit.contain,
                            ),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_greeting()}, Raz',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, MMM d, yyyy').format(now),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _loadWeather(forceRefresh: true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  _weatherIcon(_weather?.iconKey ?? 'cloud'),
                                  size: 19,
                                  color: _weather?.iconKey == 'storm'
                                      ? const Color(0xFFC62828)
                                      : const Color(0xFFF4B400),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    _weather == null
                                        ? (_weatherLoading
                                            ? 'Weather…'
                                            : 'Weather unavailable')
                                        : '${_weather!.temperatureF.round()}° • ${_weather!.condition}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if ((_weather?.message ?? '').isNotEmpty)
                                  Text(
                                    _weather!.message,
                                    style: TextStyle(
                                      color: _weather!.iconKey == 'storm'
                                          ? const Color(0xFFC62828)
                                          : const Color(0xFFE58A00),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                if (_weatherLoading) ...[
                                  const SizedBox(width: 8),
                                  const SizedBox.square(
                                    dimension: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _NeedsAttentionPanel(
              appointmentRequests:
                  _attentionCount('appointment_requests'),
              pendingCloseInvoices:
                  _attentionCount('pending_close_invoices'),
              unassignedJobs:
                  _attentionCount('unassigned_jobs'),
              unreadMessages:
                  _attentionCount('unread_messages'),
              onAppointmentRequests: () =>
                  _showAttentionCategory('appointment_requests'),
              onPendingCloseInvoices: () =>
                  _showAttentionCategory('pending_close_invoices'),
              onUnassignedJobs: () =>
                  _showAttentionCategory('unassigned_jobs'),
              onUnreadMessages: () =>
                  _showAttentionCategory('unread_messages'),
              onViewAll: _showAllAttention,
            ),
            const SizedBox(height: 8),
            _HomeTiles(
              expandedSection: _expandedSection,
              onToggle: _toggleSection,
              customersDrawer: KeyedSubtree(
                key: _drawerKeys['customers'],
                child: _ActionDrawer(
                color: BriskersColors.customers,
                actions: [
                  _DrawerAction(
                    label: 'View Customers',
                    icon: Icons.people_outline,
                    onTap: widget.onCustomersTap,
                  ),
                  _DrawerAction(
                    label: 'New Customer',
                    icon: Icons.person_add_alt_1,
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NewCustomerScreen(
                            businessId: widget.businessId,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                ),
              ),
              appointmentsDrawer: KeyedSubtree(
                key: _drawerKeys['appointments'],
                child: _ActionDrawer(
                color: BriskersColors.appointments,
                actions: [
                  _DrawerAction(
                    label: 'View Appointments',
                    icon: Icons.calendar_month_outlined,
                    onTap: widget.onAppointmentsTap,
                  ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Appointment',
                      icon: Icons.add_circle_outline,
                      onTap: _newAppointment,
                    ),
                ],
                ),
              ),
              estimatesDrawer: KeyedSubtree(
                key: _drawerKeys['estimates'],
                child: _ActionDrawer(
                color: BriskersColors.estimates,
                actions: [
                  _DrawerAction(
                    label: 'View Estimates',
                    icon: Icons.list_alt_outlined,
                    onTap: _viewEstimates,
                  ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Estimate',
                      icon: Icons.note_add_outlined,
                      onTap: _createEstimate,
                    ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'Scan from Identifix',
                      icon: Icons.document_scanner_outlined,
                      onTap: _scanIdentifixEstimate,
                    ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'Scan Handwritten Estimate',
                      icon: Icons.edit_note_outlined,
                      onTap: _scanHandwrittenEstimate,
                    ),
                ],
                ),
              ),
              invoicesDrawer: KeyedSubtree(
                key: _drawerKeys['invoices'],
                child: _ActionDrawer(
                color: BriskersColors.invoices,
                actions: [
                  _DrawerAction(
                    label: 'View Invoices',
                    icon: Icons.receipt_long_outlined,
                    onTap: widget.onInvoicesTap,
                  ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Invoice',
                      icon: Icons.note_add_outlined,
                      onTap: _createInvoice,
                    ),
                ],
                ),
              ),
              expensesDrawer: KeyedSubtree(
                key: _drawerKeys['expenses'],
                child: _ActionDrawer(
                color: BriskersColors.expenses,
                actions: [
                  _DrawerAction(
                    label: 'View Expenses',
                    icon: Icons.payments_outlined,
                    onTap: _viewExpenses,
                  ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'Scan Expense',
                      icon: Icons.document_scanner_outlined,
                      onTap: () => _newExpense(scan: true),
                    ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Expense',
                      icon: Icons.add_card_outlined,
                      onTap: _newExpense,
                    ),
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Quick Expense',
                      icon: Icons.bolt_outlined,
                      onTap: _quickExpense,
                    ),
                ],
                ),
              ),
              onJobsTap: widget.onJobsTap,
              onMoreTap: widget.onMoreTap,
              jobsCount: widget.jobsCount,
              appointmentsCount: widget.appointmentsCount,
              customersNewCount: widget.customersNewCount,
              estimatesOpenCount: widget.estimatesOpenCount,
              invoicesOpenCount: widget.invoicesOpenCount,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _NeedsAttentionPanel extends StatelessWidget {
  const _NeedsAttentionPanel({
    required this.appointmentRequests,
    required this.pendingCloseInvoices,
    required this.unassignedJobs,
    required this.unreadMessages,
    required this.onAppointmentRequests,
    required this.onPendingCloseInvoices,
    required this.onUnassignedJobs,
    required this.onUnreadMessages,
    required this.onViewAll,
  });

  final int appointmentRequests;
  final int pendingCloseInvoices;
  final int unassignedJobs;
  final int unreadMessages;
  final VoidCallback onAppointmentRequests;
  final VoidCallback onPendingCloseInvoices;
  final VoidCallback onUnassignedJobs;
  final VoidCallback onUnreadMessages;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    Widget item(
      IconData icon,
      int count,
      String label,
      VoidCallback onTap,
    ) =>
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: count > 0
                        ? const Color(0xFFC62828)
                        : const Color(0xFF344054),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: count > 0
                          ? const Color(0xFFC62828)
                          : const Color(0xFF101828),
                    ),
                  ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF475467),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Needs Attention',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onViewAll,
                child: const Text('View All'),
              ),
            ],
          ),
          Row(
            children: [
              item(
                Icons.calendar_month_outlined,
                appointmentRequests,
                'Appointment\nRequests',
                onAppointmentRequests,
              ),
              const SizedBox(
                height: 58,
                child: VerticalDivider(width: 1),
              ),
              item(
                Icons.receipt_long_outlined,
                pendingCloseInvoices,
                'Pending Close\nInvoices',
                onPendingCloseInvoices,
              ),
              const SizedBox(
                height: 58,
                child: VerticalDivider(width: 1),
              ),
              item(
                Icons.build_outlined,
                unassignedJobs,
                'Unassigned\nJobs',
                onUnassignedJobs,
              ),
              const SizedBox(
                height: 58,
                child: VerticalDivider(width: 1),
              ),
              item(
                Icons.chat_bubble_outline,
                unreadMessages,
                'Unread\nMessages',
                onUnreadMessages,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeTiles extends StatelessWidget {
  const _HomeTiles({
    required this.expandedSection,
    required this.onToggle,
    required this.customersDrawer,
    required this.appointmentsDrawer,
    required this.estimatesDrawer,
    required this.invoicesDrawer,
    required this.expensesDrawer,
    required this.onJobsTap,
    required this.onMoreTap,
    required this.jobsCount,
    required this.appointmentsCount,
    required this.customersNewCount,
    required this.estimatesOpenCount,
    required this.invoicesOpenCount,
  });

  final String? expandedSection;
  final ValueChanged<String> onToggle;
  final Widget customersDrawer;
  final Widget appointmentsDrawer;
  final Widget estimatesDrawer;
  final Widget invoicesDrawer;
  final Widget expensesDrawer;
  final VoidCallback onJobsTap;
  final VoidCallback onMoreTap;
  final int jobsCount;
  final int appointmentsCount;
  final int customersNewCount;
  final int estimatesOpenCount;
  final int invoicesOpenCount;

  Widget _tile(
    String label,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 71,
        padding: const EdgeInsets.fromLTRB(12, 6, 9, 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101828),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF667085),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: color, size: 23),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget row(Widget left, Widget right) => Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          row(
            _tile(
              'Customers',
              '$customersNewCount New',
              Icons.people_outline,
              BriskersColors.customers,
              () => onToggle('customers'),
            ),
            _tile(
              'Appointments',
              '$appointmentsCount Today',
              Icons.calendar_month_outlined,
              BriskersColors.appointments,
              () => onToggle('appointments'),
            ),
          ),
          if (expandedSection == 'customers' ||
              expandedSection == 'appointments') ...[
            const SizedBox(height: 5),
            expandedSection == 'customers'
                ? customersDrawer
                : appointmentsDrawer,
          ],
          const SizedBox(height: 5),
          row(
            _tile(
              'Estimates',
              '$estimatesOpenCount Open',
              Icons.request_quote_outlined,
              BriskersColors.estimates,
              () => onToggle('estimates'),
            ),
            _tile(
              'Invoices',
              '$invoicesOpenCount Not Closed',
              Icons.receipt_long_outlined,
              BriskersColors.invoices,
              () => onToggle('invoices'),
            ),
          ),
          if (expandedSection == 'estimates' ||
              expandedSection == 'invoices') ...[
            const SizedBox(height: 5),
            expandedSection == 'estimates'
                ? estimatesDrawer
                : invoicesDrawer,
          ],
          const SizedBox(height: 5),
          row(
            _tile(
              'Jobs',
              '$jobsCount Active',
              Icons.build_outlined,
              BriskersColors.jobs,
              onJobsTap,
            ),
            _tile(
              'Expenses',
              '0 Today',
              Icons.payments_outlined,
              BriskersColors.expenses,
              () => onToggle('expenses'),
            ),
          ),
          if (expandedSection == 'expenses') ...[
            const SizedBox(height: 5),
            expensesDrawer,
          ],
          const SizedBox(height: 5),
          row(
            _tile(
              'Reports',
              'View Reports',
              Icons.bar_chart_outlined,
              BriskersColors.reports,
              onMoreTap,
            ),
            _tile(
              'Chat',
              '0 Unread',
              Icons.chat_bubble_outline,
              BriskersColors.chat,
              onMoreTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerAction {
  const _DrawerAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActionDrawer extends StatelessWidget {
  const _ActionDrawer({
    required this.color,
    required this.actions,
  });

  final Color color;
  final List<_DrawerAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            ListTile(
              dense: true,
              minVerticalPadding: 8,
              leading: Icon(actions[index].icon, color: color),
              title: Text(
                actions[index].label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 22),
              onTap: actions[index].onTap,
            ),
            if (index < actions.length - 1)
              Divider(
                height: 1,
                indent: 52,
                color: color.withValues(alpha: 0.22),
              ),
          ],
        ],
      ),
    );
  }
}
