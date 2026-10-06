import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_i18n.dart';
import '../../local/local_database_provider.dart';
import '../../services/appointment_sync_service.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/document_index_sync_service.dart';
import '../../services/job_sync_service.dart';
import '../../services/kiosk_registration_service.dart';
import '../../services/offline_preinspection_service.dart';
import '../../services/offline_job_admin_service.dart';
import '../../services/offline_customer_vehicle_admin_service.dart';
import '../../services/offline_customer_detail_write_service.dart';
import '../../services/offline_financial_write_service.dart';
import '../../services/offline_document_draft_service.dart';
import '../../services/offline_estimate_invoice_service.dart';
import '../../services/offline_work_findings_service.dart';

class LocalSyncStatusScreen extends StatefulWidget {
  const LocalSyncStatusScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<LocalSyncStatusScreen> createState() =>
      _LocalSyncStatusScreenState();
}

class _LocalSyncStatusScreenState extends State<LocalSyncStatusScreen> {
  final JobSyncService _jobs = JobSyncService();
  final AppointmentSyncService _appointments = AppointmentSyncService();
  final CustomerVehicleSyncService _customers = CustomerVehicleSyncService();
  final CatalogSyncService _catalog = CatalogSyncService();
  final DocumentIndexSyncService _documents = DocumentIndexSyncService();
  final OfflinePreInspectionService _preInspections =
      OfflinePreInspectionService();
  final OfflineWorkFindingsService _workFindings =
      OfflineWorkFindingsService();
  final KioskRegistrationService _kiosk = KioskRegistrationService();
  final OfflineJobAdminService _jobAdmin = OfflineJobAdminService();
  final OfflineCustomerVehicleAdminService _customerVehicleAdmin =
      OfflineCustomerVehicleAdminService();
  final OfflineCustomerDetailWriteService _customerDetail =
      OfflineCustomerDetailWriteService();
  final OfflineFinancialWriteService _financial = OfflineFinancialWriteService();
  final OfflineDocumentDraftService _documentDrafts =
      OfflineDocumentDraftService();
  final OfflineEstimateInvoiceService _estimateInvoice =
      OfflineEstimateInvoiceService();

  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String? _syncMessage;

  Map<String, int> _counts = const {};
  List<Map<String, dynamic>> _syncStates = const [];
  List<Map<String, dynamic>> _outbox = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int> _count(String table, {String? where}) async {
    final rows = await localDatabase.customSelect(
      'SELECT COUNT(*) AS count FROM $table '
      'WHERE business_id = ?${where == null ? '' : ' AND $where'}',
      variables: [Variable<String>(widget.businessId)],
    ).get();
    return rows.isEmpty ? 0 : rows.first.read<int>('count');
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final counts = <String, int>{
        'customers': await _count('local_customers'),
        'vehicles': await _count('local_vehicles'),
        'appointments': await _count('local_appointments'),
        'jobs': await _count('local_jobs'),
        'catalog': await _count('local_catalog_items'),
        'documents': await _count('local_documents'),
        'findings': await _count('local_findings'),
        'inspections': await _count('local_pre_inspections'),
        'pending': await _count(
          'sync_outbox',
          where: "state = 'pending'",
        ),
        'conflicts': await _count(
          'sync_outbox',
          where: "state = 'conflict'",
        ),
      };

      final stateRows = await localDatabase.customSelect(
        '''
        SELECT scope, last_server_cursor, last_pull_at, last_push_at,
               last_error, bootstrapped
        FROM local_sync_states
        WHERE business_id = ?
        ORDER BY scope
        ''',
        variables: [Variable<String>(widget.businessId)],
      ).get();

      final outboxRows = await localDatabase.customSelect(
        '''
        SELECT entity_type, state, COUNT(*) AS count,
               MAX(last_error) AS last_error
        FROM sync_outbox
        WHERE business_id = ?
        GROUP BY entity_type, state
        ORDER BY state, entity_type
        ''',
        variables: [Variable<String>(widget.businessId)],
      ).get();

      if (!mounted) return;
      setState(() {
        _counts = counts;
        _syncStates = stateRows
            .map(
              (row) => <String, dynamic>{
                'scope': row.read<String>('scope'),
                'cursor': row.readNullable<int>('last_server_cursor'),
                'last_pull_at': row.data['last_pull_at'],
                'last_push_at': row.data['last_push_at'],
                'last_error': row.readNullable<String>('last_error'),
                'bootstrapped': row.read<int>('bootstrapped') == 1,
              },
            )
            .toList();
        _outbox = outboxRows
            .map(
              (row) => <String, dynamic>{
                'entity_type': row.read<String>('entity_type'),
                'state': row.read<String>('state'),
                'count': row.read<int>('count'),
                'last_error': row.readNullable<String>('last_error'),
              },
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  DateTime? _date(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        raw * 1000,
        isUtc: true,
      ).toLocal();
    }
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _dateLabel(Object? raw) {
    final value = _date(raw);
    if (value == null) return tr('never');
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMd(locale).add_jm().format(value);
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'jobs':
        return tr('jobs');
      case 'appointments':
        return tr('appointments');
      case 'customers_vehicles':
        return tr('customersVehicles');
      case 'catalog':
        return 'Items / Catalog';
      case 'documents':
        return 'Estimates / Invoices';
      default:
        return scope;
    }
  }

  String _operationLabel(String type) {
    switch (type) {
      case 'work_summary':
        return tr('workPerformed');
      case 'finding_create':
      case 'finding_update':
        return tr('vehicleFindings');
      case 'finding_photo':
        return tr('findingPhotos');
      case 'preinspection':
        return tr('preInspection');
      case 'preinspection_photo':
        return tr('inspectionPhotos');
      case 'appointment_checkin':
        return tr('appointmentCheckIn');
      case 'kiosk_walkin_registration':
        return tr('kioskWalkIn');
      default:
        return type.replaceAll('_', ' ');
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
      _error = null;
    });

    final failures = <String>[];

    Future<void> attempt(
      String label,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error) {
        failures.add('$label: $error');
      }
    }

    await attempt(
      'Job changes',
      () => _jobAdmin.flush(widget.businessId),
    );
    await attempt(
      'Customer / vehicle changes',
      () => _customerVehicleAdmin.flush(widget.businessId),
    );
    await attempt(
      'Customer notes / findings',
      () => _customerDetail.flush(widget.businessId),
    );
    await attempt(
      'Expenses / receipts',
      () => _financial.flush(widget.businessId),
    );
    await attempt(
      'Offline estimate drafts',
      () => _documentDrafts.flush(widget.businessId),
    );
    await attempt(
      'Estimate / invoice changes',
      () => _estimateInvoice.flush(widget.businessId),
    );
    await attempt(
      tr('preInspection'),
      () => _preInspections.flush(widget.businessId),
    );
    await attempt(
      tr('workPerformed'),
      () => _workFindings.flush(widget.businessId),
    );
    await attempt(tr('kioskWalkIn'), () async {
      await _kiosk.flush(widget.businessId);
    });
    await attempt(tr('appointments'), () async {
      await _appointments.flush(widget.businessId);
      await _appointments.pull(widget.businessId);
    });
    await attempt(
      tr('jobs'),
      () => _jobs.pull(widget.businessId),
    );
    await attempt(
      tr('customersVehicles'),
      () => _customers.pull(widget.businessId),
    );
    await attempt(
      'Items / Catalog',
      () => _catalog.pull(widget.businessId),
    );
    await attempt(
      'Estimates / Invoices',
      () => _documents.pull(widget.businessId),
    );

    await _load();
    if (!mounted) return;

    setState(() {
      _syncing = false;
      _syncMessage =
          failures.isEmpty ? tr('syncCompleted') : tr('syncPartial');
      if (failures.isNotEmpty) {
        _error = failures.join('\n');
      }
    });
  }

  Widget _countTile(
    IconData icon,
    String label,
    int count, {
    Color? color,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        trailing: Text(
          '$count',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offlineReady = (_counts['customers'] ?? 0) > 0 &&
        (_counts['jobs'] ?? 0) > 0 &&
        (_counts['catalog'] ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('localDatabaseSync')),
        actions: [
          IconButton(
            tooltip: tr('refresh'),
            onPressed: _loading || _syncing ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.storage_outlined),
                      title: Text(
                        tr('localDatabaseActive'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'SQLite / Drift • ${tr('schemaVersion')} '
                        '${localDatabase.schemaVersion}',
                      ),
                      trailing: Icon(
                        offlineReady
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: offlineReady ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('cachedOnDevice'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  _countTile(
                    Icons.people_outline,
                    tr('customers'),
                    _counts['customers'] ?? 0,
                  ),
                  _countTile(
                    Icons.directions_car_outlined,
                    tr('vehicles'),
                    _counts['vehicles'] ?? 0,
                  ),
                  _countTile(
                    Icons.calendar_month_outlined,
                    tr('appointments'),
                    _counts['appointments'] ?? 0,
                  ),
                  _countTile(
                    Icons.build_outlined,
                    tr('jobs'),
                    _counts['jobs'] ?? 0,
                  ),
                  _countTile(
                    Icons.inventory_2_outlined,
                    'Items / Catalog',
                    _counts['catalog'] ?? 0,
                  ),
                  _countTile(
                    Icons.description_outlined,
                    'Estimates / Invoices',
                    _counts['documents'] ?? 0,
                  ),
                  _countTile(
                    Icons.car_repair_outlined,
                    tr('vehicleFindings'),
                    _counts['findings'] ?? 0,
                  ),
                  _countTile(
                    Icons.search,
                    tr('preInspections'),
                    _counts['inspections'] ?? 0,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr('offlineQueue'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  _countTile(
                    Icons.cloud_upload_outlined,
                    tr('pendingUpload'),
                    _counts['pending'] ?? 0,
                    color: Colors.orange,
                  ),
                  _countTile(
                    Icons.warning_amber_rounded,
                    tr('syncConflicts'),
                    _counts['conflicts'] ?? 0,
                    color: Colors.red,
                  ),
                  if (_outbox.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ..._outbox.map(
                      (row) => Card(
                        child: ListTile(
                          dense: true,
                          title: Text(
                            _operationLabel(
                              row['entity_type']?.toString() ?? '',
                            ),
                          ),
                          subtitle: (row['last_error']?.toString() ?? '').isEmpty
                              ? Text(row['state']?.toString() ?? '')
                              : Text(
                                  row['last_error'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: Text(
                            '${row['count'] ?? 0}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    tr('syncHistory'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  if (_syncStates.isEmpty)
                    Card(
                      child: ListTile(
                        title: Text(tr('notSyncedYet')),
                      ),
                    )
                  else
                    ..._syncStates.map(
                      (row) => Card(
                        child: ListTile(
                          title: Text(
                            _scopeLabel(row['scope']?.toString() ?? ''),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${tr('lastPull')}: '
                            '${_dateLabel(row['last_pull_at'])}\n'
                            '${tr('lastPush')}: '
                            '${_dateLabel(row['last_push_at'])}',
                          ),
                          trailing: Icon(
                            row['bootstrapped'] == true
                                ? Icons.check_circle_outline
                                : Icons.hourglass_empty,
                            color: row['bootstrapped'] == true
                                ? Colors.green
                                : Colors.orange,
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('offlineTest'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            offlineReady
                                ? tr('offlineTestReady')
                                : tr('offlineTestNeedsCache'),
                          ),
                          const SizedBox(height: 8),
                          Text('1. ${tr('offlineStep1')}'),
                          Text('2. ${tr('offlineStep2')}'),
                          Text('3. ${tr('offlineStep3')}'),
                          Text('4. ${tr('offlineStep4')}'),
                        ],
                      ),
                    ),
                  ),
                  if ((_syncMessage ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _syncMessage!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if ((_error ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _syncNow,
                    icon: _syncing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      _syncing ? tr('syncing') : tr('syncNow'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
