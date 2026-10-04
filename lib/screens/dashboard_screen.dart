import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import '../widgets/job_compact_card.dart';
import 'customers/customer_detail_screen.dart';
import 'documents_screen.dart';
import 'expenses_screen.dart';
import 'jobs/job_detail_screen.dart';
import 'jobs/job_document_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.refreshToken = 0,
    this.onCustomersTap,
    this.onAppointmentsTap,
    this.onJobsChanged,
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;
  final VoidCallback? onCustomersTap;
  final VoidCallback? onAppointmentsTap;
  final VoidCallback? onJobsChanged;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _statuses = const [];
  String? _error;
  String? _busyJobId;
  bool _aiBusy = false;
  bool _activeJobsExpanded = false;
  final ScrollController _dashboardScrollController = ScrollController();
  final GlobalKey _jobsSectionKey = GlobalKey();
  double? _jobsRestoreOffset;
  int _estimateAttention = 0;
  int _invoiceAttention = 0;
  DateTime _selectedDay = DateTime.now();
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Set<String> _eventDays = <String>{};

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  String _friendlyDashboardError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network') ||
        text.contains('connection')) {
      return 'Connection unavailable. Showing the most recent saved information.';
    }
    return 'Could not refresh the dashboard. Pull down to try again.';
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _dashboardScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      setState(() {});
    }
  }

  String get _homeGreeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _homeHeader() {
    final now = DateTime.now();
    return SizedBox(
      height: 178,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -10,
            top: 28,
            width: 245,
            child: Opacity(
              opacity: 0.22,
              child: Image.asset('assets/home_car.png', fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeHeader(),
                const SizedBox(height: 6),
                _needsAttention(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Image.asset(
                      'assets/briskers_header_logo.png',
                      width: 174,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () {},
                      icon: const Badge(
                        smallSize: 8,
                        child: Icon(Icons.notifications_none, size: 28),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Profile',
                      onPressed: () {},
                      icon: const Icon(Icons.account_circle_outlined, size: 31),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _homeGreeting,
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
                const Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeTile({
    required String label,
    required IconData icon,
    required Color color,
    int? count,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 108,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 34),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if ((count ?? 0) > 0)
                      Badge(
                        backgroundColor: const Color(0xFFC62828),
                        label: Text('$count'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phaseTwoTiles(int appointmentsCount, int activeJobsCount) {
    Widget row(Widget left, Widget right) => Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );

    return Column(
      children: [
        row(
          _homeTile(
            label: tr('customers'),
            icon: Icons.people_outline,
            color: BriskersColors.customers,
            onTap: widget.onCustomersTap,
          ),
          _homeTile(
            label: tr('appointments'),
            icon: Icons.calendar_month_outlined,
            color: BriskersColors.appointments,
            count: appointmentsCount,
            onTap: widget.onAppointmentsTap,
          ),
        ),
        const SizedBox(height: 10),
        row(
          _homeTile(
            label: tr('estimates'),
            icon: Icons.request_quote_outlined,
            color: BriskersColors.estimates,
            count: _estimateAttention,
            onTap: () => _openDocuments('estimate'),
          ),
          _homeTile(
            label: tr('invoices'),
            icon: Icons.receipt_long_outlined,
            color: BriskersColors.invoices,
            count: _invoiceAttention,
            onTap: () => _openDocuments('invoice'),
          ),
        ),
        const SizedBox(height: 10),
        row(
          _homeTile(
            label: tr('jobs'),
            icon: Icons.build_outlined,
            color: BriskersColors.jobs,
            count: activeJobsCount,
            onTap: _toggleJobs,
          ),
          _homeTile(
            label: tr('expenses'),
            icon: Icons.payments_outlined,
            color: BriskersColors.expenses,
            onTap: _openExpenses,
          ),
        ),
        const SizedBox(height: 10),
        row(
          _homeTile(
            label: 'Reports',
            icon: Icons.bar_chart_outlined,
            color: BriskersColors.reports,
          ),
          _homeTile(
            label: 'Chat',
            icon: Icons.chat_bubble_outline,
            color: BriskersColors.chat,
          ),
        ),
      ],
    );
  }

  Widget _needsAttention() {
    Widget item(IconData icon, String label, int count) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 23),
              const SizedBox(height: 2),
              Text(
                count.toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Needs Attention',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
              item(Icons.calendar_month_outlined, 'Appointment\nRequests', 0),
              item(
                Icons.receipt_long_outlined,
                'Pending Close\nInvoices',
                _invoiceAttention,
              ),
              item(Icons.build_outlined, 'Unassigned\nJobs', 0),
              item(Icons.chat_bubble_outline, 'Unread\nMessages', 0),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.dashboard(
          widget.businessId,
          DateFormat('yyyy-MM-dd').format(_selectedDay),
        ),
        _api.jobStatuses(widget.businessId),
        _api.calendarEventDays(widget.businessId, _calendarMonth),
        _api.documents(widget.businessId, kind: 'estimate'),
        _api.documents(widget.businessId, kind: 'invoice'),
      ]);

      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(results[0] as Map);
        _statuses = List<Map<String, dynamic>>.from(results[1] as List);
        _eventDays = (results[2] as List<DateTime>)
            .map((day) => DateFormat('yyyy-MM-dd').format(day))
            .toSet();
        final estimates =
            List<Map<String, dynamic>>.from(results[3] as List);
        final invoices =
            List<Map<String, dynamic>>.from(results[4] as List);
        _estimateAttention = estimates.where((row) {
          final status = row['status']?.toString() ?? '';
          return row['converted'] != true &&
              !{'accepted', 'declined', 'expired', 'void'}.contains(status);
        }).length;
        _invoiceAttention = invoices.where((row) {
          final status = row['display_status_code']?.toString() ?? '';
          return status != 'paid' && status != 'void';
        }).length;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyDashboardError(error));
      }
    }
  }

  Future<void> _selectDashboardDay(DateTime day) async {
    final normalized = DateTime(day.year, day.month, day.day);
    setState(() {
      _selectedDay = normalized;
      _calendarMonth = DateTime(normalized.year, normalized.month);
    });
    await _load();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  Future<void> _showDashboardCalendar() async {
    var month = _calendarMonth;
    var selected = _selectedDay;
    var eventDays = Set<String>.from(_eventDays);
    var loadingMonth = false;

    Future<void> loadMonth(StateSetter setSheetState, DateTime value) async {
      setSheetState(() => loadingMonth = true);
      try {
        final days = await _api.calendarEventDays(widget.businessId, value);
        setSheetState(() {
          month = DateTime(value.year, value.month);
          eventDays = days.map(_dayKey).toSet();
          loadingMonth = false;
        });
      } catch (_) {
        setSheetState(() => loadingMonth = false);
      }
    }

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final first = DateTime(month.year, month.month, 1);
          final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
          final leading = first.weekday % 7;
          final cells = leading + daysInMonth;
          final rowCount = (cells / 7).ceil();

          Widget dayCell(int index) {
            final dayNumber = index - leading + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox(height: 44);
            }

            final day = DateTime(month.year, month.month, dayNumber);
            final isSelected = _sameDay(day, selected);
            final isToday = _sameDay(day, DateTime.now());
            final hasEvent = eventDays.contains(_dayKey(day));

            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                setSheetState(() => selected = day);
                Navigator.pop(sheetContext, day);
              },
              child: SizedBox(
                height: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? BriskersColors.today
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isToday && !isSelected
                            ? Border.all(
                                color: BriskersColors.today,
                                width: 1.4,
                              )
                            : null,
                      ),
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 5,
                      child: hasEvent
                          ? Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: BriskersColors.appointments,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: loadingMonth
                            ? null
                            : () => loadMonth(
                                  setSheetState,
                                  DateTime(month.year, month.month - 1),
                                ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          MaterialLocalizations.of(context).formatMonthYear(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: loadingMonth
                            ? null
                            : () => loadMonth(
                                  setSheetState,
                                  DateTime(month.year, month.month + 1),
                                ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (loadingMonth)
                    const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Expanded(child: Text('S', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('M', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('T', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('W', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('T', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('F', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(child: Text('S', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (var row = 0; row < rowCount; row++)
                    Row(
                      children: [
                        for (var column = 0; column < 7; column++)
                          Expanded(child: dayCell(row * 7 + column)),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(
                        width: 7,
                        height: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: BriskersColors.appointments,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'Scheduled event',
                        style: TextStyle(fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, DateTime.now()),
                        child: Text(tr('today')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (picked != null) {
      await _selectDashboardDay(picked);
    }
  }

  Future<Map<String, dynamic>?> _resolveAiCustomer(String query) async {
    final matches = await _api.customers(
      widget.businessId,
      search: query,
      limit: 20,
    );

    if (!mounted) return null;
    if (matches.isEmpty) {
      setState(() => _error = 'No customer found for "$query".');
      return null;
    }
    if (matches.length == 1) return matches.first;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Which customer?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            ...matches.map(
              (customer) => ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer['display_name']?.toString() ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (customer['problem_flag'] == true)
                                const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                  size: 18,
                                ),
                            ],
                          ),
                subtitle: Text(
                  '${customer['vehicle_count'] ?? 0} vehicle(s)',
                ),
                onTap: () => Navigator.pop(sheetContext, customer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _aiVehicleLabel(Map<String, dynamic> vehicle) => <String>[
        if (vehicle['year'] != null) vehicle['year'].toString(),
        if ((vehicle['make']?.toString() ?? '').isNotEmpty)
          vehicle['make'].toString(),
        if ((vehicle['model']?.toString() ?? '').isNotEmpty)
          vehicle['model'].toString(),
      ].join(' ');

  Future<Map<String, dynamic>?> _resolveAiVehicle(
    String customerId, {
    String? query,
  }) async {
    final detail = await _api.customerDetail(widget.businessId, customerId);
    final vehicles = List<dynamic>.from(detail['vehicles'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (vehicles.isEmpty) return null;

    var filtered = vehicles;
    if ((query ?? '').trim().isNotEmpty) {
      final q = query!.trim().toLowerCase();
      final hits = vehicles.where((v) {
        final label = _aiVehicleLabel(v).toLowerCase();
        final vin = v['vin']?.toString().toLowerCase() ?? '';
        return label.contains(q) || vin.contains(q);
      }).toList();
      if (hits.isNotEmpty) filtered = hits;
    }

    if (filtered.length == 1) return filtered.first;
    if (!mounted) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Which vehicle?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            ...filtered.map(
              (vehicle) => ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(_aiVehicleLabel(vehicle)),
                subtitle: (vehicle['vin']?.toString() ?? '').isEmpty
                    ? null
                    : Text('VIN: ${vehicle['vin']}'),
                onTap: () => Navigator.pop(sheetContext, vehicle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askJobTitle(String? suggested) async {
    final controller = TextEditingController(
      text: (suggested ?? '').trim().isEmpty ? 'New Job' : suggested!.trim(),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Job title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Job / service',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = controller.text.trim();
              if (title.isNotEmpty) Navigator.pop(dialogContext, title);
            },
            child: const Text('Create Job'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _executeAiPlan(Map<String, dynamic> plan) async {
    final action = plan['action']?.toString() ?? 'unknown';
    final clarification = plan['clarification']?.toString().trim() ?? '';

    if (clarification.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ask Briskers'),
          content: Text(clarification),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (action != 'create_invoice' &&
        action != 'create_estimate' &&
        action != 'create_appointment' &&
        action != 'create_job' &&
        action != 'create_customer') {
      if (!mounted) return;
      final summary = plan['summary']?.toString() ?? 'Command not supported yet.';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ask Briskers'),
          content: Text(
            '$summary\n\nThis command is understood, but this action is not wired into the first AI version yet.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final customerQuery = plan['customer_query']?.toString().trim() ?? '';
    if (customerQuery.isEmpty) {
      setState(() => _error = 'The AI command needs a customer name.');
      return;
    }

    if (action == 'create_customer') {
      final matches = await _api.customers(
        widget.businessId,
        search: customerQuery,
        limit: 20,
      );
      if (!mounted) return;

      final exact = matches.where((customer) {
        final name = customer['display_name']?.toString().trim() ?? '';
        return name.toLowerCase() == customerQuery.toLowerCase();
      }).toList();

      if (exact.isNotEmpty) {
        final existing = exact.first;
        final useExisting = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Customer already exists'),
            content: Text(
              '${existing['display_name']} already exists. Open that customer instead?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Open customer'),
              ),
            ],
          ),
        );

        if (useExisting == true && mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(
                businessId: widget.businessId,
                customerId: existing['id'].toString(),
              ),
            ),
          );
          await _load();
        }
        return;
      }

      if (matches.isNotEmpty) {
        final sampleNames = matches
            .take(3)
            .map((customer) => customer['display_name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .join(', ');

        final createAnyway = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Similar customers found'),
            content: Text(
              'Briskers found similar names: $sampleNames. Create "$customerQuery" anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create customer'),
              ),
            ],
          ),
        );

        if (createAnyway != true) return;
      }

      final customerId = await _api.createCustomer(
        widget.businessId,
        name: customerQuery,
      );

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(
            businessId: widget.businessId,
            customerId: customerId,
          ),
        ),
      );
      await _load();
      return;
    }

    final customer = await _resolveAiCustomer(customerQuery);
    if (customer == null || !mounted) return;

    final customerId = customer['id']?.toString() ?? '';
    if (customerId.isEmpty) return;

    final vehicle = await _resolveAiVehicle(
      customerId,
      query: plan['vehicle_query']?.toString(),
    );
    final vehicleId = vehicle?['id']?.toString();

    if (action == 'create_invoice') {
      final invoiceId = await _api.createQuickInvoice(
        widget.businessId,
        customerId: customerId,
        vehicleId: vehicleId,
      );

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDocumentScreen(
            businessId: widget.businessId,
            documentId: invoiceId,
            isOwner: widget.roleCode == 'owner',
          ),
        ),
      );
      await _load();
      return;
    }


    if (action == 'create_estimate') {
      final estimateId = await _api.createQuickEstimate(
        widget.businessId,
        customerId: customerId,
        vehicleId: vehicleId,
      );

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDocumentScreen(
            businessId: widget.businessId,
            documentId: estimateId,
            isOwner: widget.roleCode == 'owner',
          ),
        ),
      );
      await _load();
      return;
    }

    if (action == 'create_appointment') {
      final rawStart = plan['appointment_start']?.toString().trim() ?? '';
      final startsAt = DateTime.tryParse(rawStart);
      if (startsAt == null) {
        setState(() => _error =
            'Briskers needs a valid appointment date and time.');
        return;
      }

      final durationMinutes =
          (int.tryParse(plan['appointment_duration_minutes']?.toString() ?? '') ??
                  60)
              .clamp(1, 1440)
              .toInt();
      final appointmentTitle = plan['title']?.toString().trim() ?? '';
      final description = plan['description']?.toString().trim() ?? '';

      await _api.createAppointment(
        widget.businessId,
        customerId: customerId,
        vehicleId: vehicleId,
        title: appointmentTitle.isEmpty
            ? 'Service appointment'
            : appointmentTitle,
        description: description.isEmpty ? null : description,
        startsAt: startsAt,
        endsAt: startsAt.add(Duration(minutes: durationMinutes)),
      );

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Appointment created for '
            '${DateFormat('MMM d, h:mm a').format(startsAt.toLocal())}.',
          ),
        ),
      );
      widget.onAppointmentsTap?.call();
      return;
    }

    final title = await _askJobTitle(plan['title']?.toString());
    if (title == null || !mounted) return;

    final jobId = await _api.createJob(
      widget.businessId,
      customerId: customerId,
      vehicleId: vehicleId,
      title: title,
    );

    if (!mounted) return;
    await _openJob(jobId);
  }

  Future<void> _askBriskers() async {
    if (!_canManage || _aiBusy) return;

    final controller = TextEditingController();
    final command = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: BriskersColors.jobs),
                  SizedBox(width: 8),
                  Text(
                    'Ask Briskers',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Schedule Larry Carter tomorrow at 10 for an oil change',
                  border: OutlineInputBorder(),
                ),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(sheetContext, value.trim());
                  }
                },
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Try: "Create an estimate for Malcolm Ross"',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isNotEmpty) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(sheetContext, value);
                    }
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Run command'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    controller.dispose();

    if (command == null || command.isEmpty) return;

    setState(() {
      _aiBusy = true;
      _error = null;
    });

    try {
      final response = await _api.aiCommand(widget.businessId, command);
      final planRaw = response['plan'];
      if (planRaw is! Map) {
        throw Exception('Briskers AI returned an invalid action.');
      }
      await _executeAiPlan(Map<String, dynamic>.from(planRaw));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _openDocuments(String kind) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsScreen(
          businessId: widget.businessId,
          kind: kind,
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: <String>{'owner', 'manager', 'office'}.contains(widget.roleCode),
        ),
      ),
    );
    await _load();
  }



  Future<void> _openExpenses() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpensesScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
        ),
      ),
    );
    await _load();
  }

  Future<void> _toggleJobs() async {
    if (_activeJobsExpanded) {
      final restore = _jobsRestoreOffset;
      setState(() => _activeJobsExpanded = false);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (restore != null && _dashboardScrollController.hasClients) {
        final target = restore.clamp(
          0.0,
          _dashboardScrollController.position.maxScrollExtent,
        );
        await _dashboardScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    _jobsRestoreOffset = _dashboardScrollController.hasClients
        ? _dashboardScrollController.offset
        : 0;
    setState(() {
      _activeJobsExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contextForJobs = _jobsSectionKey.currentContext;
      if (contextForJobs != null) {
        Scrollable.ensureVisible(
          contextForJobs,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          alignment: 0,
        );
      }
    });
  }

  Future<void> _openJob(String jobId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: jobId,
          roleCode: widget.roleCode,
        ),
      ),
    );
    await _load();
    widget.onJobsChanged?.call();
  }


  Future<void> _changeJobStatus(
    Map<String, dynamic> job,
    String statusCode,
  ) async {
    if (!_canManage || statusCode == job['status']?.toString()) return;

    final id = job['id'].toString();
    setState(() => _busyJobId = id);

    try {
      await _api.changeJobStatus(
        widget.businessId,
        id,
        statusCode,
      );
      await _load();
      widget.onJobsChanged?.call();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  Widget _todayStatusControl(Map<String, dynamic> job) {
    final color = colorFromHex(job['status_color']?.toString());
    final label = jobStatusLabel(job['status']?.toString(), job['status_name']?.toString() ?? 'Status');
    final busy = _busyJobId == job['id']?.toString();

    final child = Container(
      constraints: const BoxConstraints(maxWidth: 155),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
            )
          else
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          if (_canManage && !busy) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, size: 15, color: color),
          ],
        ],
      ),
    );

    if (!_canManage || busy) return child;

    return PopupMenuButton<String>(
      tooltip: tr('changeStatus'),
      padding: EdgeInsets.zero,
      onSelected: (value) => _changeJobStatus(job, value),
      itemBuilder: (context) => _statuses.map((status) {
        final itemColor = colorFromHex(status['color_hex']?.toString());
        return PopupMenuItem<String>(
          value: status['code']?.toString(),
          child: Row(
            children: [
              Icon(
                jobStatusIcon(status['icon_key']?.toString()),
                color: itemColor,
              ),
              const SizedBox(width: 10),
              Text(status['name']?.toString() ?? ''),
            ],
          ),
        );
      }).toList(),
      child: child,
    );
  }

  Widget _activeJobCard(Map<String, dynamic> job) => JobCompactCard(
        job: job,
        statusControl: _todayStatusControl(job),
        onOpen: () => _openJob(job['id'].toString()),
        canOpen: _busyJobId != job['id']?.toString(),
      );


  @override
  Widget build(BuildContext context) {
    final _ = _askBriskers;

    final appointments = List<dynamic>.from(
      _data?['appointments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final activeJobs = List<dynamic>.from(
      _data?['active_jobs'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    Widget calendarHeader() {
      return Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showDashboardCalendar,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  color: BriskersColors.today,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        MaterialLocalizations.of(context).formatFullDate(_selectedDay),
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                if (!_sameDay(_selectedDay, DateTime.now()))
                  TextButton(
                    onPressed: () => _selectDashboardDay(DateTime.now()),
                    child: Text(tr('today')),
                  ),
                const Icon(Icons.keyboard_arrow_down),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              controller: _dashboardScrollController,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
              children: [
                _homeHeader(),
                const SizedBox(height: 6),
                _needsAttention(),
                const SizedBox(height: 10),
                calendarHeader(),
                const SizedBox(height: 8),
                _phaseTwoTiles(appointments.length, activeJobs.length),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  key: _jobsSectionKey,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _toggleJobs,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.build_outlined,
                              color: BriskersColors.jobs,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              tr('activeJobs'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: BriskersColors.jobs,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '${activeJobs.length}',
                              style: const TextStyle(
                                color: BriskersColors.jobs,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _activeJobsExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: BriskersColors.jobs,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_activeJobsExpanded) ...[
                  const SizedBox(height: 7),
                  if (activeJobs.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No active jobs right now.'),
                      ),
                    )
                  else
                    ...activeJobs.map(_activeJobCard),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

