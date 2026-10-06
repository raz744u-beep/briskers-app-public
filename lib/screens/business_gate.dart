import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_config.dart';
import '../services/briskers_api.dart';
import '../services/appointment_sync_service.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/offline_preinspection_service.dart';
import '../services/offline_job_admin_service.dart';
import '../services/offline_work_findings_service.dart';
import 'kiosk/kiosk_checkin_screen.dart';
import 'shell_screen.dart';

class BusinessGate extends StatefulWidget {
  const BusinessGate({super.key});

  @override
  State<BusinessGate> createState() => _BusinessGateState();
}

class _BusinessGateState extends State<BusinessGate> {
  static const _api = BriskersApi();
  final JobSyncService _jobSync = JobSyncService();
  final AppointmentSyncService _appointmentSync =
      AppointmentSyncService();
  final CustomerVehicleSyncService _customerVehicleSync =
      CustomerVehicleSyncService();
  final DocumentIndexSyncService _documentSync = DocumentIndexSyncService();
  final OfflinePreInspectionService _offlineInspection =
      OfflinePreInspectionService();
  final OfflineJobAdminService _offlineJobAdmin =
  final LocalFinancialCache _localFinancial = LocalFinancialCache();
      OfflineJobAdminService();
  final OfflineWorkFindingsService _offlineWorkFindings =
      OfflineWorkFindingsService();

  List<Map<String, dynamic>>? _businesses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _refreshLocalData(
    String businessId, {
    required String roleCode,
  }) async {
    if (roleCode == 'kiosk') {
      // The dedicated kiosk screen owns appointment/check-in sync so there is
      // only one local outbox/pull loop on the public terminal.
      return;
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
      await _appointmentSync.flush(businessId);
    } catch (_) {
      // Queued check-ins stay local and retry on the next sync.
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
      await _documentSync.pull(businessId);
    } catch (_) {
      // Estimate/invoice Home counts keep the previous local snapshot.
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
