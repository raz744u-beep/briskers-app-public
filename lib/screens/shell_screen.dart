import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/briskers_colors.dart';
import '../core/supabase_config.dart';
import '../core/connection_mode.dart';
import '../core/briskers_i18n.dart';
import '../core/employee_role_style.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/customer_notification_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/appointment_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/owner_job_retirement_service.dart';
import '../services/owner_job_deletion_service_v3.dart';
import '../services/local_job_deletion_v3.dart';
import '../local/local_database_provider.dart';
import '../services/local_appointment_repository.dart';
import '../services/local_customer_repository.dart';
import '../services/local_document_repository.dart';
import '../services/briskers_api.dart';
import '../services/local_payment_methods_cache.dart';
import '../services/local_standard_notes_service.dart';
import '../services/local_job_repository.dart';
import '../widgets/briskers_page_header.dart';
import '../widgets/auth_visibility_shield.dart';
import '../widgets/connection_header_toggle.dart';
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
    BriskersColors.schedule,
    BriskersColors.jobs,
    BriskersColors.invoices,
    BriskersColors.more,
  ];

  StreamSubscription<dynamic>? _scopeAuthSubscription;
  String? _scopeActor;
  bool _scopeLocked = false;
  int _index = 0;
  int _customersRefreshToken = 0;
  int _customerNavigationRequest = 0;
  List<String>? _focusedCustomerIds;
  CustomerNotificationService? _customerNotifications;
  StreamSubscription<String>? _customerReviewsSubscription;
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
    WidgetsBinding.instance.addObserver(this);
    _scopeActor = supabase.auth.currentUser?.id;
    _scopeAuthSubscription = supabase.auth.onAuthStateChange.listen((event) {
      if (!mounted || event.session?.user.id == _scopeActor) return;
      setState(() {
        _scopeLocked = true;
        _lazyPages.clear();
        _navCounts = const {};
        _homeJobsCount = 0;
        _homeEstimatesOpenCount = 0;
        _homeInvoicesOpenCount = 0;
      });
    });
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
    _index = widget.initialIndex.clamp(0, 5);
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
      final deletionV3 = OwnerJobDeletionServiceV3();
      await deletionV3.pullTombstones(businessId);
      if (widget.roleCode == 'owner' && mounted && _foreground &&
          widget.businessId == businessId &&
          !BriskersConnectionModeController.instance.forceOffline &&
          supabase.auth.currentUser?.id == actorId) {
        await deletionV3.flush(businessId);
      }
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
  void didUpdateWidget(covariant ShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleCode != widget.roleCode || oldWidget.businessId != widget.businessId) {
      _scopeLocked = true;
      _lazyPages.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { authVisibilityEpoch.value++; }
      });
      unawaited(_refreshKnownAccessChange());
    }
  }

  Future<void> _refreshKnownAccessChange() async {
    final business = widget.businessId;
    final role = widget.roleCode;
    try {
      await LocalJobDeletionV3.lockKnownRoleChange(localDatabase, business);
      if (BriskersConnectionModeController.instance.forceOffline) return;
      await OwnerJobDeletionServiceV3().pullTombstones(business);
      await LocalJobDeletionV3.assertVisibilityActor(localDatabase, business);
      if (mounted && widget.businessId == business && widget.roleCode == role &&
          supabase.auth.currentUser?.id == _scopeActor) {
        setState(() { _scopeLocked = false; });
      }
    } catch (_) {
      // Keep prior-scope screens hidden until verified access is available.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scopeAuthSubscription?.cancel();
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

  void _goTo(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    final request = ++_customerNavigationRequest;
    if (index == 1) {
      unawaited(_openCustomers(request));
      return;
    }
    setState(() {
      _index = index;
      if (index == 3) _jobsRefreshToken++;
      if (index == 0) _homeAttentionRefreshToken++;
    });
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
    if (_scopeLocked || supabase.auth.currentUser?.id != _scopeActor) {
      return const Scaffold(body: Center(child: Text('Your account access changed. Reopen this shop to refresh.')));
    }
    final activeColor = _sectionColors[_index];
    final isHome = _index == 0;
    final roleStyle = employeeRoleStyle(_roleLabel);
    Widget buildPage(int index) {
      if (index == 0) {
        return HomeScreen(
          onCustomersTap: () => _goTo(1),
          onAppointmentsTap: () => _goTo(2),
          onJobsTap: () => _goTo(3),
          onInvoicesTap: () => _goTo(4),
          onMoreTap: () => _goTo(5),
          estimatesNavigationBar: _shellNavigationBar(),
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
        );
      }
      if (index == 3) {
        // Deliver a fresh refreshToken even when Jobs is already selected.
        // Reusing the cached Widget bypasses JobsScreen.didUpdateWidget.
        return JobsScreen(
          businessId: widget.businessId,
          roleCode: widget.roleCode,
          refreshToken: _jobsRefreshToken,
          onJobsChanged: _refreshHomeJobsCount,
          jobDetailBottomNavigationBar: _shellNavigationBar(),
        );
      }
      return _lazyPages.putIfAbsent(index, () {
        switch (index) {
          case 2:
            return AppointmentsScreen(
              businessId: widget.businessId,
              roleCode: widget.roleCode,
            );
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

    final currentPage = buildPage(_index);

    return Scaffold(
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
