import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../services/briskers_api.dart';
import '../services/local_job_repository.dart';
import 'appointments/appointment_manage_screen.dart';
import 'customers/new_customer_screen.dart';
import 'documents_screen.dart';
import 'expenses/expense_entry_screen.dart';
import 'expenses_screen.dart';
import 'jobs/blank_invoice_setup_screen.dart';
import 'jobs/estimate_job_setup_screen.dart';
import 'jobs/identifix_estimate_import_screen.dart';
import 'jobs/job_document_screen.dart';

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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _api = BriskersApi();
  final LocalJobRepository _localJobs = LocalJobRepository();

  String? _expandedSection;
  final Map<String, GlobalKey> _drawerKeys = {
    'customers': GlobalKey(),
    'appointments': GlobalKey(),
    'estimates': GlobalKey(),
    'invoices': GlobalKey(),
    'expenses': GlobalKey(),
  };

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  bool get _allowRecurring =>
      widget.roleCode == 'owner' || widget.roleCode == 'manager';

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
  }

  Future<void> _createEstimate() async {
    if (!_canManage) return;
    final job = await _chooseEstimateJob('New Estimate');
    if (job == null || !mounted) return;
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty) return;

    try {
      final documentId = await _api.createEstimate(widget.businessId, jobId);
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
                'Use an existing Job or create a blank invoice for a customer.',
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
              title: const Text('Blank Invoice'),
              subtitle: const Text('Choose customer and optional vehicle'),
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
                            IconButton(
                              tooltip: 'Notifications',
                              onPressed: () {},
                              icon: const Badge(
                                smallSize: 8,
                                child: Icon(
                                  Icons.notifications_none,
                                  size: 28,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Profile',
                              onPressed: () {},
                              icon: const Icon(
                                Icons.account_circle_outlined,
                                size: 31,
                              ),
                            ),
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
                        const Row(
                          children: [
                            Icon(
                              Icons.wb_sunny_outlined,
                              size: 19,
                              color: Color(0xFFF4B400),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Weather',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Spacer(),
                            SizedBox.shrink(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const _NeedsAttentionPanel(),
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
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Estimate',
                      icon: Icons.request_quote_outlined,
                      onTap: _createEstimate,
                    ),
                  _DrawerAction(
                    label: 'View Estimates',
                    icon: Icons.list_alt_outlined,
                    onTap: _viewEstimates,
                  ),
                ],
                ),
              ),
              invoicesDrawer: KeyedSubtree(
                key: _drawerKeys['invoices'],
                child: _ActionDrawer(
                color: BriskersColors.invoices,
                actions: [
                  if (_canManage)
                    _DrawerAction(
                      label: 'New Invoice',
                      icon: Icons.note_add_outlined,
                      onTap: _createInvoice,
                    ),
                  _DrawerAction(
                    label: 'View Invoices',
                    icon: Icons.receipt_long_outlined,
                    onTap: widget.onInvoicesTap,
                  ),
                ],
                ),
              ),
              expensesDrawer: KeyedSubtree(
                key: _drawerKeys['expenses'],
                child: _ActionDrawer(
                color: BriskersColors.expenses,
                actions: [
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
                  _DrawerAction(
                    label: 'View Expenses',
                    icon: Icons.payments_outlined,
                    onTap: _viewExpenses,
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
  const _NeedsAttentionPanel();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String count, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 24, color: const Color(0xFF344054)),
              const SizedBox(height: 3),
              Text(
                count,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
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
                onPressed: () {},
                child: const Text('View All'),
              ),
            ],
          ),
          Row(
            children: [
              item(
                Icons.calendar_month_outlined,
                '0',
                'Appointment\nRequests',
              ),
              const SizedBox(
                height: 58,
                child: VerticalDivider(width: 1),
              ),
              item(
                Icons.receipt_long_outlined,
                '0',
                'Pending Close\nInvoices',
              ),
              const SizedBox(
                height: 58,
                child: VerticalDivider(width: 1),
              ),
              item(Icons.build_outlined, '0', 'Unassigned\nJobs'),
              const SizedBox(
                height: 58,
                child: VerticalDivider(width: 1),
              ),
              item(
                Icons.chat_bubble_outline,
                '0',
                'Unread\nMessages',
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
