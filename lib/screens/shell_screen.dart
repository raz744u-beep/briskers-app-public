import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/employee_role_style.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/appointment_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/local_appointment_repository.dart';
import '../services/local_customer_repository.dart';
import '../services/local_document_repository.dart';
import '../services/local_job_repository.dart';
import '../widgets/briskers_page_header.dart';
import 'appointments_screen.dart';
import 'customers/customers_screen.dart';
import 'home_screen.dart';
import 'jobs_screen.dart';
import 'more_screen.dart';
import 'documents_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({
    super.key,
    required this.businessId,
    required this.businessName,
    required this.roleCode,
  });

  final String businessId;
  final String businessName;
  final String roleCode;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  static const _sectionColors = [
    BriskersColors.today,
    BriskersColors.customers,
    BriskersColors.schedule,
    BriskersColors.jobs,
    BriskersColors.invoices,
    BriskersColors.more,
  ];

  int _index = 0;
  int _customersRefreshToken = 0;
  int _jobsRefreshToken = 0;
  int _homeAttentionRefreshToken = 0;
  Map<String, dynamic> _navCounts = const {
    'customers': 0,
    'appointments': 0,
    'jobs': 0,
  };
  late String _businessName;
  final Map<int, Widget> _lazyPages = {};
  final LocalJobRepository _localJobs = LocalJobRepository();
  final LocalAppointmentRepository _localAppointments =
      LocalAppointmentRepository();
  final LocalCustomerRepository _localCustomers = LocalCustomerRepository();
  final LocalDocumentRepository _localDocuments = LocalDocumentRepository();
  int _homeJobsCount = 0;
  int _homeAppointmentsCount = 0;
  int _homeCustomersNewCount = 0;
  int _homeEstimatesOpenCount = 0;
  int _homeInvoicesOpenCount = 0;
  StreamSubscription<int>? _homeJobsCountSubscription;
  StreamSubscription<String>? _homeJobsSyncSubscription;
  StreamSubscription<int>? _homeAppointmentsCountSubscription;
  StreamSubscription<String>? _homeAppointmentsSyncSubscription;
  StreamSubscription<int>? _homeCustomersTableSubscription;
  StreamSubscription<String>? _homeCustomersSyncSubscription;
  StreamSubscription<int>? _homeEstimatesCountSubscription;
  StreamSubscription<int>? _homeInvoicesCountSubscription;
  StreamSubscription<String>? _homeDocumentsSyncSubscription;

  @override
  void initState() {
    super.initState();
    _businessName = widget.businessName;
    _refreshHomeJobsCount();
    _homeJobsCountSubscription = _localJobs
        .watchActiveJobCount(widget.businessId)
        .listen((count) {
          _applyHomeJobsCount(count);
          if (mounted) {
            setState(() => _homeAttentionRefreshToken++);
          }
        });
    _homeJobsSyncSubscription = JobSyncService.syncEvents.listen((businessId) {
      if (businessId == widget.businessId) {
        _refreshHomeJobsCount();
      }
    });
    _refreshHomeAppointmentsCount();
    _homeAppointmentsCountSubscription = _localAppointments
        .watchConfirmedTodayCount(widget.businessId)
        .listen(_applyHomeAppointmentsCount);
    _homeAppointmentsSyncSubscription =
        AppointmentSyncService.syncEvents.listen((businessId) {
      if (businessId == widget.businessId) {
        _refreshHomeAppointmentsCount();
      }
    });
    _refreshHomeCustomersCount();
    _homeCustomersTableSubscription =
        _localCustomers.watchCustomerTotal(widget.businessId).listen((_) {
      _refreshHomeCustomersCount();
    });
    _homeCustomersSyncSubscription =
        CustomerVehicleSyncService.syncEvents.listen((businessId) {
      if (businessId == widget.businessId) {
        _refreshHomeCustomersCount();
      }
    });
    _refreshHomeEstimatesCount();
    _homeEstimatesCountSubscription = _localDocuments
        .watchOpenEstimateCount(widget.businessId)
        .listen(_applyHomeEstimatesCount);
    _refreshHomeInvoicesCount();
    _homeInvoicesCountSubscription = _localDocuments
        .watchOpenInvoiceCount(widget.businessId)
        .listen(_applyHomeInvoicesCount);
    _homeDocumentsSyncSubscription =
        DocumentIndexSyncService.syncEvents.listen((businessId) {
      if (businessId == widget.businessId) {
        _refreshHomeEstimatesCount();
        _refreshHomeInvoicesCount();
      }
    });
  }

  void _applyHomeJobsCount(int count) {
    if (!mounted) return;
    final navCount =
        int.tryParse(_navCounts['jobs']?.toString() ?? '') ?? 0;
    if (count == _homeJobsCount && count == navCount) return;
    setState(() {
      _homeJobsCount = count;
      _navCounts = Map<String, dynamic>.from(_navCounts)
        ..['jobs'] = count;
    });
  }

  Future<void> _refreshHomeJobsCount() async {
    try {
      final count = await _localJobs.activeJobCount(widget.businessId);
      _applyHomeJobsCount(count);
    } catch (_) {}
  }

  void _applyHomeAppointmentsCount(int count) {
    if (!mounted) return;
    final navCount =
        int.tryParse(_navCounts['appointments']?.toString() ?? '') ?? 0;
    if (count == _homeAppointmentsCount && count == navCount) return;
    setState(() {
      _homeAppointmentsCount = count;
      _navCounts = Map<String, dynamic>.from(_navCounts)
        ..['appointments'] = count;
    });
  }

  Future<void> _refreshHomeAppointmentsCount() async {
    try {
      final count =
          await _localAppointments.confirmedTodayCount(widget.businessId);
      _applyHomeAppointmentsCount(count);
    } catch (_) {}
  }

  void _applyHomeCustomersCount(int count) {
    if (!mounted) return;
    final navCount =
        int.tryParse(_navCounts['customers']?.toString() ?? '') ?? 0;
    if (count == _homeCustomersNewCount && count == navCount) return;
    setState(() {
      _homeCustomersNewCount = count;
      _navCounts = Map<String, dynamic>.from(_navCounts)
        ..['customers'] = count;
    });
  }

  Future<void> _refreshHomeCustomersCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawSince = prefs.getString(_customersViewedKey);
      final since = rawSince == null ? null : DateTime.tryParse(rawSince);
      final count = await _localCustomers.newCustomerCount(
        widget.businessId,
        since: since,
      );
      _applyHomeCustomersCount(count);
    } catch (_) {}
  }

  void _applyHomeEstimatesCount(int count) {
    if (!mounted || count == _homeEstimatesOpenCount) return;
    setState(() => _homeEstimatesOpenCount = count);
  }

  Future<void> _refreshHomeEstimatesCount() async {
    try {
      final count = await _localDocuments.openEstimateCount(widget.businessId);
      _applyHomeEstimatesCount(count);
    } catch (_) {}
  }

  void _applyHomeInvoicesCount(int count) {
    if (!mounted || count == _homeInvoicesOpenCount) return;
    setState(() => _homeInvoicesOpenCount = count);
  }

  Future<void> _refreshHomeInvoicesCount() async {
    try {
      final count = await _localDocuments.openInvoiceCount(widget.businessId);
      _applyHomeInvoicesCount(count);
    } catch (_) {}
  }

  @override
  void dispose() {
    _homeJobsCountSubscription?.cancel();
    _homeJobsSyncSubscription?.cancel();
    _homeAppointmentsCountSubscription?.cancel();
    _homeAppointmentsSyncSubscription?.cancel();
    _homeCustomersTableSubscription?.cancel();
    _homeCustomersSyncSubscription?.cancel();
    _homeEstimatesCountSubscription?.cancel();
    _homeInvoicesCountSubscription?.cancel();
    _homeDocumentsSyncSubscription?.cancel();
    super.dispose();
  }

  String get _customersViewedKey =>
      'briskers_customers_viewed_${widget.businessId}';

  Future<void> _markCustomersViewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customersViewedKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    _applyHomeCustomersCount(0);
  }

  void _goTo(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = index;
      if (index == 1) _customersRefreshToken++;
      if (index == 3) _jobsRefreshToken++;
      if (index == 0) _homeAttentionRefreshToken++;
    });
    if (index == 1) {
      _markCustomersViewed();
    }
  }

  String get _roleLabel => roleLabel(widget.roleCode);

  Widget _navIcon(
    IconData icon,
    String countKey,
  ) {
    final count = int.tryParse(_navCounts[countKey]?.toString() ?? '') ?? 0;
    if (count <= 0) return Icon(icon);
    return Badge(
      label: Text('$count'),
      smallSize: 16,
      largeSize: 18,
      child: Icon(icon),
    );
  }

  Widget _shellNavigationBar() {
    final activeColor = _sectionColors[_index];
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: NavigationBarThemeData(
          height: 70,
          backgroundColor: Colors.white,
          elevation: 4,
          indicatorColor: activeColor.withValues(alpha: 0.16),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          _goTo(index);
        },
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: _navIcon(Icons.people_outline, 'customers'), selectedIcon: _navIcon(Icons.people, 'customers'), label: tr('customers')),
          NavigationDestination(icon: _navIcon(Icons.calendar_month_outlined, 'appointments'), selectedIcon: _navIcon(Icons.calendar_month, 'appointments'), label: tr('schedule')),
          NavigationDestination(icon: _navIcon(Icons.build_outlined, 'jobs'), selectedIcon: _navIcon(Icons.build, 'jobs'), label: tr('jobs')),
          NavigationDestination(icon: _navIcon(Icons.receipt_long_outlined, 'invoices'), selectedIcon: _navIcon(Icons.receipt_long, 'invoices'), label: tr('invoices')),
          const NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _sectionColors[_index];
    final isHome = _index == 0;
    final roleStyle = employeeRoleStyle(_roleLabel);
    final pageTitles = ['Home', tr('customers'), tr('appointments'), tr('jobs'), tr('invoices'), tr('more')];
    Widget buildPage(int index) {
      if (index == 0) {
        return HomeScreen(
          onCustomersTap: () => _goTo(1),
          onAppointmentsTap: () => _goTo(2),
          onJobsTap: () => _goTo(3),
          onInvoicesTap: () => _goTo(4),
          onMoreTap: () => _goTo(5),
          businessId: widget.businessId,
          roleCode: widget.roleCode,
          jobsCount: _homeJobsCount,
          appointmentsCount: _homeAppointmentsCount,
          customersNewCount: _homeCustomersNewCount,
          estimatesOpenCount: _homeEstimatesOpenCount,
          invoicesOpenCount: _homeInvoicesOpenCount,
          attentionRefreshToken: _homeAttentionRefreshToken,
        );
      }
      return _lazyPages.putIfAbsent(index, () {
        switch (index) {
          case 1:
            return CustomersScreen(
              businessId: widget.businessId,
              refreshToken: _customersRefreshToken,
            );
          case 2:
            return AppointmentsScreen(
              businessId: widget.businessId,
              roleCode: widget.roleCode,
            );
          case 3:
            return JobsScreen(
              businessId: widget.businessId,
              roleCode: widget.roleCode,
              refreshToken: _jobsRefreshToken,
              onJobsChanged: _refreshHomeJobsCount,
              jobDetailBottomNavigationBar: _shellNavigationBar(),
            );
          case 4:
            return DocumentsScreen(
              businessId: widget.businessId,
              kind: 'invoice',
              isOwner: widget.roleCode == 'owner',
              showAppBar: false,
            );
          default:
            return MoreScreen(
              businessId: widget.businessId,
              businessName: _businessName,
              roleCode: widget.roleCode,
              onBusinessNameChanged: (name) =>
                  setState(() => _businessName = name),
            );
        }
      });
    }

    final currentPage = buildPage(_index);

    return Scaffold(
      appBar: isHome ? null : AppBar(
        backgroundColor: activeColor.withValues(alpha: 0.08),
        titleSpacing: 10,
        toolbarHeight: 78,
        title: BriskersPageTitle(
          title: pageTitles[_index],
          logoHeight: 44,
          logoWidth: 148,
        ),
        actions: [
          if (widget.roleCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: roleStyle.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _roleLabel,
                    style: TextStyle(
                      color: roleStyle.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: currentPage,
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            height: 70,
            backgroundColor: Colors.white,
            elevation: 4,
            indicatorColor: activeColor.withValues(alpha: 0.16),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                color: selected ? activeColor : const Color(0xFF667085),
                size: selected ? 27 : 25,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                color: selected ? activeColor : const Color(0xFF667085),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              );
            }),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home',
            ),
            NavigationDestination(
              icon: _navIcon(Icons.people_outline, 'customers'),
              selectedIcon: _navIcon(
                Icons.people,
                'customers',
              ),
              label: tr('customers'),
            ),
            NavigationDestination(
              icon: _navIcon(Icons.calendar_month_outlined, 'appointments'),
              selectedIcon: _navIcon(
                Icons.calendar_month,
                'appointments',
              ),
              label: tr('schedule'),
            ),
            NavigationDestination(
              icon: _navIcon(Icons.build_outlined, 'jobs'),
              selectedIcon: _navIcon(
                Icons.build,
                'jobs',
              ),
              label: tr('jobs'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: tr('invoices'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz),
              label: tr('more'),
            ),
          ],
        ),
      ),
    );
  }
}
