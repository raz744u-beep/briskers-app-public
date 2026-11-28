import '../core/document_presentation.dart';
import '../core/owner_report_models.dart';
import 'employee_nickname_store.dart';
import 'job_task_summary.dart';
import 'local_invoice_closure.dart';
import 'local_job_work_date.dart';
import 'local_owner_reports.dart';
import 'local_payroll_repository.dart';
import 'local_task_schedule.dart';

typedef CloseoutItem = ({String title, String detail, String id});

typedef ShopCloseout = ({
  DateTime loadedAt,
  DateTime friday,
  List<CloseoutItem> labor,
  List<CloseoutItem> invoices,
  List<CloseoutItem> jobs,
  List<String> verify,
  bool payrollAvailable,
});

class LocalShopCloseout {
  LocalShopCloseout(this.reports);
  final LocalOwnerReports reports;

  Future<ShopCloseout> load(
    String business, {
    required bool isOwner,
    DateTime? now,
  }) async {
    if (!isOwner || business.trim().isEmpty) {
      throw StateError('Owner access is required.');
    }
    final loadedAt = now ?? DateTime.now();
    final today = LocalJobWorkDate.today(now: loadedAt);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final friday = DateTime(monday.year, monday.month, monday.day + 4);
    final cutoff = today.isBefore(friday) ? today : friday;
    final data = await reports.load(business, isOwner: isOwner);
    final verify = <String>{...data.readIssues};
    final labor = <CloseoutItem>[];
    final invoices = <CloseoutItem>[];
    final jobs = <CloseoutItem>[];
    final jobsById = {for (final job in data.jobs) job['id']: job};
    final activeJobs = data.jobs
        .where(
          (job) => !const {
            'closed',
            'completed',
            'complete',
            'done',
            'cancelled',
            'canceled',
          }.contains(_text(job['status']).toLowerCase()),
        )
        .toList();
    final overdueJobs = <String>{};
    final payroll = LocalPayrollRepository(
      reports.db,
      business: business,
      owner: isOwner,
    );
    var payrollAvailable = false;
    try {
      final work = await payroll.savedWorkForCloseout();
      final names = await EmployeeNicknameStore(database: reports.db)
          .all(business);
      work.sort(
        (a, b) =>
            _text(a['completed_date']).compareTo(_text(b['completed_date'])),
      );
      for (final row in work) {
        final jobId = _text(row['job_id']);
        if (!jobsById.containsKey(jobId)) continue;
        if (row['source_active'] != 0 &&
            LocalTaskSchedule.overdue(row, now: today)) {
          overdueJobs.add(jobId);
        }
        if (row['state'] != 'Done' ||
            row['paid'] == 1 ||
            row['owner_prior_paid'] == 1 ||
            row['archived_labor'] == 1 ||
            row['duplicate_of_task_id'] != null) {
          continue;
        }
        final carry = LocalTaskSchedule.parse(row['carry_week']);
        final date = LocalTaskSchedule.parse(row['completed_date']);
        if ((carry?.isAfter(monday) ?? false) ||
            (date?.isAfter(cutoff) ?? false))
          continue;
        final job = _label(row['job_number'], 'Job');
        final name =
            names[row['employee_id']] ??
            _label(row['employee_name'], 'Employee');
        final task = _label(
          row['task_name'],
          _label(row['description'], 'Labor'),
        );
        final title = '$name · $job · $task';
        final minutes = reportInt(row['remaining_minutes']);
        if (row['source_active'] == 0 && row['assignment_conflict'] != 1)
          continue;
        if (date == null ||
            minutes <= 0 ||
            row['assignment_conflict'] == 1 ||
            row['payroll_treatment'] == 'review' ||
            reportInt(row['remaining_cents']) <= 0) {
          verify.add(
            '$title — verify the completion date, hours, assignment and pay rate in Payroll.',
          );
          continue;
        }
        final carryover = date.isBefore(monday)
            ? ' · Prior-week carryover'
            : '';
        labor.add((
          title: title,
          detail:
              '${(minutes / 60).toStringAsFixed(2)} unpaid hrs$carryover · Review in Payroll',
          id: jobId,
        ));
      }
      payrollAvailable = true;
    } catch (_) {
      labor.clear();
      overdueJobs.clear();
      verify.add(
        'Saved payroll could not be read. Verify completed labor in Payroll.',
      );
    }

    final closure = LocalInvoiceClosure(database: reports.db);
    final invoiceNumbers = <String, int>{};
    for (final invoice in data.invoices) {
      final number = _text(invoice['document_number']);
      if (number.isNotEmpty) {
        invoiceNumbers.update(number, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    for (final invoice in data.invoices) {
      final doc = DocumentPresentation({
        ...invoice,
        if (invoice['closed_at']?.toString() == '0') 'closed_at': null,
      });
      if (doc.isClosed ||
          const {
            'void',
            'voided',
            'cancelled',
            'canceled',
            'deleted',
          }.contains(doc.rawStatus))
        continue;
      final hint = _text(invoice['display_status_code'])
          .toLowerCase()
          .replaceAll(' ', '_');
      final total = doc.totalCents;
      final received = reportInt(invoice['_received_cents']);
      final hasPaidHint =
          const {'paid', 'pending_close', 'pendingclose'}.contains(hint) ||
          doc.rawStatus == 'paid';
      final title =
          'Invoice ${_label(invoice['document_number'], '(number missing)')} · ${_label(invoice['customer_name'], 'Customer')}';
      if (doc.requiresReconciliation) {
        verify.add('$title — verify the saved payments.');
        continue;
      }
      if (!hasPaidHint &&
          !(total != null && total > 0 && received >= total) &&
          !doc.fullyCovered)
        continue;
      if ((invoiceNumbers[_text(invoice['document_number'])] ?? 0) > 1) {
        verify.add('$title — verify the duplicate invoice number.');
        continue;
      }
      final id = _text(invoice['id']);
      try {
        final previews = await closure.preview(business, [
          id,
        ], isOwner: isOwner);
        if (previews.containsKey(id)) {
          invoices.add((
            title: title,
            detail: 'Balance \$0.00 · Review and close in Invoices',
            id: id,
          ));
        }
      } on StateError catch (error) {
        verify.add('$title — ${error.message}');
      } catch (_) {
        verify.add('$title — verify the saved receipt details before closing.');
      }
    }

    var progress = <String, JobTaskProgress>{};
    try {
      progress = await JobTaskSummary(reports.db).progressForJobs(
        business,
        activeJobs.map((job) => _text(job['id'])).toList(),
      );
    } catch (_) {
      verify.add(
        'Saved job task progress could not be read. Verify it from the Jobs list.',
      );
    }
    final ranked = <({int priority, CloseoutItem item})>[];
    for (final job in activeJobs) {
      final id = _text(job['id']);
      final tasks = progress[id];
      final unassigned =
          job['is_unassigned'] == 1 ||
          (_text(job['assigned_employee_id']).isEmpty &&
              _text(job['assigned_employee_name']).isEmpty);
      final complete =
          tasks != null && tasks.total > 0 && tasks.done == tasks.total;
      final overdue = overdueJobs.contains(id);
      final pendingRequests = reportInt(job['pending_request_count']);
      final status = _label(
        job['status_name'],
        _label(job['status'], 'Status missing'),
      );
      final reasons = [
        if (complete) 'All saved tasks done. Verify job completion',
        if (overdue) 'Overdue labor. Review next steps',
        if (unassigned) 'Review mechanic assignment',
        if (pendingRequests > 0) 'Review pending requests',
      ];
      if (reasons.isEmpty) reasons.add('Review what is holding the job open');
      ranked.add((
        priority: overdue
            ? 0
            : complete
            ? 1
            : unassigned || pendingRequests > 0
            ? 2
            : 3,
        item: (
          title:
              '${_label(job['job_number'], 'Job')} · ${_label(job['customer_name'], _label(job['title'], 'Customer'))}',
          detail: [status, ...reasons].join(' · '),
          id: id,
        ),
      ));
    }
    ranked.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      return priority == 0 ? a.item.title.compareTo(b.item.title) : priority;
    });
    jobs.addAll(ranked.map((row) => row.item));
    return (
      loadedAt: loadedAt,
      friday: friday,
      labor: labor,
      invoices: invoices,
      jobs: jobs,
      verify: verify.toList(),
      payrollAvailable: payrollAvailable,
    );
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
  static String _label(Object? value, String fallback) =>
      _text(value).isEmpty ? fallback : _text(value);
}
