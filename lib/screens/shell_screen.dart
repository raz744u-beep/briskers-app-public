import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/employee_role_style.dart';
import '../services/briskers_api.dart';
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
  int _todayRefreshToken = 0;
  int _customersRefreshToken = 0;
  int _jobsRefreshToken = 0;
  Map<String, dynamic> _navCounts = const {
    'customers': 0,
    'appointments': 0,
    'jobs': 0,
  };
  late String _businessName;
  final Map<int, Widget> _lazyPages = {};

  @override
  void initState() {
    super.initState();
    _businessName = widget.businessName;
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
      if (index == 0) _todayRefreshToken++;
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

  @override
  Widget build(BuildContext context) {
    final activeColor = _sectionColors[_index];
    final isHome = _index == 0;
    final roleStyle = employeeRoleStyle(_roleLabel);
    final pageTitles = ['Home', tr('customers'), tr('appointments'), tr('jobs'), tr('invoices'), tr('more')];
    Widget buildPage(int index) {
      return _lazyPages.putIfAbsent(index, () {
        switch (index) {
          case 0:
            return const HomeScreen();
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
              onJobsChanged: _refreshNavCounts,
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
