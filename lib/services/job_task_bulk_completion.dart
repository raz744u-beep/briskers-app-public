import 'dart:convert';

import 'local_payroll_repository.dart';
import 'local_invoice_task_store.dart';

/// A confirmed snapshot, not a second work-credit or payment ledger.
class JobTaskCompletionPlan {
  JobTaskCompletionPlan(
    this.job,
    this.labor,
    this.general, {
    this.starting = false,
  });
  final bool starting;
  final String job;
  final List<Map<String, dynamic>> labor, general;
  int get count =>
      labor.map((r) => r['task_id']).toSet().length + general.length;
  String get signature => jsonEncode([
    starting,
    for (final r in labor)
      [
        'labor',
        r['id'],
        r['version'],
        r['employee_id'],
        r['estimated_minutes'],
        r['state'],
        r['actual_minutes'],
        r['paid_minutes'],
        r['can_finish_paid_progress'],
      ],
    for (final r in general)
      ['general', r['id'], r['employee_id'], r['status'], r['due_at']],
  ]);

  static JobTaskCompletionPlan fromRows(
    String job,
    List<Map<String, dynamic>> work,
    List<Map<String, dynamic>> general,
    DateTime now, {
    bool starting = false,
  }) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in work.where((r) => r['job_id'] == job)) {
      groups.putIfAbsent(row['task_id'] as String, () => []).add(row);
    }
    final labor = <Map<String, dynamic>>[];
    for (final group in groups.values) {
      final unfinished = group
          .where((r) => starting ? r['state'] == 'Open' : r['state'] != 'Done')
          .toList();
      // A split task is eligible only when every unfinished allocation is safe.
      if (unfinished.isNotEmpty &&
          unfinished.every(
            (r) =>
                r['archived_labor'] != 1 &&
                (r['source_kind'] != 'invoice' ||
                    LocalInvoiceTaskStore.currentPayrollDate(
                      r['invoice_date'],
                    )) &&
                r['source_active'] != 0 &&
                r['assignment_conflict'] != 1 &&
                r['owner_prior_paid'] != 1 &&
                ((r['paid'] != 1 && (r['paid_minutes'] as int? ?? 0) == 0) ||
                    (!starting && r['can_finish_paid_progress'] == true)) &&
                (starting || (r['estimated_minutes'] as int? ?? 0) > 0),
          )) {
        labor.addAll(unfinished.map(Map<String, dynamic>.of));
      }
    }
    labor.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final reminders =
        general
            .where(
              (r) =>
                  r['job_id'] == job &&
                  (starting
                      ? r['status'] == 'planned'
                      : r['status'] != 'done') &&
                  (r['due_at'] == null ||
                      (r['due_at'] as int) <= now.millisecondsSinceEpoch),
            )
            .map(Map<String, dynamic>.of)
            .toList()
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    return JobTaskCompletionPlan(job, labor, reminders, starting: starting);
  }
}

class JobTaskBulkCompletion {
  JobTaskBulkCompletion(this.repository);
  final LocalPayrollRepository repository;

  Future<JobTaskCompletionPlan> plan(
    String job,
    DateTime now, {
    bool starting = false,
  }) async => JobTaskCompletionPlan.fromRows(
    job,
    await repository.work(job: job),
    await repository.shopTasks(),
    now,
    starting: starting,
  );

  Future<int> start(JobTaskCompletionPlan confirmed, DateTime now) {
    if (!confirmed.starting) {
      throw ArgumentError('Confirm a Start All plan first.');
    }
    return _apply(confirmed, now);
  }

  Future<int> complete(JobTaskCompletionPlan confirmed, DateTime now) {
    if (confirmed.starting) {
      throw ArgumentError('Confirm a Finish All plan first.');
    }
    return _apply(confirmed, now);
  }

  Future<int> _apply(JobTaskCompletionPlan confirmed, DateTime now) async {
    await repository.prepare();
    return repository.db.transaction(() async {
      final current = await plan(
        confirmed.job,
        now,
        starting: confirmed.starting,
      );
      if (current.signature != confirmed.signature) {
        final work = await repository.work(job: confirmed.job);
        final general = await repository.shopTasks();
        // A completed retry is a no-op; every originally selected ID must
        // still exist and be Done. A conflict or missing task is not success.
        final alreadyDone =
            confirmed.labor.every(
              (old) => work.any(
                (r) =>
                    r['id'] == old['id'] &&
                    (confirmed.starting
                        ? r['state'] != 'Open'
                        : r['state'] == 'Done'),
              ),
            ) &&
            confirmed.general.every(
              (old) => general.any(
                (r) =>
                    r['id'] == old['id'] &&
                    r['job_id'] == confirmed.job &&
                    (confirmed.starting
                        ? r['status'] != 'planned'
                        : r['status'] == 'done'),
              ),
            );
        if (alreadyDone) return 0;
        throw StateError(
          'Tasks or assigned hours changed. Review and confirm again.',
        );
      }
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      for (final row in current.labor) {
        if (confirmed.starting) {
          final minutes =
              row['recorded_actual_minutes'] as int? ??
              row['actual_minutes'] as int? ??
              0;
          await repository.recordAllocatedTime(
            row['id'] as String,
            'In Progress',
            minutes,
            minutes,
            date,
          );
          continue;
        }
        final minutes = row['estimated_minutes'] as int;
        if (row['can_finish_paid_progress'] == true) {
          await repository.finishPaidProgress(row['id'] as String, date);
          continue;
        }
        await repository.recordAllocatedTime(
          row['id'] as String,
          'Done',
          minutes,
          minutes,
          date,
        );
      }
      for (final row in current.general) {
        await repository.setShopTaskStatus(
          row['employee_id'] as String,
          row['id'] as int,
          confirmed.starting ? 'in_progress' : 'done',
        );
      }
      return current.count;
    });
  }
}
