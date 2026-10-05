import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/employee_role_style.dart';
import '../services/briskers_api.dart';
import '../services/job_sync_service.dart';
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
  static const _api = BriskersApi();

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
  Map<String, dynamic> _navCounts = const {
    'customers': 0,
    'appointments': 0,
    'jobs': 0,
  };
  late String _businessName;
  final Map<int, Widget> _lazyPages = {};
  final LocalJobRepository _localJobs = LocalJobRepository();
  int _homeJobsCount = 0;
  StreamSubscription<int>? _homeJobsCountSubscription;
  StreamSubscription<String>? _homeJobsSyncSubscription;

  @override
  void initState() {
    super.initState();
    _businessName = widget.businessName;
    _refreshHomeJobsCount();
    _homeJobsCountSubscription = _localJobs
        .watchJobCount(widget.businessId, status: 'in_progress')
        .listen(_applyHomeJobsCount);
    _homeJobsSyncSubscription = JobSyncService.syncEvents.listen((businessId) {
      if (businessId == widget.businessId) {
        _refreshHomeJobsCount();
      }
    });
  }

  void _applyHomeJobsCount(int count) {
    if (!mounted || count == _homeJobsCount) return;
    setState(() => _homeJobsCount = count);
  }

  Future<void> _refreshHomeJobsCount() async {
    try {
      final count = await _localJobs.jobCount(
        widget.businessId,
        status: 'in_progress',
      );
      _applyHomeJobsCount(count);
    } catch (_) {}
  }

  @override
  void dispose() {
    _homeJobsCountSubscription?.cancel();
    _homeJobsSyncSubscription?.cancel();
    super.dispose();
  }

  String get _customersViewedKey =>
      'briskers_customers_viewed_${widget.businessId}';

  Future<void> _refreshNavCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawSince = prefs.getString(_customersViewedKey);
      final customersSince =
          rawSince == null ? null : DateTime.tryParse(rawSince);
      final counts = await _api.attentionCounts(
        widget.businessId,
        DateFormat('yyyy-MM-dd').format(DateTime.now()),
        customersSince: customersSince,
      );
      if (!mounted) return;
      setState(() => _navCounts = counts);
    } catch (_) {}
  }

  Future<void> _markCustomersViewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customersViewedKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    if (!mounted) return;
    setState(() {
      _navCounts = Map<String, dynamic>.from(_navCounts)
        ..['customers'] = 0;
    });
    await _refreshNavCounts();
  }

  void _goTo(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = index;
      if (index == 1) _customersRefreshToken++;
      if (index == 3) _jobsRefreshToken++;
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
              onJobsChanged: () {
                _refreshNavCounts();
              },
              jobDetailBottomNavigationBar: _shellNavigationBar(),
            );
          case 4:
            return DocumentsScreen(
              businessId: widget.businessId,
              kind: 'invoice',
              isOwner: widget.roleCode == 'owner',
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
