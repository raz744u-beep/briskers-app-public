import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/briskers_colors.dart';
import '../../widgets/job_compact_card.dart';
import '../../core/connection_mode.dart';
import '../../core/formatters.dart';
import '../../core/briskers_i18n.dart';
import '../../core/document_presentation.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/customer_document_summary_service.dart';
import '../../local/local_database_provider.dart';
import '../../services/local_customer_repository.dart';
import '../../services/job_summary_visibility.dart';
import '../../services/offline_customer_vehicle_admin_service.dart';
import '../appointments/appointment_create_screen.dart';
import '../jobs/job_create_screen.dart';
import '../jobs/job_document_screen.dart';
import '../jobs/job_detail_screen.dart';
import '../appointments/appointment_manage_screen.dart';
import '../jobs/blank_invoice_setup_screen.dart';
import 'customer_quick_actions.dart';
import 'customer_problem_flag_card.dart';
import 'customer_account_section.dart';
import 'customer_appointments_section.dart';
import 'customer_notes_section.dart';
import 'customer_service_history_section.dart';
import 'customer_vehicles_section.dart';
import 'customer_vehicle_findings_section.dart';
import 'edit_customer_screen.dart';
import 'new_vehicle_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.roleCode,
    this.onReviewed,
    this.sharedBottomNavigationBar,
  });

  final String businessId;
  final String customerId;
  final String roleCode;
  final VoidCallback? onReviewed;
  final Widget? sharedBottomNavigationBar;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  static const _api = BriskersApi();
  static const _sectionCache = CustomerDetailCache();
  final CustomerVehicleSyncService _sync =
      CustomerVehicleSyncService();
  final LocalCustomerRepository _localCustomers =
      LocalCustomerRepository();
  final OfflineCustomerVehicleAdminService _offlineAdmin =
      OfflineCustomerVehicleAdminService();

  late JobSummaryVisibility _jobVisibility;
  Map<String, dynamic>? _data;
  String? _error;
  bool _onlineReady = false;
  bool _showingLocal = false;

  bool get _canEditLocal => _data != null && _canManageQuickActions;
  bool get _canManageQuickActions => canManageCustomerActions(widget.roleCode);
  final GlobalKey _notesSectionKey = GlobalKey();
  bool _expandQuickNotes = false;
  int _customerTab = 0; // Overview, Info, Vehicles, Notes.

  Future<Map<String, dynamic>> _loadOfflineSections() async {
    final visibility = _jobVisibility;
    final generation = visibility.epoch;
    Future<List<Map<String, dynamic>>> listSection(String key) async {
      final raw = await _sectionCache.load(
        widget.businessId,
        widget.customerId,
        key,
      );
      return raw is List
          ? raw
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
    }

    final appointments = await visibility.filter(
        await listSection('appointments'), jobIdKey: 'job_id');

    final historyRaw = await _sectionCache.load(
      widget.businessId,
      widget.customerId,
      'service_history',
    );
    final history = historyRaw is Map
        ? Map<String, dynamic>.from(historyRaw)
        : <String, dynamic>{};

    history['jobs'] = await visibility.filter(
      List<dynamic>.from(history['jobs'] ?? const [])
          .whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
      cached: true,
    );
    if (!visibility.isCurrent(generation)) return const {};
    return <String, dynamic>{
      'appointments': appointments,
      'history': history,
    };
  }



  Future<List<Map<String, dynamic>>> _activeCustomerItems() async {
    final visibility = _jobVisibility;
    final generation = visibility.epoch;
    final vars = <Variable<Object>>[
      Variable<String>(widget.businessId),
      Variable<String>(widget.customerId),
    ];
    final rows = <Map<String, dynamic>>[];
    final appointments = await localDatabase.customSelect(
      "SELECT id,title,status,job_id FROM local_appointments WHERE business_id=? AND customer_id=? "
      "AND lower(status) NOT IN ('cancelled','canceled','no_show','checked_in','completed')",
      variables: vars).get();
    for (final a in appointments) {
      rows.add({'type':'Appointment','id':a.read<String>('id'),
        'job_id':a.readNullable<String>('job_id'),
        'title':a.read<String>('title'),
        'status':a.read<String>('status')});
    }
    final jobs = await localDatabase.customSelect(
      "SELECT * FROM local_jobs WHERE business_id=? AND customer_id=? "
      "",
      variables: vars).get();
    for (final j in jobs) {
      final rawStatus = j.read<String>('status');
      final formattedStatus = rawStatus.replaceAll('_', ' ');
      final jobStatus = formattedStatus.isEmpty ? 'Open' :
          formattedStatus[0].toUpperCase() + formattedStatus.substring(1);
      rows.add({'type':'Job','id':j.read<String>('id'),
        'job_id':j.read<String>('id'),
        'title':j.read<String>('title'),
        'number':j.readNullable<String>('job_number') ?? 'Pending sync',
        'status':jobStatus,
        'job_snapshot': <String, dynamic>{
          ...j.data,
          'customer_name': _data?['customer']?['name'] ?? '',
          'vehicle': j.data['vehicle_label'],
        } });
    }
    final docs = await CustomerDocumentSummaryService().forCustomer(
      widget.businessId, widget.customerId, includeClosed: true);
    for (final document in docs) {
      final presentation = DocumentPresentation(document);
      rows.add({
        'type': document['kind'],
        'id': document['id'],
        'job_id': document['job_id'],
        'vehicle': document['vehicle'] ?? document['vehicle_label'],
        'document_date': document['document_date'],
        'server_updated_at': document['server_updated_at'] ?? document['updated_at'],
        'title': document['title'] ?? document['job_title'] ??
            (presentation.isInvoice ? tr('invoice') : tr('estimate')),
        'status': presentation.statusLabel,
        'number': document['document_number'] ?? tr('pendingSync'),
        'total': num.tryParse(document['total_amount']?.toString() ?? ''),
        'balance_due_cents': presentation.balanceDueCents,
        'pending_cents': presentation.paymentDetailsKnown ? presentation.pendingCents : null,
        'payment_reconciliation_required': presentation.requiresReconciliation,
      });
    }
    final visits = await localDatabase.customSelect(
      'SELECT v.id,v.job_id,v.reason,j.job_number FROM local_job_visits v '
      'JOIN local_jobs j ON j.id=v.job_id AND j.business_id=v.business_id '
      'WHERE v.business_id=? AND j.customer_id=?',
      variables: vars).get();
    for (final visit in visits) {
      rows.add({'type': 'Visit', 'id': visit.read<String>('id'),
        'job_id': visit.read<String>('job_id'),
        'number': visit.readNullable<String>('job_number') ?? '',
        'title': visit.readNullable<String>('reason') ?? 'Shop visit'});
    }
    final visibleRows = await visibility.filter(rows, jobIdKey: 'job_id');
    return visibility.isCurrent(generation) ? visibleRows : [];
  }

  Future<void> _openOverviewRecord(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final jobId = item['job_id']?.toString() ?? '';
    if (id.isEmpty || !mounted) return;
    final type = item['type']?.toString() ?? '';
    if (type == 'Job' || type == 'Visit') {
      if (type == 'Visit' && jobId.isEmpty) return;
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: type == 'Visit' ? jobId : id,
          roleCode: widget.roleCode)));
    } else if (type == 'Appointment') {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => AppointmentManageScreen(
          businessId: widget.businessId,
          isOwner: widget.roleCode == 'owner',
          appointment: {'id': id, 'customer_id': widget.customerId,
            'title': item['title'], 'status': item['status']})));
    } else if (type == 'invoice' || type == 'estimate') {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: id,
          isOwner: widget.roleCode == 'owner',
          roleCode: widget.roleCode)));
    }
  }

  Future<void> _showOverviewList(String title, List<Map<String, dynamic>> records) async {
    Color moduleColor(String type) {
      switch (type) {
        case 'Job':
        case 'Visit':
          return BriskersColors.jobs;
        case 'invoice':
          return BriskersColors.invoices;
        case 'estimate':
          return BriskersColors.estimates;
        case 'Appointment':
          return BriskersColors.schedule;
        default:
          return BriskersColors.invoices;
      }
    }

    IconData moduleIcon(String type) {
      switch (type) {
        case 'Job':
          return Icons.build_outlined;
        case 'Visit':
          return Icons.history_outlined;
        case 'invoice':
          return Icons.receipt_long_outlined;
        case 'estimate':
          return Icons.description_outlined;
        case 'Appointment':
          return Icons.calendar_today_outlined;
        default:
          return Icons.payments_outlined;
      }
    }

    Color statusColor(String status, Color fallback) {
      final key = status.toLowerCase().trim();
      if (key.contains('pending close') || key.contains('waiting') ||
          key.contains('draft') || key.contains('pending approval')) {
        return const Color(0xFFC77700);
      }
      if (key.contains('unpaid') || key.contains('overdue')) {
        return const Color(0xFFC62828);
      }
      if (key.contains('closed') || key.contains('completed') ||
          key.contains('paid') || key.contains('accepted') ||
          key.contains('converted')) {
        return const Color(0xFF2E7D32);
      }
      if (key.contains('recheck') || key.contains('void') ||
          key.contains('cancel')) {
        return const Color(0xFFC62828);
      }
      if (key.contains('open') || key.contains('progress') ||
          key.contains('sent')) {
        return const Color(0xFF1976D2);
      }
      return fallback;
    }
    final documentList = title == 'Invoices' || title == 'Estimates';
    final financialRows = records.where((record) =>
      title == 'Invoices' ? record['type'] == 'invoice'
        : record['type'] == 'estimate').toList();
    final knownAmounts = financialRows.where((record) =>
      record['total'] is num).toList();
    final totalValue = knownAmounts.fold<double>(0, (total, record) =>
      total + (record['total'] as num).toDouble());
    final money = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final missingAmounts = financialRows.length - knownAmounts.length;

    final sheetColor = title == 'Jobs' || title == 'Visits'
        ? BriskersColors.jobs
        : title == 'Estimates'
            ? BriskersColors.estimates
            : title == 'Appointments'
                ? BriskersColors.schedule
                : BriskersColors.invoices;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: Column(children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: sheetColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: sheetColor,
                ),
              ),
            ),
            if (documentList)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: sheetColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.account_balance_wallet_outlined,
                    color: sheetColor, size: 21),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title == 'Invoices'
                          ? 'Total Invoices' : 'Total Estimates',
                        style: TextStyle(color: sheetColor,
                          fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        '${financialRows.length} records'
                        '${missingAmounts > 0 ? ' • $missingAmounts amounts unavailable' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  )),
                  Text(money.format(totalValue),
                    style: TextStyle(color: sheetColor,
                      fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
            Expanded(child: records.isEmpty
              ? const Center(child: Text('No records found on this device.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
                  itemCount: records.length,
                  itemBuilder: (context, i) {
                    final item = records[i];
                    final type = item['type']?.toString() ?? '';
                    final number = item['number']?.toString().trim() ?? '';
                    final status = item['status']?.toString().trim() ?? '';
                    final color = moduleColor(type);
                    final stateColor = statusColor(status, color);
                    final amount = item['total'] is num
                        ? money.format(item['total']) : null;
                    final recordTitle = number.isEmpty
                        ? (item['title']?.toString().trim().isNotEmpty == true
                            ? item['title'].toString()
                            : type)
                        : type == 'invoice'
                            ? 'Invoice #$number'
                            : type == 'estimate'
                                ? 'Estimate #$number'
                                : type == 'Job'
                                    ? 'Job $number'
                                    : '$type $number';
                    final description = [
                      item['title'],
                      item['vehicle'],
                    ].map((value) => value?.toString().trim() ?? '')
                      .where((value) => value.isNotEmpty && value != recordTitle)
                      .join(' • ');
                    if (type == 'Job') {
                      final jobData = Map<String, dynamic>.from(
                        item['job_snapshot'] is Map
                          ? item['job_snapshot'] as Map
                          : <String, dynamic>{},
                      );
                      return JobCompactCard(
                        job: jobData,
                        statusControl: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(status, style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: stateColor,
                          )),
                        ),
                        onOpen: () {
                          Navigator.pop(sheetContext);
                          _openOverviewRecord(item);
                        },
                      );
                    }
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 9),
                      color: stateColor.withValues(alpha: 0.075),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: stateColor.withValues(alpha: 0.14)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openOverviewRecord(item);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 13),
                          child: Row(children: [
                            Icon(moduleIcon(type), color: color, size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(recordTitle,
                                  style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800),
                                ),
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(description,
                                    style: const TextStyle(fontSize: 14.5),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
                                ],
                                if (status.isNotEmpty) ...[
                                  const SizedBox(height: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: stateColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(status,
                                      style: TextStyle(color: stateColor,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            )),
                            if (documentList && amount != null) ...[
                              const SizedBox(width: 6),
                              Text(amount, style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w800)),
                            ],
                            const SizedBox(width: 5),
                            Icon(Icons.chevron_right, color: color, size: 21),
                          ]),
                        ),
                      ),
                    );
                  },
                )),
            if (_canManageQuickActions &&
                (title == 'Jobs' || title == 'Invoices' ||
                 title == 'Estimates' || title == 'Appointments'))
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: sheetColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      if (title == 'Jobs') {
                        _createJob();
                      } else if (title == 'Invoices') {
                        _createInvoiceForCustomer();
                      } else if (title == 'Estimates') {
                        _createEstimateForCustomer();
                      } else {
                        _scheduleAppointment();
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: Text(title == 'Jobs' ? 'New Job'
                      : title == 'Invoices' ? 'New Invoice'
                      : title == 'Estimates' ? 'New Estimate'
                      : 'New Appointment'),
                  ),
                ),
              ),
            if (widget.sharedBottomNavigationBar != null)
              widget.sharedBottomNavigationBar!,
          ]),
        ),
      ),
    );
  }

  Widget _customerOverviewCard() => FutureBuilder<List<Map<String, dynamic>>>(
    key: ValueKey(('customer-overview', _jobVisibility.epoch)),
    future: _activeCustomerItems(),
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      final jobs = rows.where((item) => item['type'] == 'Job').toList();
      final invoices = rows.where((item) => item['type'] == 'invoice').toList();
      final estimates = rows.where((item) => item['type'] == 'estimate').toList();
      final appointments = rows.where((item) => item['type'] == 'Appointment').toList();
      final visits = rows.where((item) => item['type'] == 'Visit').toList();
      final docs = [...invoices, ...estimates];
      DateTime activityDate(Map<String, dynamic> item) =>
        DateTime.tryParse(item['server_updated_at']?.toString() ?? '') ??
        DateTime.tryParse(item['document_date']?.toString() ?? '') ??
        DateTime(1970);
      docs.sort((a, b) => activityDate(b).compareTo(activityDate(a)));
      final balance = invoices.fold<int>(0, (sum, item) =>
        sum + ((item['balance_due_cents'] as int?) ?? 0));
      final pending = invoices.fold<int>(0, (sum, item) =>
        sum + ((item['pending_cents'] as int?) ?? 0));
      final paymentInvoices = invoices.where((item) =>
        (item['pending_cents'] as int? ?? 0) > 0 ||
        (item['balance_due_cents'] is int &&
          item['balance_due_cents'] != null &&
          (item['total'] is num) &&
          (item['balance_due_cents'] as int) <
            ((item['total'] as num) * 100).round())).toList();
      Widget link(String title, IconData icon, Color color,
          List<Map<String, dynamic>> items) => ListTile(
        dense: true, visualDensity: VisualDensity.compact,
        leading: Icon(icon, color: color, size: 25),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${items.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6), const Icon(Icons.chevron_right, size: 18),
        ]),
        onTap: () => _showOverviewList(title, items),
      );
      return Card(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(minHeight: 2),
          if (snapshot.hasError)
            const ListTile(title: Text('Saved customer activity unavailable')),
          link('Jobs', Icons.build_outlined, BriskersColors.jobs, jobs),
          link('Invoices', Icons.receipt_long_outlined, BriskersColors.invoices, invoices),
          link('Estimates', Icons.description_outlined, BriskersColors.estimates, estimates),
          link('Appointments', Icons.calendar_today_outlined, BriskersColors.schedule, appointments),
          link('Visits', Icons.history_outlined, BriskersColors.jobs, visits),
          link('Payments', Icons.payments_outlined, BriskersColors.invoices, paymentInvoices),
          if (balance > 0 || pending > 0) ...[
            const Divider(height: 12),
            if (balance > 0)
              ListTile(dense: true, title: Text(tr('customerInvoiceBalanceDue')),
                trailing: Text('\u0024${(balance/100).toStringAsFixed(2)}')),
            if (pending > 0)
              ListTile(dense: true, title: Text(tr('customerPendingReceipts')),
                trailing: Text('\u0024${(pending/100).toStringAsFixed(2)}')),
          ],
          const Divider(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 3, 16, 5),
            child: Text('Recent Invoices & Estimates',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          for (final item in docs.take(3))
            ListTile(
              dense: true,
              leading: Icon(item['type'] == 'invoice' ?
                Icons.receipt_long_outlined : Icons.description_outlined,
                color: item['type'] == 'invoice' ? BriskersColors.invoices :
                  BriskersColors.estimates),
              title: Text('${item['type'] == 'invoice' ? 'Invoice' : 'Estimate'} #${item['number'] ?? 'Pending sync'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                item['status']?.toString() ?? '',
                item['vehicle']?.toString() ?? '',
                if ((item['job_id']?.toString() ?? '').isNotEmpty) 'Linked Job',
              ].where((s) => s.isNotEmpty).join(' • '),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (item['total'] is num)
                  Text('\u0024${(item['total'] as num).toStringAsFixed(2)}'),
                const Icon(Icons.chevron_right, size: 18),
              ]),
              onTap: () => _openOverviewRecord(item),
            ),
          if (docs.isEmpty && snapshot.hasData)
            const Padding(padding: EdgeInsets.all(16),
              child: Text('No estimates or invoices found on this device.')),
        ]),
      ));
    },
  );

  Widget _offlineCountCard({
    required IconData icon,
    required String title,
    required String emptyText,
    required List<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic>)? label
  }) {
    return Card(
      child: ExpansionTile(
        maintainState: false,
        leading: Icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          rows.isEmpty
              ? emptyText
              : rows.length == 1
                  ? '1 saved item'
                  : '${rows.length} saved items',
        ),
        children: rows.isEmpty
            ? const <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No saved data yet.'),
                  ),
                ),
              ]
            : rows.map((row) {
                final text = label?.call(row) ?? '';
                return ListTile(
                  dense: true,
                  title: Text(
                    text.isEmpty ? 'Saved item' : text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget _offlineCustomerSections() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(('offline-customer-sections', _jobVisibility.epoch)),
      future: _loadOfflineSections(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading saved customer details...'),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final appointments = List<Map<String, dynamic>>.from(
          data['appointments'] ?? const <Map<String, dynamic>>[],
        );
        final history = Map<String, dynamic>.from(
          data['history'] ?? const <String, dynamic>{},
        );
        final jobs = List<dynamic>.from(history['jobs'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final documents = List<dynamic>.from(history['documents'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final expenses = List<dynamic>.from(history['expenses'] ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();

        return Column(
          children: [

            _offlineCountCard(
              icon: Icons.calendar_month_outlined,
              title: 'Appointments',
              emptyText: 'No saved appointments',
              rows: appointments,
              label: (row) {
                final title = row['title']?.toString().trim() ?? '';
                final starts = row['starts_at']?.toString().trim() ?? '';
                return [starts, title].where((x) => x.isNotEmpty).join(' • ');
              },
            ),
            const SizedBox(height: 18),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text(
                  'Service History',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${jobs.length} jobs • ${documents.length} documents • ${expenses.length} expenses',
                ),
                children: [
                  if (jobs.isEmpty && documents.isEmpty && expenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No saved service history yet.'),
                      ),
                    )
                  else ...[
                    for (final job in jobs.take(12))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.build_outlined),
                        title: Text(
                          [
                            job['job_number']?.toString() ?? '',
                            job['title']?.toString() ?? '',
                          ].where((x) => x.isNotEmpty).join(' — '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (jobs.length > 12)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('+ ${jobs.length - 12} more jobs saved'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }


  String get _detailCacheKey =>
      'briskers_customer_detail_${widget.businessId}_${widget.customerId}';

  Future<Map<String, dynamic>?> _cachedFullDetail() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_detailCacheKey);
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

  Future<void> _saveFullDetail(Map<String, dynamic> detail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_detailCacheKey, jsonEncode(detail));
  }


  @override
  void initState() {
    super.initState();
    _listenForQuarantine();
    _load();
  }

  bool _reportedReview = false;

  void _reportReview() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedReview || _data == null ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _reportedReview = true;
      widget.onReviewed?.call();
    });
  }

  void _listenForQuarantine() {
    _jobVisibility = JobSummaryVisibility(
      businessId: widget.businessId,
      onQuarantine: (_) {
        if (!mounted) return;
        // New FutureBuilder keys discard retained activity/history snapshots.
        // Customer identity, vehicles, and independently readable invoices stay.
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _jobVisibility.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomerDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId) {
      _jobVisibility.dispose();
      _data = null;
      _reportedReview = false;
      _onlineReady = false;
      _listenForQuarantine();
      _load();
    }
  }

  Future<void> _load() async {
    final visibility = _jobVisibility;
    final generation = visibility.beginLoad();
    var localShown = false;
    final forceOnline =
        BriskersConnectionModeController.instance.forceOnline;
    final forceOffline =
        BriskersConnectionModeController.instance.forceOffline;

    if (!forceOnline) {
      try {
        final cached = await _cachedFullDetail();
        final local = cached ??
            await _localCustomers.customerDetail(
              widget.businessId,
              widget.customerId,
            );
        if (local != null && mounted && visibility.isCurrent(generation)) {
          localShown = true;
          setState(() {
            _data = local;
            _showingLocal = true;
            _onlineReady = false;
            _error = null;
          });
          _reportReview();
        }
      } catch (_) {
        // The online refresh below can still populate the local cache.
      }
    }

    if (!mounted || !visibility.isCurrent(generation)) return;

    if (forceOffline) {
      if (mounted && localShown && visibility.isCurrent(generation)) {
        setState(() {
          _onlineReady = false;
          _showingLocal = true;
          _error = null;
        });
      }
      return;
    }

    try {
      try {
        await _offlineAdmin.flush(widget.businessId);
      } catch (_) {
        // Pending edits stay queued if the connection is not ready yet.
      }
      // Full customer/vehicle dataset sync belongs to the background Sync Now
      // workflow, not to opening every individual customer profile.
      if (!await _localCustomers.hasBootstrap(widget.businessId)) {
        await _sync.pull(widget.businessId);
      }
      Map<String, dynamic>? fullDetail;
      try {
        fullDetail = await _api.customerDetail(
          widget.businessId,
          widget.customerId,
        );
        if (!mounted || !visibility.isCurrent(generation)) return;
        await _saveFullDetail(fullDetail);
        await _sync.refreshCustomer(
          widget.businessId,
          widget.customerId,
          fetchedDetail: fullDetail,
        );
      } catch (_) {
        // The regular local snapshot is still usable if a focused refresh fails.
      }
      final bootstrapped =
          await _localCustomers.hasBootstrap(widget.businessId);
      final local = fullDetail ??
          await _localCustomers.customerDetail(
            widget.businessId,
            widget.customerId,
          );

      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _data = local;
        _onlineReady = bootstrapped && local != null;
        _showingLocal = !_onlineReady && local != null;
        _error = local == null
            ? (bootstrapped
                ? 'Customer not found.'
                : 'Customer access is not available for this account.')
            : null;
      });
      _reportReview();
    } catch (error) {
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _onlineReady = false;
        if (localShown && !forceOnline) {
          _showingLocal = true;
          _error = null;
        } else {
          _error = error.toString();
        }
      });
    }
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    if (!_canEditLocal) return;
    final saved = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCustomerScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customer: customer,
        ),
      ),
    );
    if (saved == null || !mounted) return;

    setState(() {
      final data = Map<String, dynamic>.from(_data ?? const {});
      final current = Map<String, dynamic>.from(
        data['customer'] ?? const {},
      );
      current.addAll(saved);
      data['customer'] = current;
      _data = data;
    });

    await _load();
  }

  Future<void> _editProblemFlag() async {
    if (!_canEditLocal) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    bool flagged = customer['problem_flag'] == true;
    final controller = TextEditingController(
      text: customer['problem_flag_note']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Problem customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Flag this customer'),
                  value: flagged,
                  onChanged: (value) =>
                      setDialogState(() => flagged = value == true),
                ),
                if (flagged) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 6,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Reason / note',
                      hintText: 'Example: Non-paying customer',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _offlineAdmin.queueProblemFlag(
        widget.businessId,
        widget.customerId,
        flagged: flagged,
        note: flagged ? controller.text.trim() : null,
      );
      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await _offlineAdmin.flush(widget.businessId);
        } catch (_) {}
      }
      await _load();
    }
    controller.dispose();
  }

  Future<void> _addVehicle() async {
    if (!_canEditLocal) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewVehicleScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editVehicle(Map<String, dynamic> vehicle) async {
    if (!_canEditLocal) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewVehicleScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          vehicle: vehicle,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _scheduleAppointment() async {
    if (!_onlineReady) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    final vehicles = List<dynamic>.from(
      _data?['vehicles'] ?? const [],
    );

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentCreateScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customerName: customer['name']?.toString() ?? 'Customer',
          vehicles: vehicles,
        ),
      ),
    );

    if (changed == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment scheduled.')),
        );
      }
    }
  }

  Future<void> _createJob() async {
    if (!_onlineReady) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    final vehicles = List<dynamic>.from(
      _data?['vehicles'] ?? const [],
    );

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => JobCreateScreen(
          businessId: widget.businessId,
          customerId: widget.customerId,
          customerName: customer['name']?.toString() ?? 'Customer',
          roleCode: widget.roleCode,
          vehicles: vehicles,
        ),
      ),
    );

    if (changed == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job created.')),
        );
      }
    }
  }

  Future<void> _createInvoiceForCustomer() async {
    if (_data == null || !_canManageQuickActions) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const <String, dynamic>{},
    );
    final vehicles = List<dynamic>.from(_data?['vehicles'] ?? const []);
    final invoiceId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BlankInvoiceSetupScreen(
          businessId: widget.businessId,
          initialCustomerId: widget.customerId,
          initialCustomerName: customer['name']?.toString() ?? 'Customer',
          initialVehicles: vehicles,
        ),
      ),
    );
    if (!mounted || invoiceId == null || invoiceId.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: widget.roleCode == 'owner',
          roleCode: widget.roleCode,
          canManageExpenses: _canManageQuickActions,
          initialAction: 'add_item',
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _createEstimateForCustomer() async {
    if (_data == null || !_canManageQuickActions) return;
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const <String, dynamic>{},
    );
    final vehicles = List<dynamic>.from(_data?['vehicles'] ?? const []);
    String? jobId;
    try {
      if (BriskersConnectionModeController.instance.forceOffline) {
        final documentId=await Navigator.push<String>(
          context,MaterialPageRoute(builder:(_)=>BlankInvoiceSetupScreen(
            businessId:widget.businessId,
            kind:'estimate',
            initialCustomerId:widget.customerId,
            initialCustomerName:customer['name']?.toString() ?? 'Customer',
            initialVehicles:vehicles,
          )),
        );
        if (!mounted || documentId==null) return;
        await Navigator.push<void>(context,MaterialPageRoute(
          builder:(_)=>JobDocumentScreen(
            businessId:widget.businessId,
            documentId:documentId,
            isOwner:widget.roleCode=='owner',
            roleCode:widget.roleCode,
            canManageExpenses:_canManageQuickActions,
            initialAction:'add_item',
          ),
        ));
        return;
      }
      final history = await _api.customerServiceHistory(
        widget.businessId, widget.customerId,
      );
      if (!mounted) return;
      final active = history.where((job) {
        final status = job['status']?.toString() ?? '';
        return status != 'completed' && status != 'cancelled';
      }).toList();

      if (active.isNotEmpty) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Create estimate'),
                  subtitle: Text('Existing Job or standalone estimate.'),
                ),
                ListTile(
                  leading: const Icon(Icons.build_outlined),
                  title: const Text('Existing customer job'),
                  onTap: () => Navigator.pop(sheetContext, 'existing'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('New Estimate (no Job)'),
                  onTap: () => Navigator.pop(sheetContext, 'new'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'existing') {
          final picked = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.65,
                child: ListView(
                  children: [
                    const ListTile(title: Text('Select an active job')),
                    for (final job in active)
                      ListTile(
                        leading: const Icon(Icons.build_outlined),
                        title: Text(
                          '${job['job_number'] ?? ''} • ${job['title'] ?? 'Job'}',
                        ),
                        subtitle: Text(job['vehicle']?.toString() ?? ''),
                        onTap: () => Navigator.pop(sheetContext, job),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (!mounted || picked == null) return;
          jobId = picked['id']?.toString();
        }
      }

      if (jobId == null) {
        final documentId=await Navigator.push<String>(
          context,
          MaterialPageRoute(builder:(_)=>BlankInvoiceSetupScreen(
            businessId:widget.businessId,
            kind:'estimate',
            initialCustomerId:widget.customerId,
            initialCustomerName:customer['name']?.toString() ?? 'Customer',
            initialVehicles:vehicles,
          )),
        );
        if (!mounted || documentId==null || documentId.isEmpty) return;
        await Navigator.push<void>(
          context,MaterialPageRoute(builder:(_)=>JobDocumentScreen(
            businessId:widget.businessId,
            documentId:documentId,
            isOwner:widget.roleCode=='owner',
            roleCode:widget.roleCode,
            canManageExpenses:_canManageQuickActions,
            initialAction:'add_item',
          )),
        );
        if (mounted) await _load();
        return;
      }
      if (jobId.isEmpty) {
        throw StateError('No job was selected for the estimate.');
      }
      final documentId = await _api.createEstimate(widget.businessId, jobId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDocumentScreen(
            businessId: widget.businessId,
            documentId: documentId,
            isOwner: widget.roleCode == 'owner',
            roleCode: widget.roleCode,
            canManageExpenses: _canManageQuickActions,
            initialAction: 'add_item',
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create estimate: $error')),
      );
    }
  }

  void _openCustomerNoteComposer() {
    setState(() { _expandQuickNotes = true; _customerTab = 3; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _notesSectionKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0.08,
        );
      }
    });
  }

  Future<void> _showQuickActions() async {
    if (_data == null || !_canManageQuickActions) return;
    final action = await showModalBottomSheet<CustomerQuickAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => CustomerQuickActionsSheet(
        roleCode: widget.roleCode,
        offline: BriskersConnectionModeController.instance.forceOffline,
        onSelected: (choice) => Navigator.pop(sheetContext, choice),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case CustomerQuickAction.appointment:
        await _scheduleAppointment();
      case CustomerQuickAction.job:
        await _createJob();
      case CustomerQuickAction.estimate:
        await _createEstimateForCustomer();
      case CustomerQuickAction.invoice:
        await _createInvoiceForCustomer();
      case CustomerQuickAction.vehicle:
        await _addVehicle();
      case CustomerQuickAction.note:
        _openCustomerNoteComposer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = Map<String, dynamic>.from(
      _data?['customer'] ?? const {},
    );
    final vehicles = List<dynamic>.from(
      _data?['vehicles'] ?? const [],
    );
    final addressRaw = customer['billing_address'];
    final address = addressRaw is Map
        ? Map<String, dynamic>.from(addressRaw)
        : <String, dynamic>{};
    final addressLine1 = address['line1']?.toString().trim() ?? '';
    final addressLine2 = address['line2']?.toString().trim() ?? '';
    final addressCity = address['city']?.toString().trim() ?? '';
    final addressState = address['state']?.toString().trim() ?? '';
    final addressZip =
        (address['postal_code'] ?? address['zip'])?.toString().trim() ?? '';
    final addressText = <String>[
      if (addressLine1.isNotEmpty) addressLine1,
      if (addressLine2.isNotEmpty) addressLine2,
      if (addressCity.isNotEmpty ||
          addressState.isNotEmpty ||
          addressZip.isNotEmpty)
        <String>[
          if (addressCity.isNotEmpty) addressCity,
          if (addressState.isNotEmpty) addressState,
          if (addressZip.isNotEmpty) addressZip,
        ].join(' '),
    ].join('\n');

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: BriskersColors.customers.withValues(alpha: 0.12),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '${customer['name'] ?? 'Customer'}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (customer['problem_flag'] == true) ...[
              const SizedBox(width: 6),
              const Icon(Icons.flag, color: Colors.red, size: 20),
            ],
          ],
        ),
      ),
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      floatingActionButton: _data == null || !_canManageQuickActions
          ? null
          : FloatingActionButton(
              onPressed: _showQuickActions,
              tooltip: 'Customer actions',
              child: const Icon(Icons.add),
            ),
      body: _data == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_showingLocal)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: BriskersColors.customers.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 18),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Showing saved customer and vehicle data • edits save locally and sync when reconnected',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(child: TextButton(
                        onPressed: () => setState(() => _customerTab = i),
                        style: TextButton.styleFrom(
                          backgroundColor: _customerTab == i
                            ? BriskersColors.customers.withValues(alpha: 0.14) : null,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(const <IconData>[Icons.dashboard_outlined,
                            Icons.person_outline, Icons.directions_car_outlined,
                            Icons.note_alt_outlined][i], size: 25),
                          Text(const <String>['Overview', 'Info', 'Vehicles', 'Notes'][i],
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ]),
                      )),
                  ]),
                  const SizedBox(height: 8),
                  if (_customerTab == 1) Card(
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      leading: const Icon(Icons.person_outline, color: BriskersColors.customers),
                      title: const Text('Customer information', style: TextStyle(fontWeight: FontWeight.bold)),
                      children: [ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${customer['name'] ?? ''}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (customer['problem_flag'] == true)
                            const Icon(Icons.flag, color: Colors.red),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ('${customer['phone'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                formatUsPhone('${customer['phone']}'),
                              ),
                            ),
                          if ('${customer['email'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('${customer['email']}'),
                            ),
                          if (addressText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 17),
                                  const SizedBox(width: 5),
                                  Expanded(child: Text(addressText)),
                                ],
                              ),
                            ),
                          if (_canEditLocal) ...[
                            const SizedBox(height: 2),
                            const Text('Tap to edit'),
                          ],
                        ],
                      ),
                      trailing: _canEditLocal
                          ? const Icon(Icons.edit_outlined)
                          : null,
                      onTap: _canEditLocal
                          ? () => _editCustomer(customer)
                          : null,
                    )],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_customerTab == 0 && _canManageQuickActions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(child: FilledButton.icon(
                          onPressed: _showQuickActions,
                          icon: const Icon(Icons.add),
                          label: const Text('New'),
                          style: FilledButton.styleFrom(
                            backgroundColor: BriskersColors.customers,
                            foregroundColor: Colors.white,
                          ),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('New Message • Coming Soon'),
                        )),
                      ]),
                    ),
                  if (_customerTab == 0) _customerOverviewCard(),
                  const SizedBox(height: 10),
                  if (_customerTab == 1) CustomerProblemFlagCard(
                    customerId: widget.customerId,
                    flagged: customer['problem_flag'] == true,
                    note: customer['problem_flag_note']?.toString() ?? '',
                    canEdit: _canEditLocal,
                    onEdit: _editProblemFlag,
                  ),
                  const SizedBox(height: 18),
                  if (_customerTab == 2) CustomerVehiclesSection(
                    vehicles: vehicles,
                    onAdd: _addVehicle,
                    onEdit: _editVehicle,
                    enabled: _canEditLocal,
                  ),
                  const SizedBox(height: 18),
                  if (_customerTab == 2) Card(
                    child: ListTile(
                      leading: const Icon(Icons.car_repair_outlined, color: BriskersColors.vehicles),
                      title: const Text('All Vehicle Findings',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('View open and resolved findings across vehicles'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('All Vehicle Findings')),
                          body: ListView(children: [CustomerVehicleFindingsSection(
                            businessId: widget.businessId,
                            customerId: widget.customerId,
                            vehicles: vehicles,
                            canManage: _canManageQuickActions,
                            canDelete: widget.roleCode == 'owner',
                            initiallyExpanded: true,
                          )]),
                        )),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_customerTab == 3) Container(
                    key: _notesSectionKey,
                    child: KeyedSubtree(
                      key: ValueKey(_expandQuickNotes),
                      child: CustomerNotesSection(
                        businessId: widget.businessId,
                        customerId: widget.customerId,
                        initiallyExpanded: _expandQuickNotes,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_customerTab == 0 && BriskersConnectionModeController.instance.forceOffline)
                    _offlineCustomerSections()
                  else if (_customerTab == 0) ...[
                    CustomerAppointmentsSection(
                      businessId: widget.businessId,
                      customerId: widget.customerId,
                    ),
                    const SizedBox(height: 18),
                    CustomerServiceHistorySection(
                  roleCode: widget.roleCode,
                      businessId: widget.businessId,
                      customerId: widget.customerId,
                      vehicles: vehicles,
                    ),
                    if (_onlineReady && widget.roleCode == 'owner') ...[
                      const SizedBox(height: 18),
                      CustomerAccountSection(
                        businessId: widget.businessId,
                        customerId: widget.customerId,
                        onDeleted: () =>
                            Navigator.pop(context, true),
                      ),
                    ],
                  ],
                  const SizedBox(height: 96),
                ],
              ),
            ),
    );
  }
}
