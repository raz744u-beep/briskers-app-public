import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/briskers_colors.dart';
import '../core/supabase_config.dart';
import '../core/connection_mode.dart';
import '../core/briskers_i18n.dart';
import '../core/employee_role_style.dart';
import '../core/navigation_content_timing.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/customer_notification_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/appointment_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/owner_job_retirement_service.dart';
import '../services/local_appointment_repository.dart';
import '../services/local_customer_repository.dart';
import '../services/local_document_repository.dart';
import '../services/briskers_api.dart';
import '../services/local_payment_methods_cache.dart';
import '../services/local_standard_notes_service.dart';
import '../services/local_job_repository.dart';
import '../widgets/briskers_page_header.dart';
import '../widgets/connection_header_toggle.dart';
import '../widgets/briskers_module_dock.dart';
import '../widgets/stale_keyboard_inset_guard.dart';
import '../widgets/retained_module_stack.dart';
import 'expenses_screen.dart';
import 'appointments_screen.dart';
import 'customers/customers_screen.dart';
import 'customers/new_customers_screen.dart';
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
    this.initialIndex = 0,
  });

  final String businessId;
  final String businessName;
  final String roleCode;
  final int initialIndex;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with WidgetsBindingObserver {
  static const _api = BriskersApi();
  bool _preparingOfflineChoices = false;
  bool _retirementSyncing = false;
  bool _foreground = true;
  Timer? _retirementRetry;
  StreamSubscription<String>? _retirementChanges;
  static const _sectionColors = [
    BriskersColors.today,
    BriskersColors.customers,
    BriskersColors.jobs,
    BriskersColors.estimates,
    BriskersColors.invoices,
    BriskersColors.schedule,
    BriskersColors.expenses,
    BriskersColors.more,
  ];

  int _index = 0;
  int _customersRefreshToken = 0;
  int _customerNavigationRequest = 0;
  List<String>? _focusedCustomerIds;
  CustomerNotificationService? _customerNotifications;
  StreamSubscription<String>? _customerReviewsSubscription;
  int _jobsRefreshToken = 0;
  int _estimatesDockReset = 0;
  int _invoicesDockReset = 0;
  int _scheduleDockReset = 0;
  int _expensesDockReset = 0;
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
    WidgetsBinding.instance.addObserver(this);
    _retirementRetry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) unawaited(_syncRetirements());
    });
    _retirementChanges = OwnerJobRetirementService.statusEvents.listen((businessId) {
      if (mounted && businessId == widget.businessId) {
        _refreshHomeJobsCount();
        _refreshHomeEstimatesCount();
        _refreshHomeInvoicesCount();
      }
    });
    unawaited(_syncRetirements());
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      _customerNotifications = CustomerNotificationService(
        businessId: widget.businessId, userId: userId);
    }
    _customerReviewsSubscription = CustomerNotificationService.changes.listen((businessId) {
      if (businessId == widget.businessId) _refreshHomeCustomersCount();
    });
    _businessName = widget.businessName;
    _index = widget.initialIndex.clamp(0, 7);
    BriskersConnectionModeController.instance.addListener(_connectionChanged);
    unawaited(_prepareOfflineChoices());
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refreshHomeCustomersCount();
      unawaited(_syncRetirements());
    }
  }

  void _connectionChanged() {
    if (!mounted) return;
    unawaited(_prepareOfflineChoices());
    unawaited(_syncRetirements());
    _refreshHomeCustomersCount();
    setState(() {
      _lazyPages.clear();
      _customersRefreshToken++;
      _jobsRefreshToken++;
    });
  }

  Future<void> _syncRetirements() async {
    if (!OwnerJobRetirementService.isTombstoneReaderRole(widget.roleCode) ||
        !mounted || !_foreground || _retirementSyncing ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }
    final businessId = widget.businessId;
    final actorId = supabase.auth.currentUser?.id;
    if (actorId == null) return;
    _retirementSyncing = true;
    try {
      final service = OwnerJobRetirementService();
      await service.pullTombstones(businessId);
      if (!mounted || !_foreground || widget.businessId != businessId ||
          BriskersConnectionModeController.instance.forceOffline ||
          supabase.auth.currentUser?.id != actorId) {
        return;
      }
      await service.flush(businessId,
        actorId: actorId, isOwner: widget.roleCode == 'owner');
    } catch (_) {
      // The persisted sync diagnostics explain any block; uncertainty never
      // clears a fence. Foreground retries and app restart resume the request.
    } finally {
      _retirementSyncing = false;
    }
  }

  /// Preload the shop's actual payment method IDs for future offline use.
  /// Never invent method IDs or block app navigation on connectivity.
  Future<void> _prepareOfflineChoices() async {
    if (_preparingOfflineChoices ||
        BriskersConnectionModeController.instance.forceOffline) {
      return;
    }
    _preparingOfflineChoices = true;
    try {
      final options = await _api.paymentOptions(widget.businessId);
      final methods = List<dynamic>.from(options['methods'] ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      if (methods.isNotEmpty) {
        await const LocalPaymentMethodsCache().save(widget.businessId, methods);
      }
    } catch (_) {
      // An unavailable network must not prevent local app use.
    }
    try {
      // Warranty company choice should be available in the same form offline.
      // IDs come from actual shop configuration, never fabricated defaults.
      final companies = await _api.warrantyCompanies(widget.businessId);
      if (companies.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'briskers_warranty_companies_${widget.businessId}',
          jsonEncode(companies),
        );
      }
    } catch (_) {
      // Retain the last known shop-scoped warranty company list.
    }
    try {
      await LocalStandardNotesService().available(
        widget.businessId, offline: false);
    } catch (_) {
      // Unsynced templates remain saved and retry when online again.
    } finally {
      _preparingOfflineChoices = false;
    }
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
      final ids = await _customerNotifications?.unreadCustomerIds() ?? const <String>[];
      final count = ids.length;
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
    WidgetsBinding.instance.removeObserver(this);
    _retirementRetry?.cancel();
    _retirementChanges?.cancel();
    _customerReviewsSubscription?.cancel();
    BriskersConnectionModeController.instance.removeListener(_connectionChanged);
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

  Future<void> _openCustomers(int request) async {
    List<String> ids;
    try {
      ids = await _customerNotifications?.unreadCustomerIds() ?? const <String>[];
    } catch (_) {
      // A read failure must not consume the inbox or pretend the badge is zero.
      if (!mounted || request != _customerNavigationRequest) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('newCustomersLoadError'))));
      return;
    }
    if (!mounted || request != _customerNavigationRequest) return;
    setState(() {
      _focusedCustomerIds = ids.isEmpty ? null : List.unmodifiable(ids);
      _index = 1;
      _customersRefreshToken++;
    });
    _applyHomeCustomersCount(ids.length);
  }

  Future<void> _reviewCustomer(String id) async {
    try {
      await _customerNotifications?.markReviewed([id]);
    } catch (_) {
      // Retain the badge on storage failure; never optimistically clear it.
    }
  }

  void _viewAllCustomers() {
    _customerNavigationRequest++;
    setState(() {
      _focusedCustomerIds = null;
      _index = 1;
      _customersRefreshToken++;
    });
  }

  void _selectCustomersFromDock() {
    // The Customers badge represents unread customer arrivals, not the
    // total customer count. A normal-sized tab tap must show those people,
    // not require a precision tap on the tiny badge label.
    // Do not consume events here; only explicit review marks them read.
    if (_homeCustomersNewCount > 0 && _customerNotifications != null) {
      final request = ++_customerNavigationRequest;
      unawaited(_openCustomers(request));
      return;
    }
    _goTo(1);
  }

  void _goTo(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    final timedModule = switch (index) {
      3 => 'estimates',
      4 => 'invoices',
      5 => 'appointments',
      _ => null,
    };
    if (timedModule != null) {
      NavigationContentTiming.start(timedModule);
    } else {
      NavigationContentTiming.cancel();
    }
    // General navigation (Home shortcuts and View all) stays unfiltered;
    // the dock Customers destination routes through _selectCustomersFromDock.
    ++_customerNavigationRequest;
    setState(() {
      _index = index;
      if (index == 1) _focusedCustomerIds = null;
      if (index == 2) _jobsRefreshToken++;
      if (index == 3) _estimatesDockReset++;
      if (index == 4) _invoicesDockReset++;
      if (index == 5) _scheduleDockReset++;
      if (index == 6) _expensesDockReset++;
      if (index == 0) _homeAttentionRefreshToken++;
    });
    if (index == 4) _refreshHomeInvoicesCount();
  }

  String get _roleLabel => roleLabel(widget.roleCode);

  Widget _shellNavigationBar({bool nested = false}) => BriskersModuleDock(
    selectedIndex: _index,
    destinations: [
      const BriskersDockDestination(label: 'Home', icon: Icons.home_outlined, color: BriskersColors.today),
      BriskersDockDestination(label: 'Customers', icon: Icons.people_outline, color: BriskersColors.customers, count: _homeCustomersNewCount),
      BriskersDockDestination(label: 'Jobs', icon: Icons.build_outlined, color: BriskersColors.jobs, count: _homeJobsCount),
      BriskersDockDestination(label: 'Estimates', icon: Icons.description_outlined, color: BriskersColors.estimates, count: _homeEstimatesOpenCount),
      BriskersDockDestination(label: 'Invoices', icon: Icons.receipt_long_outlined, color: BriskersColors.invoices, count: _homeInvoicesOpenCount),
      BriskersDockDestination(label: 'Schedule', icon: Icons.calendar_month_outlined, color: BriskersColors.schedule, count: _homeAppointmentsCount),
      const BriskersDockDestination(label: 'Expenses', icon: Icons.account_balance_wallet_outlined, color: BriskersColors.expenses),
      const BriskersDockDestination(label: 'More', icon: Icons.more_horiz, color: BriskersColors.more),
    ],
    onBadgeSelected: (index) {
      if (index != 1) {
        _goTo(index);
        return;
      }
      if (nested) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      // Only the Customers badge opens the new-customer review queue.
      final request = ++_customerNavigationRequest;
      unawaited(_openCustomers(request));
    },
    onSelected: (index) {
      if (nested) {
        // A shared dock may be inside a sheet over a detail page.
        // Explicit module navigation dismisses the nested routes first.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      if (index == 1) {
        _selectCustomersFromDock();
      } else {
        _goTo(index);
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final activeColor = _sectionColors[_index];
    final isHome = _index == 0;
    final roleStyle = employeeRoleStyle(_roleLabel);
    Widget buildPage(int index) {
      if (index == 0) {
        return HomeScreen(
          onCustomersTap: () => _goTo(1),
          onAppointmentsTap: () => _goTo(5),
          onJobsTap: () => _goTo(2),
          onInvoicesTap: () => _goTo(4),
          onMoreTap: () => _goTo(7),
          estimatesNavigationBar: _shellNavigationBar(nested: true),
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
      if (index == 1) {
        final focused = _focusedCustomerIds;
        if (focused != null && _customerNotifications != null) {
          return NewCustomersScreen(
            key: ValueKey('customer-review-$_customersRefreshToken'),
            businessId: widget.businessId,
            roleCode: widget.roleCode,
            customerIds: focused,
            notifications: _customerNotifications!,
            onViewAll: _viewAllCustomers,
          );
        }
        return CustomersScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
          refreshToken: _customersRefreshToken,
          onCustomerReviewed: (id) => unawaited(_reviewCustomer(id)),
          detailBottomNavigationBar: _shellNavigationBar(nested: true),
        );
      }
      if (index == 2) {
        // Deliver a fresh refreshToken even when Jobs is already selected.
        // Reusing the cached Widget bypasses JobsScreen.didUpdateWidget.
        return JobsScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
          refreshToken: _jobsRefreshToken,
          defaultToOpen: true,
          onJobsChanged: _refreshHomeJobsCount,
          jobDetailBottomNavigationBar: _shellNavigationBar(nested: true),
        );
      }
      if (index == 3 || index == 4) {
        return DocumentsScreen(
          roleCode: widget.roleCode,
          businessId: widget.businessId,
          kind: index == 3 ? 'estimate' : 'invoice',
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: index == 4 &&
              <String>{'owner', 'manager', 'office'}.contains(widget.roleCode),
          showAppBar: false,
          sharedBottomNavigationBar:
              index == 3 ? _shellNavigationBar(nested: true) : null,
          // The Shell owns the list dock. Detail routes are pushed above
          // this Shell and need their own navigation dock to leave invoices.
          detailBottomNavigationBar: _shellNavigationBar(nested: true),
          dockDefaultsToOpen: true,
          dockResetToken: index == 3 ? _estimatesDockReset : _invoicesDockReset,
        );
      }
      if (index == 5) {
        return AppointmentsScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
          dockResetToken: _scheduleDockReset,
        );
      }
      if (index == 6) {
        return ExpensesScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
          showAppBar: false,
          dockResetToken: _expensesDockReset,
        );
      }
      return _lazyPages.putIfAbsent(index, () {
        switch (index) {
          case 5:
            return AppointmentsScreen(
              businessId: widget.businessId,
              roleCode: widget.roleCode,
            );
          case 3:
            return DocumentsScreen(
              roleCode: widget.roleCode,
              businessId: widget.businessId,
              kind: 'estimate',
              isOwner: widget.roleCode == 'owner',
              canManageExpenses: false,
              showAppBar: false,
              sharedBottomNavigationBar: _shellNavigationBar(nested: true),
            );
          case 6:
            return ExpensesScreen(businessId: widget.businessId, roleCode: widget.roleCode, showAppBar: false);
          case 4:
            return DocumentsScreen(
              roleCode: widget.roleCode,
              businessId: widget.businessId,
              kind: 'invoice',
              isOwner: widget.roleCode == 'owner',
              canManageExpenses: <String>{'owner', 'manager', 'office'}.contains(widget.roleCode),
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

    return StaleKeyboardInsetGuard(
      child: Scaffold(
      appBar: isHome ? null : AppBar(
        backgroundColor: activeColor.withValues(alpha: 0.08),
        titleSpacing: 10,
        toolbarHeight: 78,
        title: Row(
          children: [
            const BriskersLogo(height: 44, maxWidth: 148),
            const Spacer(),
            ConnectionHeaderToggle(businessId: widget.businessId),
          ],
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
      body: RetainedModuleStack(
        key: ValueKey('${widget.businessId}:${widget.roleCode}'),
        index: _index,
        itemCount: _sectionColors.length,
        itemBuilder: (_, index) => buildPage(index),
      ),
      bottomNavigationBar: _shellNavigationBar(),
      ),
    );
  }
}

