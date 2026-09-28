import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import '../widgets/job_compact_card.dart';
import 'customers/customer_detail_screen.dart';
import 'documents_screen.dart';
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
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;
  final VoidCallback? onCustomersTap;
  final VoidCallback? onAppointmentsTap;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _statuses = const [];
  String? _error;
  String? _checkingInId;
  String? _busyJobId;
  bool _aiBusy = false;
  bool _appointmentsExpanded = false;
  bool _activeJobsExpanded = false;
  int _estimateCount = 0;
  int _invoiceCount = 0;
  DateTime _selectedDay = DateTime.now();
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Set<String> _eventDays = <String>{};

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
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
        _estimateCount = (results[3] as List).length;
        _invoiceCount = (results[4] as List).length;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
                          DateFormat('MMMM yyyy').format(month),
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
                        child: const Text('Today'),
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
                title: Text(customer['display_name']?.toString() ?? ''),
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
        ),
      ),
    );
    await _load();
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
  }


  Future<void> _checkIn(Map<String, dynamic> appointment) async {
    if (!_canManage) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Check in vehicle?'),
        content: Text(
          'Check in ${appointment['customer'] ?? 'this customer'} and create the Job?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Check In'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final appointmentId = appointment['id'].toString();
    setState(() => _checkingInId = appointmentId);

    try {
      final jobId = await _api.checkInAppointment(
        widget.businessId,
        appointmentId,
      );
      await _load();
      if (mounted) await _openJob(jobId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checkingInId = null);
    }
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
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  Widget _todayStatusControl(Map<String, dynamic> job) {
    final color = colorFromHex(job['status_color']?.toString());
    final label = job['status_name']?.toString() ?? 'Status';
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
      tooltip: 'Change status',
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
    if (_data == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final appointments = List<dynamic>.from(
      _data?['appointments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final activeJobs = List<dynamic>.from(
      _data?['active_jobs'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _showDashboardCalendar,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 5,
                ),
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
                            DateFormat('EEEE, MMMM d').format(_selectedDay),
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
                        child: const Text('Today'),
                      ),
                    const Icon(Icons.keyboard_arrow_down),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_canManage) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: BriskersColors.jobs.withValues(alpha: 0.07),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _aiBusy ? null : _askBriskers,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            BriskersColors.jobs.withValues(alpha: 0.15),
                        child: _aiBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: BriskersColors.jobs,
                                ),
                              )
                            : const Icon(
                                Icons.auto_awesome,
                                color: BriskersColors.jobs,
                              ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ask Briskers',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Create invoices, estimates, appointments or jobs',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ],
          _DocumentShortcutRow(
            label: 'Estimates',
            count: _estimateCount,
            icon: Icons.request_quote_outlined,
            color: BriskersColors.estimates,
            onTap: () => _openDocuments('estimate'),
          ),
          const SizedBox(height: 8),
          _DocumentShortcutRow(
            label: 'Invoices',
            count: _invoiceCount,
            icon: Icons.receipt_long_outlined,
            color: BriskersColors.invoices,
            onTap: () => _openDocuments('invoice'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(
                () => _appointmentsExpanded = !_appointmentsExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: BriskersColors.appointments,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _sameDay(_selectedDay, DateTime.now())
                          ? 'Appointments'
                          : DateFormat('MMM d Appointments').format(_selectedDay),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: BriskersColors.appointments,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${appointments.length}',
                      style: const TextStyle(
                        color: BriskersColors.appointments,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _appointmentsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: BriskersColors.appointments,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_appointmentsExpanded) ...[
            const SizedBox(height: 7),
            if (appointments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No confirmed appointments for this day.'),
                ),
              )
            else
              ...appointments.map((item) {
                final start =
                    DateTime.tryParse(item['starts_at']?.toString() ?? '');
                final time = start == null
                    ? ''
                    : DateFormat('h:mm a').format(start.toLocal());
                final mechanic = item['mechanic']?.toString() ?? '';
                final checking = _checkingInId == item['id']?.toString();

                return Card(
                  margin: const EdgeInsets.only(bottom: 7),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 19,
                      backgroundColor:
                          BriskersColors.appointments.withValues(alpha: 0.14),
                      child: const Icon(
                        Icons.event_outlined,
                        color: BriskersColors.appointments,
                        size: 21,
                      ),
                    ),
                    title: Text(
                      <String>[
                        if (time.isNotEmpty) time,
                        item['title']?.toString() ?? 'Appointment',
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      <String>[
                        item['customer']?.toString() ?? '',
                        if ((item['vehicle']?.toString() ?? '').isNotEmpty)
                          item['vehicle'].toString(),
                        if (mechanic.isNotEmpty) 'Planned: $mechanic',
                      ].where((value) => value.isNotEmpty).join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _canManage
                        ? checking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                tooltip: 'Check in / Create job',
                                onPressed: () => _checkIn(item),
                                icon: const Icon(
                                  Icons.login_outlined,
                                  color: BriskersColors.appointments,
                                ),
                              )
                        : null,
                  ),
                );
              }),
          ],
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(
                () => _activeJobsExpanded = !_activeJobsExpanded,
              ),
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
                      'Active Jobs',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _DocumentShortcutRow extends StatelessWidget {
  const _DocumentShortcutRow({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

