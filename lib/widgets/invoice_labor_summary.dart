import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import '../services/employee_nickname_store.dart';
import '../services/historical_task_recordkeeping.dart';
import '../services/offline_job_admin_service.dart';

/// Read-only sum of this invoice's active saved mechanic allocations.
class InvoiceLaborSummary extends StatefulWidget {
  const InvoiceLaborSummary({
    super.key,
    required this.business,
    required this.invoice,
    this.revision = 0,
    this.database,
  });
  final String business, invoice;
  final int revision;
  final BriskersLocalDatabase? database;
  @override
  State<InvoiceLaborSummary> createState() => _InvoiceLaborSummaryState();
}

class _InvoiceLaborSummaryState extends State<InvoiceLaborSummary> {
  List<Map<String, dynamic>>? people;
  bool failed = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant InvoiceLaborSummary old) {
    super.didUpdateWidget(old);
    if (old.business != widget.business ||
        old.invoice != widget.invoice ||
        old.revision != widget.revision) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    final turn = ++generation;
    final db = widget.database ?? localDatabase;
    try {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      final result = <Map<String, dynamic>>[];
      if (names.containsAll({
        'regular_payroll_task_sources',
        'regular_payroll_portions',
        'regular_payroll_employees',
        'regular_payroll_estimates',
        'regular_payroll_assignment_meta',
      })) {
        final roster = await OfflineJobAdminService(
          database: db,
        ).cachedEmployees(widget.business);
        await HistoricalTaskRecordkeeping(db).prepare();
        final rows = await db
            .customSelect(
              '''
          SELECT COALESCE(h.employee_id,p.employee_id) AS employee_id,COALESCE(h.employee_name,e.name) AS name,SUM(COALESCE(h.minutes,v.minutes,0)) AS minutes
          FROM regular_payroll_task_sources s
          JOIN regular_payroll_portions p ON p.business_id=s.business_id AND p.task_id=s.task_id
          JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id
          LEFT JOIN historical_task_recordkeeping_v1 h ON h.business_id=p.business_id AND h.allocation_id=p.id
          LEFT JOIN regular_payroll_estimates v ON v.business_id=p.business_id AND v.task_id=p.task_id AND v.employee_id=p.employee_id
          LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id
          WHERE s.business_id=? AND s.invoice_id=? AND s.active=1 AND (COALESCE(m.active,1)=1 OR p.state='Done')
          GROUP BY COALESCE(h.employee_id,p.employee_id),COALESCE(h.employee_name,e.name) ORDER BY name,employee_id
        ''',
              variables: [Variable(widget.business), Variable(widget.invoice)],
            )
            .get();
        final aliases = await EmployeeNicknameStore(
          database: db,
        ).all(widget.business);
        for (final row in rows) {
          final id = row.read<String>('employee_id');
          final saved = roster.where((r) => r['id'] == id).firstOrNull;
          final identity = {
            'id': id,
            'name': saved?['name'] ?? row.read<String>('name'),
            'nickname': aliases[id] ?? saved?['nickname'],
          };
          result.add({
            'label': EmployeeNicknameStore.displayLabel(identity, roster),
            'minutes': row.read<int>('minutes'),
          });
        }
      }
      if (mounted && turn == generation) {
        setState(() {
          people = result;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && turn == generation) {
        setState(() {
          people = null;
          failed = true;
        });
      }
    }
  }

  String hours(int minutes) {
    final value = (minutes / 60).toStringAsFixed(2);
    return value.endsWith('0') ? value.substring(0, value.length - 1) : value;
  }

  @override
  Widget build(BuildContext context) {
    final rows = people;
    return Container(
      key: const Key('invoice-assigned-labor-summary'),
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_outlined, color: Color(0xFF07594D), size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Labor Hours:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                if (rows == null)
                  Text(
                    failed ? 'Saved hours unavailable' : 'Loading saved hours…',
                  )
                else ...[
                  for (final row in rows) ...[
                    if (row != rows.first)
                      const Text(
                        '|',
                        style: TextStyle(color: Color(0xFF526171)),
                      ),
                    Text(
                      '${row['label']} ${hours(row['minutes'] as int)} hrs',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDF3E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Total ${hours(rows.fold<int>(0, (n, r) => n + (r['minutes'] as int)))} hrs',
                      style: const TextStyle(
                        color: Color(0xFF08763D),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
