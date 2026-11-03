import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_config.dart';
import '../core/connection_mode.dart';
import '../core/auto_sync_retry_policy.dart';
import '../local/local_database_provider.dart';
import '../services/briskers_api.dart';
import '../services/appointment_sync_service.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/owner_job_retirement_service.dart';
import '../services/local_financial_cache.dart';
import '../services/linked_expense_sync_service.dart';
import '../services/offline_preinspection_service.dart';
import '../services/offline_job_admin_service.dart';
import '../services/offline_customer_vehicle_admin_service.dart';
import '../services/offline_customer_detail_write_service.dart';
import '../services/offline_financial_write_service.dart';
import '../services/offline_estimate_invoice_service.dart';
import '../services/offline_document_draft_service.dart';
import '../services/offline_document_edit_service.dart';
import '../services/offline_invoice_tax_service.dart';
import '../services/offline_invoice_mileage_service.dart';
import '../services/offline_invoice_payment_ledger.dart';
import '../services/local_tax_settings_cache.dart';
import '../services/local_invoice_status_styles_cache.dart';
import '../services/offline_work_findings_service.dart';
import 'kiosk/kiosk_checkin_screen.dart';
import 'shell_screen.dart';

class BusinessGate extends StatefulWidget {
  const BusinessGate({super.key});

  @override
  State<BusinessGate> createState() => _BusinessGateState();
}

class _BusinessGateState extends State<BusinessGate> with WidgetsBindingObserver {
  static const _api = BriskersApi();
  final JobSyncService _jobSync = JobSyncService();
  final AppointmentSyncService _appointmentSync =
      AppointmentSyncService();
  final CustomerVehicleSyncService _customerVehicleSync =
      CustomerVehicleSyncService();
  final CatalogSyncService _catalogSync = CatalogSyncService();
  final DocumentIndexSyncService _documentSync = DocumentIndexSyncService();
  final OfflinePreInspectionService _offlineInspection =
      OfflinePreInspectionService();
  final OfflineJobAdminService _offlineJobAdmin =
      OfflineJobAdminService();
  final OfflineCustomerVehicleAdminService _offlineCustomerVehicle =
      OfflineCustomerVehicleAdminService();
  final OfflineCustomerDetailWriteService _offlineCustomerDetail =
      OfflineCustomerDetailWriteService();
  final OfflineFinancialWriteService _offlineFinancial =
      OfflineFinancialWriteService();
  final OfflineEstimateInvoiceService _offlineEstimateInvoice =
      OfflineEstimateInvoiceService();
  final OfflineDocumentDraftService _offlineDocumentDraft =
      OfflineDocumentDraftService();
  final OfflineDocumentEditService _offlineDocumentEdit =
      OfflineDocumentEditService();
  final OfflineInvoiceTaxService _offlineInvoiceTax =
      OfflineInvoiceTaxService();
  final OfflineInvoicePaymentLedger _offlinePayments =
      OfflineInvoicePaymentLedger();
  final OfflineInvoiceMileageService _offlineInvoiceMileage =
      OfflineInvoiceMileageService();
  final LocalTaxSettingsCache _taxSettingsCache =
      LocalTaxSettingsCache();
  final LocalInvoiceStatusStylesCache _invoiceStatusStyles =
      LocalInvoiceStatusStylesCache();
  final LocalFinancialCache _localFinancial = LocalFinancialCache();
  final LinkedExpenseSyncService _linkedExpenses = LinkedExpenseSyncService();
  final OfflineWorkFindingsService _offlineWorkFindings =
      OfflineWorkFindingsService();

  List<Map<String, dynamic>>? _businesses;
  String? _error;
  Timer? _autoRetryTimer;
  bool _inForeground = true;
  bool _inspectingPendingRetry = false;
  int _stalledRetryAttempts = 0;
  DateTime? _nextRetryAt;
  final Map<String, Future<void>> _activeRefreshes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BriskersConnectionModeController.instance.addListener(
      _connectionModeChanged,
    );
    // Retry only while foregrounded. Backoff prevents repeated server floods.
    _autoRetryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_retryPendingAutoSync()),
    );
    _load();
  }

  void _connectionModeChanged() {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    _stalledRetryAttempts = 0;
    _nextRetryAt = null;
    final businesses = _businesses;
    if (businesses == null || businesses.isEmpty) return;
    final business = businesses.first;
    final businessId =
        '${business['business_id'] ?? business['id'] ?? ''}';
    final roleCode =
        '${business['role_code'] ?? business['role'] ?? ''}';
    if (businessId.isNotEmpty) {
      unawaited(
        _refreshLocalData(
          businessId,
          roleCode: roleCode,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (_inForeground && mounted) {
      // Return to the app is an opportunity to recover an interrupted upload.
      _nextRetryAt = null;
      unawaited(_retryPendingAutoSync());
    }
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    BriskersConnectionModeController.instance.removeListener(
      _connectionModeChanged,
    );
    super.dispose();
  }

  Future<int> _pendingUploadCount(String businessId) async {
    final row = await localDatabase.customSelect(
      "SELECT COUNT(*) AS n FROM sync_outbox "
      "WHERE business_id=? AND state IN ('pending','inflight')",
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('n');
  }

  Future<void> _retryPendingAutoSync() async {
    if (_inspectingPendingRetry || !mounted || !_inForeground ||
        BriskersConnectionModeController.instance.forceOffline) { return; }
    final businesses = _businesses;
    if (businesses == null || businesses.isEmpty) { return; }
    final business = businesses.first;
    final businessId =
        '${business['business_id'] ?? business['id'] ?? ''}';
    final roleCode =
        '${business['role_code'] ?? business['role'] ?? ''}';
    if (businessId.isEmpty || roleCode == 'kiosk') { return; }

    _inspectingPendingRetry = true;
    try {
      final before = await _pendingUploadCount(businessId);
      if (!mounted || !AutoSyncRetryPolicy.eligible(
        inForeground: _inForeground,
        forceOffline: BriskersConnectionModeController.instance.forceOffline,
        busy: false,
        pendingCount: before,
        now: DateTime.now(),
        notBefore: _nextRetryAt,
      )) { return; }
      await _refreshLocalData(businessId, roleCode: roleCode);
      if (!mounted) { return; }
      final after = await _pendingUploadCount(businessId);
      _stalledRetryAttempts =
          after < before ? 0 : _stalledRetryAttempts + 1;
      _nextRetryAt = DateTime.now().add(
        AutoSyncRetryPolicy.delayAfterStalledAttempt(
          _stalledRetryAttempts,
        ),
      );
    } catch (_) {
      // The original network failure stays with the durable outbox entry.
      _stalledRetryAttempts += 1;
      _nextRetryAt = DateTime.now().add(
        AutoSyncRetryPolicy.delayAfterStalledAttempt(
          _stalledRetryAttempts,
        ),
      );
    } finally {
      _inspectingPendingRetry = false;
    }
  }

  String? get _businessCacheKey {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;
    return 'briskers_business_context_$userId';
  }

  Future<Map<String, dynamic>?> _cachedBusiness() async {
    final key = _businessCacheKey;
    if (key == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedBusiness(
    Map<String, dynamic>? business,
  ) async {
    final key = _businessCacheKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();

    if (business == null) {
      await prefs.remove(key);
      return;
    }

    await prefs.setString(
      key,
      jsonEncode({
        'business_id':
            '${business['business_id'] ?? business['id'] ?? ''}',
        'business_name':
            '${business['business_name'] ?? business['name'] ?? 'Briskers'}',
        'role_code':
            '${business['role_code'] ?? business['role'] ?? ''}',
      }),
    );
  }

  Future<void> _load() async {
    Map<String, dynamic>? cached;
    try {
      cached = await _cachedBusiness();
      if (cached != null && mounted) {
        setState(() {
          _businesses = [cached!];
          _error = null;
        });

        final businessId =
            '${cached['business_id'] ?? cached['id'] ?? ''}';
        final roleCode =
            '${cached['role_code'] ?? cached['role'] ?? ''}';
        if (businessId.isNotEmpty) {
          unawaited(
            _refreshLocalData(
              businessId,
              roleCode: roleCode,
            ),
          );
        }
      }
    } catch (_) {
      cached = null;
    }

    try {
      final businesses = await _api.myBusinesses();
      if (businesses.isNotEmpty) {
        await _saveCachedBusiness(businesses.first);
      } else {
        await _saveCachedBusiness(null);
      }

      if (mounted) {
        setState(() {
          _businesses = businesses;
          _error = null;
        });
      }

      if (businesses.isNotEmpty) {
        final business = businesses.first;
        final businessId =
            '${business['business_id'] ?? business['id'] ?? ''}';
        final roleCode =
            '${business['role_code'] ?? business['role'] ?? ''}';
        if (businessId.isNotEmpty) {
          unawaited(
            _refreshLocalData(
              businessId,
              roleCode: roleCode,
            ),
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      if (cached == null) {
        setState(() {
          _businesses = const [];
          _error = error.toString();
        });
      }
    }
  }

  // Startup may load cached and remote business context concurrently.
  // Share the same upload pass rather than replaying it twice.
  Future<void> _refreshLocalData(
    String businessId, {
    required String roleCode,
  }) {
    final previous = _activeRefreshes[businessId];
    if (previous != null) return previous;
    final work = _runLocalRefresh(businessId, roleCode: roleCode);
    _activeRefreshes[businessId] = work;
    return work.whenComplete(() {
      if (identical(_activeRefreshes[businessId], work)) {
        _activeRefreshes.remove(businessId);
      }
    });
  }

  Future<void> _runLocalRefresh(
    String businessId, {
    required String roleCode,
  }) async {
    if (roleCode == 'kiosk') {
      // The dedicated kiosk screen owns appointment/check-in sync so there is
      // only one local outbox/pull loop on the public terminal.
      return;
    }
    // Reconcile durable deletions before any older queued edit can replay.
    // Individual replay paths also enforce the persistent retirement fences.
    if (BriskersConnectionModeController.instance.forceOffline) return;
    if (OwnerJobRetirementService.isTombstoneReaderRole(roleCode)) {
      final retirement = OwnerJobRetirementService();
      try {
        await retirement.pullTombstones(businessId);
      } catch (_) {
        // Unknown deletion state is not permission to replay stale work.
        return;
      }
      final actorId = supabase.auth.currentUser?.id;
      if (actorId == null) return;
      try {
        await retirement.flush(
          businessId,
          actorId: actorId,
          isOwner: roleCode == 'owner',
        );
      } catch (_) {
        // Pending deletion remains durable and blocks its related writes.
      }
    }
    try {
      await _offlineInspection.flush(businessId);
    } catch (_) {
      // Offline writes stay queued and retry the next time the app can sync.
    }

    try {
      await _offlineWorkFindings.flush(businessId);
    } catch (_) {
      // Work and Finding edits stay queued and retry on the next sync.
    }

    try {
      await _offlineJobAdmin.flush(businessId);
    } catch (_) {
      // Mechanic/time edits stay queued and retry on the next sync.
    }

    try {
      await _offlineCustomerVehicle.flush(businessId);
    } catch (_) {
      // Customer and vehicle edits stay queued and retry on reconnect.
    }

    try {
      await _offlineCustomerDetail.flush(businessId);
    } catch (_) {
      // Customer notes, findings and photos stay queued and retry.
    }

    try {
      await _offlineFinancial.flush(businessId);
    } catch (_) {
      // Expense and receipt changes stay queued and retry on reconnect.
    }

    try {
      await _offlineDocumentDraft.flush(businessId);
    } catch (_) {
      // New offline estimate drafts stay queued and retry on reconnect.
    }

    Map<String, dynamic>? taxSettings;
    try {
      taxSettings = await _taxSettingsCache.refresh(businessId);
    } catch (_) {
      taxSettings = await _taxSettingsCache.load(businessId);
    }

    if (taxSettings != null) {
      try {
        final rate = num.tryParse(
              taxSettings['sales_tax_rate']?.toString() ?? '',
            ) ??
            0;
        await _offlineDocumentEdit.repairPendingCatalogTaxes(
          businessId,
          rate,
        );
      } catch (_) {
        // Pending taxable document lines stay queued until repair can run.
      }
    }

    try {
      await _offlineDocumentEdit.flush(businessId);
    } catch (_) {
      // Cached document edits stay queued and retry on reconnect.
    }

    try {
      await _offlineInvoiceTax.flush(businessId);
    } catch (_) {
      // A tax edit with uncertain or stale server outcome remains fenced
      // in SQLite; never retry an ambiguous non-idempotent correction.
    }

    try {
      await _offlineInvoiceMileage.flush(businessId);
    } catch (_) {
      // Arrival and departure odometer saves remain in their separate,
      // business-scoped durable queues until the next trusted sync.
      // Never touch an invoice's historical odometer_in on replay.
    }

    try {
      await _offlinePayments.flush(businessId);
    } catch (_) {
      // Payments remain in the durable outbox until acknowledged by server.
    }

    try {
      await _offlinePayments.flushPendingServerEdits(businessId);
    } catch (_) {
      // Corrections to existing pending receipts also remain durable.
      // An unverified server receipt is never silently overwritten.
    }

    try {
      await _offlineEstimateInvoice.flush(businessId);
    } catch (_) {
      // Estimate-to-invoice merges stay queued and retry on reconnect.
    }

    try {
      await _appointmentSync.flushCreates(businessId);
      await _appointmentSync.flushEdits(businessId);
      await _appointmentSync.flushCancels(businessId);
      await _appointmentSync.flushDeletes(businessId);
      await _appointmentSync.flush(businessId);
    } catch (_) {
      // Queued check-ins stay local and retry on the next sync.
    }

    if (<String>{'owner', 'manager', 'office'}.contains(roleCode)) {
      try {
        final results = await Future.wait<dynamic>([
          _api.transactions(businessId, limit: 1000),
          _api.transactionOptions(businessId),
        ]);
        await _localFinancial.saveTransactions(
          businessId,
          List<Map<String, dynamic>>.from(results[0] as List),
        );
        await _localFinancial.saveOptions(
          businessId,
          Map<String, dynamic>.from(results[1] as Map),
        );
      } catch (_) {
        // Keep the last saved transaction snapshot for offline use.
      }
    }

    if (<String>{'owner', 'manager', 'office'}.contains(roleCode)) {
      // Do not hold up entry into the shop while downloading history.
      unawaited(_linkedExpenses.refreshBestEffort(businessId));
    }

    try {
      await _jobSync.pull(businessId);
    } catch (_) {
      // Existing online UI remains usable; the local pull retries later.
    }

    try {
      await _appointmentSync.pull(businessId);
    } catch (_) {
      // The schedule keeps the previous local appointment snapshot.
    }

    try {
      await _customerVehicleSync.pull(businessId);
    } catch (_) {
      // Customer/vehicle browsing keeps the previous local snapshot.
    }

    try {
      await _catalogSync.flush(businessId);
    } catch (_) {
      // Catalog edits stay queued and the last local item list remains usable.
    }

    try {
      await _catalogSync.pull(businessId);
    } catch (_) {
      // Keep the last saved catalog snapshot for offline estimates/invoices.
    }

    try {
      await _documentSync.pull(businessId);
    } catch (_) {
      // Estimate/invoice Home counts keep the previous local snapshot.
    }

    try {
      await _invoiceStatusStyles.refresh(businessId);
    } catch (_) {
      // Keep the last saved invoice status colors for offline use.
    }

  }

  @override
  Widget build(BuildContext context) {
    if (_businesses == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_businesses!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Briskers Setup')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined, size: 56),
              const SizedBox(height: 16),
              Text('Account ready', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'This login is not linked to the Briskers development business yet. Return to ChatGPT and the account can be attached as Owner.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => supabase.auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      );
    }

    final business = _businesses!.first;
    final businessId =
        '${business['business_id'] ?? business['id']}';
    final businessName =
        '${business['business_name'] ?? business['name'] ?? 'Briskers'}';
    final roleCode =
        '${business['role_code'] ?? business['role'] ?? ''}';

    if (roleCode == 'kiosk') {
      return KioskCheckInScreen(
        businessId: businessId,
        businessName: businessName,
      );
    }

    return ShellScreen(
      businessId: businessId,
      businessName: businessName,
      roleCode: roleCode,
    );
  }
}

