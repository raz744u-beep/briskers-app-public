import 'dart:async';

import 'package:flutter/material.dart';

import '../core/supabase_config.dart';
import '../services/briskers_api.dart';
import '../services/appointment_sync_service.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/offline_preinspection_service.dart';
import '../services/offline_work_findings_service.dart';
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
  final OfflinePreInspectionService _offlineInspection =
      OfflinePreInspectionService();
  final OfflineWorkFindingsService _offlineWorkFindings =
      OfflineWorkFindingsService();

  List<Map<String, dynamic>>? _businesses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final businesses = await _api.myBusinesses();
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
        if (businessId.isNotEmpty) {
          unawaited(_refreshLocalData(businessId));
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _businesses = const [];
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _refreshLocalData(String businessId) async {
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
    return ShellScreen(
      businessId: '${business['business_id'] ?? business['id']}',
      businessName: '${business['business_name'] ?? business['name'] ?? 'Briskers'}',
      roleCode: '${business['role_code'] ?? business['role'] ?? ''}',
    );
  }
}
