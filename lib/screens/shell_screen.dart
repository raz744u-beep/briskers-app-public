import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import 'appointments_screen.dart';
import 'customers/customers_screen.dart';
import 'dashboard_screen.dart';
import 'jobs_screen.dart';
import 'more_screen.dart';

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
    BriskersColors.more,
  ];

  int _index = 0;
  int _todayRefreshToken = 0;
  int _customersRefreshToken = 0;
  int _jobsRefreshToken = 0;
  late String _businessName;

  @override
  void initState() {
    super.initState();
    _businessName = widget.businessName;
  }

  void _goTo(int index) {
    setState(() {
      _index = index;
      if (index == 0) _todayRefreshToken++;
      if (index == 1) _customersRefreshToken++;
      if (index == 3) _jobsRefreshToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _sectionColors[_index];
    final pages = [
      DashboardScreen(
        businessId: widget.businessId,
        roleCode: widget.roleCode,
        refreshToken: _todayRefreshToken,
        onCustomersTap: () => _goTo(1),
        onAppointmentsTap: () => _goTo(2),
      ),
      CustomersScreen(
        businessId: widget.businessId,
        refreshToken: _customersRefreshToken,
      ),
      AppointmentsScreen(
        businessId: widget.businessId,
        roleCode: widget.roleCode,
      ),
      JobsScreen(
        businessId: widget.businessId,
        roleCode: widget.roleCode,
        refreshToken: _jobsRefreshToken,
      ),
      MoreScreen(
        businessId: widget.businessId,
        businessName: _businessName,
        roleCode: widget.roleCode,
        onBusinessNameChanged: (name) => setState(() => _businessName = name),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: activeColor.withValues(alpha: 0.08),
        title: Text(
          _businessName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.roleCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.roleCode.toUpperCase(),
                    style: TextStyle(
                      color: activeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Schedule',
            ),
            NavigationDestination(
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build),
              label: 'Jobs',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
