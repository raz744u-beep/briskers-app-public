import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/job_list_options.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_access_history.dart';
import 'local_job_retirement.dart';

class LocalJobDetailSnapshot {
  const LocalJobDetailSnapshot({
    required this.job,
    required this.preInspection,
    required this.findings,
    required this.statuses,
  });

  final Map<String, dynamic> job;
  final Map<String, dynamic>? preInspection;
  final List<Map<String, dynamic>> findings;
  final List<Map<String, dynamic>> statuses;
}

class LocalJobRepository {
  LocalJobRepository({BriskersLocalDatabase? database})
    : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<bool> hasJobBootstrap(String businessId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT bootstrapped
      FROM local_sync_states
      WHERE business_id = ? AND scope = 'jobs'
      LIMIT 1
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();

    return rows.isNotEmpty && rows.first.read<int>('bootstrapped') == 1;
  }

  // Retirement is a durable visibility decision. Keep the retained rows for
  // reconciliation, but exclude them before sorting, paging, or aggregating.
  static String _visibleJobSql(String alias) =>
      """
    NOT EXISTS (SELECT 1 FROM local_job_retirement_entities r
      WHERE r.business_id = $alias.business_id AND r.entity_kind = 'job'
        AND r.entity_id = $alias.id
        AND r.state IN ('pending','accepted','locally_cancelled'))
    AND NOT EXISTS (SELECT 1 FROM local_job_deletion_v3_fences v3
      WHERE v3.business_id=$alias.business_id AND v3.entity_kind='job'
        AND v3.entity_id=$alias.id)
  """;

  static const _finishedStatuses = "('completed','cancelled','closed')";

  // Import time is not business activity. MB jobs with no reliable historical
  // date sort last; a later edit still counts. Job number only breaks ties.
  static const _jobActivitySql = """
    MAX(
      COALESCE(j.completed_at, 0),
      CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
        THEN CASE WHEN j.server_updated_at > j.created_at
          THEN j.server_updated_at ELSE 0 END
        ELSE MAX(COALESCE(j.server_updated_at, 0),
                 COALESCE(j.created_at, 0)) END,
      COALESCE((SELECT MAX(MAX(
        COALESCE(v.closed_at, 0),
        CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
          AND v.server_updated_at <= j.created_at THEN 0
          ELSE COALESCE(v.server_updated_at, 0) END
      )) FROM local_job_visits v
        WHERE v.business_id = j.business_id AND v.job_id = j.id), 0),
      COALESCE((SELECT MAX(MAX(
        COALESCE(CAST(strftime('%s', d.document_date) AS INTEGER), 0),
        COALESCE(d.closed_at, 0),
        CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
          THEN CASE WHEN d.server_updated_at > d.created_at
            THEN d.server_updated_at ELSE 0 END
          ELSE MAX(COALESCE(d.server_updated_at, 0),
                   COALESCE(d.created_at, 0)) END
      )) FROM local_documents d
        WHERE d.business_id = j.business_id AND d.job_id = j.id), 0),
      COALESCE((SELECT MAX(MAX(
        COALESCE(i.inspected_at, 0),
        CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
          AND i.server_updated_at <= j.created_at THEN 0
          ELSE COALESCE(i.server_updated_at, 0) END
      )) FROM local_pre_inspections i
        WHERE i.business_id = j.business_id AND i.job_id = j.id), 0),
      COALESCE((SELECT MAX(MAX(
        COALESCE(f.resolved_at, 0),
        CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
          AND f.created_at = j.created_at THEN 0
          ELSE COALESCE(f.created_at, 0) END,
        CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
          AND f.server_updated_at <= j.created_at THEN 0
          ELSE COALESCE(f.server_updated_at, 0) END
      )) FROM local_findings f
        WHERE f.business_id = j.business_id
          AND (f.found_job_id = j.id OR f.repair_job_id = j.id)), 0),
      COALESCE((SELECT MAX(p.captured_at)
        FROM local_pre_inspection_photos p
        JOIN local_pre_inspections i ON i.business_id = p.business_id
          AND i.id = p.inspection_id
        WHERE i.business_id = j.business_id AND i.job_id = j.id), 0),
      COALESCE((SELECT MAX(p.captured_at)
        FROM local_finding_photos p
        JOIN local_findings f ON f.business_id = p.business_id
          AND f.id = p.finding_id
        WHERE f.business_id = j.business_id
          AND (f.found_job_id = j.id OR f.repair_job_id = j.id)), 0),
      COALESCE((SELECT MAX(MAX(COALESCE(o.created_at, 0),
        CASE WHEN json_valid(o.payload_json)
          THEN COALESCE(CAST(json_extract(o.payload_json, '\$._activity_at') AS INTEGER), 0)
          ELSE 0 END)) FROM sync_outbox o
        WHERE o.business_id = j.business_id AND o.state = 'pending'
          AND ((o.entity_id = j.id AND o.entity_type IN
            ('job_create', 'job_admin', 'work_summary', 'preinspection'))
          OR (o.entity_type IN ('invoice_payment_received', 'document_edit',
            'document_draft_create', 'estimate_add_to_invoice') AND EXISTS (
            SELECT 1 FROM local_documents pd
            WHERE pd.business_id = j.business_id AND pd.job_id = j.id
              AND pd.id = o.entity_id
          ))
          OR (o.entity_type IN ('finding_create', 'finding_update',
            'finding_action') AND EXISTS (
            SELECT 1 FROM local_findings pf
            WHERE pf.business_id = j.business_id
              AND (pf.found_job_id = j.id OR pf.repair_job_id = j.id)
              AND pf.id = o.entity_id
          )))), 0)
    )
  """;

  // A historical date is a separate presentation choice, never a rewrite of
  // server modification history. Completion/document/visit dates are evidence
  // of the work itself. Invoice settlement and visit container creation may be
  // later administrative activity. An undated MB import must not use its import
  // timestamp.
  static const _jobDateSql = """
    COALESCE(NULLIF(j.completed_at, 0),
      (SELECT MIN(CAST(strftime('%s', d.document_date) AS INTEGER))
        FROM local_documents d
        WHERE d.business_id = j.business_id AND d.job_id = j.id),
      (SELECT MIN(NULLIF(v.closed_at, 0)) FROM local_job_visits v
        WHERE v.business_id = j.business_id AND v.job_id = j.id),
      CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
        THEN 0 ELSE COALESCE(j.created_at, 0) END)
  """;

  static const _numberOrderSql = """
    CASE WHEN substr(j.job_number, instr(j.job_number, '-') + 1)
      GLOB '[0-9]*'
    THEN CAST(substr(j.job_number, instr(j.job_number, '-') + 1) AS INTEGER)
    ELSE -1 END DESC
  """;

  ({String sql, List<Variable<Object>> variables}) _filters(
    String businessId, {
    String? status,
    String? search,
    JobListView view = JobListView.all,
  }) {
    final where = <String>['j.business_id = ?', _visibleJobSql('j')];
    final variables = <Variable<Object>>[Variable<String>(businessId)];
    if (view == JobListView.active) {
      where.add('lower(j.status) NOT IN $_finishedStatuses');
    }
    if (status == 'paid_still_open') {
      // Payment state is never evidence that repair work is completed.
      where.add("lower(COALESCE(j.payment_state, '')) = 'paid'");
      where.add('lower(j.status) NOT IN $_finishedStatuses');
    } else if (status != null && status.isNotEmpty) {
      where.add('j.status = ?');
      variables.add(Variable<String>(status));
    }
    final query = search?.trim().toLowerCase() ?? '';
    if (RegExp(r'^[0-9]+$').hasMatch(query)) {
      where.add('(j.job_number = ? OR j.job_number = ? OR j.job_number = ?)');
      variables.addAll([
        Variable<String>(query),
        Variable<String>('J-$query'),
        Variable<String>('MB-$query'),
      ]);
    } else if (query.isNotEmpty) {
      where.add("""
        (lower(COALESCE(j.job_number, '')) LIKE ?
         OR lower(COALESCE(j.customer_name, '')) LIKE ?
         OR lower(COALESCE(j.vehicle_label, '')) LIKE ?
         OR lower(COALESCE(j.vehicle_vin, '')) LIKE ?
         OR lower(COALESCE(j.vehicle_plate, '')) LIKE ?
         OR lower(j.title) LIKE ?
         OR EXISTS (
           SELECT 1 FROM local_customers c
           WHERE c.business_id = j.business_id AND c.id = j.customer_id
             AND (lower(COALESCE(c.display_name, '')) LIKE ?
               OR lower(COALESCE(c.email, '')) LIKE ?
               OR lower(COALESCE(c.phone, '')) LIKE ?
               OR lower(COALESCE(c.list_email, '')) LIKE ?
               OR lower(COALESCE(c.list_phone, '')) LIKE ?)))
      """);
      for (var i = 0; i < 11; i++) {
        variables.add(Variable<String>('%$query%'));
      }
    }
    return (sql: where.join(' AND '), variables: variables);
  }

  Future<List<Map<String, dynamic>>> listJobs(
    String businessId, {
    String? status,
    String? search,
    JobListView view = JobListView.all,
    JobListSort sort = JobListSort.lastModified,
    String? userId,
    int limit = 50,
    int offset = 0,
  }) async {
    await LocalJobRetirement.ensureSchema(_database);
    await LocalJobAccessHistory(database: _database).ensureTable();
    // Activity is sorted before paging. Keep related lookups indexed even on
    // older installed databases so a large imported history stays usable.
    await _database.customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'idx_jobs_view_visits ON local_job_visits (business_id, job_id)',
    );
    await _database.customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'idx_jobs_view_outbox ON sync_outbox (business_id, entity_id, state)',
    );
    await _database.customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'idx_jobs_view_findings ON local_findings (business_id, vehicle_id, status)',
    );
    for (final index in const [
      'idx_jobs_view_inspections ON local_pre_inspections (business_id, job_id)',
      'idx_jobs_view_found_job ON local_findings (business_id, found_job_id)',
      'idx_jobs_view_repair_job ON local_findings (business_id, repair_job_id)',
      'idx_jobs_view_inspection_photos ON local_pre_inspection_photos (business_id, inspection_id)',
      'idx_jobs_view_finding_photos ON local_finding_photos (business_id, finding_id)',
    ]) {
      await _database.customStatement('CREATE INDEX IF NOT EXISTS $index');
    }
    final filters = _filters(
      businessId,
      status: status,
      search: search,
      view: view,
    );
    // Completed means the work was completed, regardless of a later payment,
    // import correction or note. Missing dates fall back to meaningful activity.
    final order = status?.toLowerCase() == 'completed'
        ? 'COALESCE(NULLIF(j.completed_at, 0), j.activity_at) DESC, '
              'j.activity_at DESC,'
        : view == JobListView.active
        ? """
          COALESCE(s.sort_order, 9999), lower(j.status),
          CASE WHEN upper(COALESCE(j.job_number, '')) LIKE 'MB-%'
            THEN COALESCE((SELECT MIN(CAST(strftime('%s', d.document_date) AS INTEGER))
              FROM local_documents d
              WHERE d.business_id = j.business_id AND d.job_id = j.id), 0)
            ELSE COALESCE(j.created_at, 0) END DESC,
        """
        : view == JobListView.all || sort == JobListSort.lastModified
        ? 'j.activity_at DESC,'
        : view == JobListView.recent && sort == JobListSort.lastAccessed
        // Accesses always precede unopened Jobs, even if a later import/edit
        // has a newer server timestamp. Never borrow another user's history.
        ? 'CASE WHEN a.last_accessed_at IS NULL THEN 1 ELSE 0 END, '
              'a.last_accessed_at DESC, j.job_date_at DESC,'
        : 'j.job_date_at DESC,';
    // Only legacy callers keep the old provisional pin. The Jobs screen's All
    // list is strictly newest activity first, including pending local Jobs.
    final legacyPin =
        view == JobListView.all || status?.toLowerCase() == 'completed'
        ? ''
        : """
          CASE WHEN (j.job_number = 'Pending sync' OR upper(j.job_number) LIKE 'TEMP-%')
            THEN 0 ELSE 1 END,
          CASE WHEN (j.job_number = 'Pending sync' OR upper(j.job_number) LIKE 'TEMP-%')
            THEN j.created_at END DESC,
        """;
    final rows = await _database
        .customSelect(
          """
      WITH job_activity AS (
        SELECT j.*, $_jobActivitySql AS activity_at,
          $_jobDateSql AS job_date_at FROM local_jobs j
        WHERE ${filters.sql}
      )
      SELECT j.*, a.last_accessed_at,
        COALESCE(s.sort_order, 9999) AS status_sort_order,
        (SELECT COUNT(*) FROM local_findings f
          WHERE f.business_id = j.business_id AND f.vehicle_id = j.vehicle_id
            AND f.status = 'open') AS open_findings
      FROM job_activity j
      LEFT JOIN local_job_statuses s
        ON s.business_id = j.business_id AND s.code = j.status
      LEFT JOIN local_job_accesses a
        ON a.business_id = j.business_id AND a.job_id = j.id AND a.user_id = ?
      ORDER BY
        $legacyPin
        $order
        $_numberOrderSql, j.id
      LIMIT ? OFFSET ?
      """,
          variables: [
            ...filters.variables,
            Variable<String>(userId ?? ''),
            Variable<int>(limit),
            Variable<int>(offset),
          ],
        )
        .get();
    return rows.map(_jobListMap).toList();
  }

  Future<String?> jobNumberForJob(String businessId, String jobId) async {
    if (await LocalJobRetirement.isJobBlocked(_database, businessId, jobId)) {
      return null;
    }
    final rows = await _database
        .customSelect(
          "SELECT job_number FROM local_jobs j WHERE business_id = ? AND id = ? "
          "AND ${_visibleJobSql('j')}",
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();
    if (rows.isEmpty) return null;
    final number = rows.single.readNullable<String>('job_number')?.trim();
    return number == null || number.isEmpty ? null : number;
  }

  /// Replace an invoice's provisional Job identity without leaving a hole in
  /// the Jobs list while the authoritative Job bundle is still downloading.
  /// A previously cached real Job always takes precedence over the placeholder.
  Future<String?> remapProvisionalJob(
    String businessId,
    String provisionalJobId,
    String serverJobId, {
    String? jobNumber,
  }) async {
    if (serverJobId.trim().isEmpty || serverJobId.startsWith('local-')) {
      throw StateError('The synced invoice did not return its linked Job.');
    }
    final number = jobNumber?.trim();
    return _database.transaction(() async {
      if (await LocalJobRetirement.isJobBlocked(
            _database,
            businessId,
            provisionalJobId,
          ) ||
          await LocalJobRetirement.isJobBlocked(
            _database,
            businessId,
            serverJobId,
          )) {
        throw StateError(
          'The linked Job is pending deletion or retired. '
          'Its provisional work has been preserved.',
        );
      }
      final source =
          await (_database.select(_database.localJobs)..where(
                (row) =>
                    row.businessId.equals(businessId) &
                    row.id.equals(provisionalJobId),
              ))
              .getSingleOrNull();
      if (source != null) {
        await _database
            .into(_database.localJobs)
            .insert(
              source.copyWith(
                id: serverJobId,
                jobNumber: Value<String?>(
                  number == null || number.isEmpty ? source.jobNumber : number,
                ),
                syncState: 'synced',
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      final real =
          await (_database.select(_database.localJobs)..where(
                (row) =>
                    row.businessId.equals(businessId) &
                    row.id.equals(serverJobId),
              ))
              .getSingleOrNull();
      if (real == null) {
        throw StateError('The linked Job is not saved locally yet.');
      }
      final currentNumber = real.jobNumber?.trim() ?? '';
      if (number != null &&
          number.isNotEmpty &&
          (currentNumber.isEmpty ||
              currentNumber == 'Pending sync' ||
              currentNumber.toUpperCase().startsWith('TEMP-'))) {
        await (_database.update(_database.localJobs)..where(
              (row) =>
                  row.businessId.equals(businessId) &
                  row.id.equals(serverJobId),
            ))
            .write(LocalJobsCompanion(jobNumber: Value<String?>(number)));
      }
      if (provisionalJobId != serverJobId) {
        // The blank visit made with a Quick Invoice has no server identity.
        // Preserve actual work and its outbox instead of deleting user edits.
        await _database.customStatement(
          "DELETE FROM local_job_visits WHERE business_id = ? AND job_id = ? "
          "AND id LIKE 'local-visit-%' AND trim(COALESCE(work_summary, '')) = '' "
          "AND NOT EXISTS (SELECT 1 FROM sync_outbox WHERE business_id = ? "
          "AND entity_type = 'work_summary' AND entity_id = ?)",
          [businessId, provisionalJobId, businessId, provisionalJobId],
        );
        for (final table in const [
          'local_documents',
          'local_job_visits',
          'local_job_assignments',
          'local_pre_inspections',
          'local_appointments',
        ]) {
          await _database.customStatement(
            'UPDATE $table SET job_id = ? WHERE business_id = ? AND job_id = ?',
            [serverJobId, businessId, provisionalJobId],
          );
        }
        for (final column in const ['found_job_id', 'repair_job_id']) {
          await _database.customStatement(
            'UPDATE local_findings SET $column = ? '
            'WHERE business_id = ? AND $column = ?',
            [serverJobId, businessId, provisionalJobId],
          );
        }
        final queued = await _database
            .customSelect(
              'SELECT id, entity_id, payload_json FROM sync_outbox WHERE business_id = ?',
              variables: [Variable<String>(businessId)],
            )
            .get();
        for (final row in queued) {
          final payload = _jsonMap(row.read<String>('payload_json'));
          var changed = false;
          for (final key in const ['job_id', 'found_job_id', 'repair_job_id']) {
            if (payload[key] == provisionalJobId) {
              payload[key] = serverJobId;
              changed = true;
            }
          }
          final patch = payload['patch'];
          if (patch is Map) {
            for (final key in const [
              'job_id',
              'found_job_id',
              'repair_job_id',
            ]) {
              if (patch[key] == provisionalJobId) {
                patch[key] = serverJobId;
                changed = true;
              }
            }
          }
          final entityId = row.read<String>('entity_id');
          if (!changed && entityId != provisionalJobId) continue;
          await _database.customStatement(
            'UPDATE sync_outbox SET entity_id = ?, payload_json = ? WHERE id = ?',
            [
              entityId == provisionalJobId ? serverJobId : entityId,
              changed ? jsonEncode(payload) : row.read<String>('payload_json'),
              row.read<int>('id'),
            ],
          );
        }
        await LocalJobAccessHistory(database: _database)
            .remapJob(businessId, provisionalJobId, serverJobId);
        await _database.customStatement(
          'DELETE FROM local_jobs WHERE business_id = ? AND id = ?',
          [businessId, provisionalJobId],
        );
      }
      return jobNumberForJob(businessId, serverJobId);
    });
  }

  Future<int> jobCount(
    String businessId, {
    String? status,
    String? search,
    JobListView view = JobListView.all,
  }) async {
    await LocalJobRetirement.ensureSchema(_database);
    final filters = _filters(
      businessId,
      status: status,
      search: search,
      view: view,
    );
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS count FROM local_jobs j WHERE ${filters.sql}',
          variables: filters.variables,
        )
        .getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchJobCount(String businessId, {String? status}) async* {
    await LocalJobRetirement.ensureSchema(_database);
    final where = <String>['j.business_id = ?', _visibleJobSql('j')];
    final variables = <Variable<Object>>[Variable<String>(businessId)];
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      variables.add(Variable<String>(status));
    }

    yield* _database
        .customSelect(
          'SELECT COUNT(*) AS count FROM local_jobs j WHERE ${where.join(' AND ')}',
          variables: variables,
          readsFrom: {_database.localJobs},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
  }

  Future<List<Map<String, dynamic>>> unassignedOpenJobs(
    String businessId, {
    int limit = 25,
  }) async {
    await LocalJobRetirement.ensureSchema(_database);
    final rows = await _database
        .customSelect(
          '''
      SELECT id, job_number, title, customer_name, vehicle_label, status
      FROM local_jobs j
      WHERE j.business_id = ?
        AND ${_visibleJobSql('j')}
        AND is_unassigned = 1
        AND lower(status) NOT IN $_finishedStatuses
      ORDER BY created_at DESC, id
      LIMIT ?
      ''',
          variables: [Variable<String>(businessId), Variable<int>(limit)],
        )
        .get();

    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row.read<String>('id'),
            'job_number': row.readNullable<String>('job_number'),
            'title': row.read<String>('title'),
            'customer_name': row.readNullable<String>('customer_name'),
            'vehicle': row.readNullable<String>('vehicle_label'),
            'status': row.read<String>('status'),
            '_local_snapshot': true,
          },
        )
        .toList();
  }

  Future<int> unassignedOpenJobCount(String businessId) async {
    await LocalJobRetirement.ensureSchema(_database);
    final row = await _database
        .customSelect(
          '''
      SELECT COUNT(*) AS count
      FROM local_jobs j
      WHERE j.business_id = ?
        AND ${_visibleJobSql('j')}
        AND is_unassigned = 1
        AND lower(status) NOT IN $_finishedStatuses
      ''',
          variables: [Variable<String>(businessId)],
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<int> activeJobCount(String businessId) async {
    await LocalJobRetirement.ensureSchema(_database);
    final row = await _database
        .customSelect(
          '''
      SELECT COUNT(*) AS count
      FROM local_jobs j
      WHERE j.business_id = ?
        AND ${_visibleJobSql('j')}
        AND lower(status) NOT IN $_finishedStatuses
      ''',
          variables: [Variable<String>(businessId)],
        )
        .getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchActiveJobCount(String businessId) async* {
    await LocalJobRetirement.ensureSchema(_database);
    yield* _database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM local_jobs j
          WHERE j.business_id = ?
        AND ${_visibleJobSql('j')}
            AND lower(status) NOT IN $_finishedStatuses
          ''',
          variables: [Variable<String>(businessId)],
          readsFrom: {_database.localJobs},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
  }

  Future<Map<String, int>> jobStatusCounts(
    String businessId, {
    JobListView view = JobListView.all,
  }) async {
    await LocalJobRetirement.ensureSchema(_database);
    final rows = await _database
        .customSelect(
          '''
      SELECT status, COUNT(*) AS count
      FROM local_jobs j
      WHERE j.business_id = ?
        AND ${_visibleJobSql('j')}
      ${view == JobListView.active ? 'AND lower(status) NOT IN $_finishedStatuses' : ''}
      GROUP BY status
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('status'): row.read<int>('count'),
    };
  }

  Future<List<Map<String, dynamic>>> jobStatuses(String businessId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT code, name, color_hex, icon_key, sort_order
      FROM local_job_statuses
      WHERE business_id = ?
      ORDER BY sort_order, name, code
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();

    return rows
        .map(
          (row) => <String, dynamic>{
            'code': row.read<String>('code'),
            'name': row.read<String>('name'),
            'color_hex': row.readNullable<String>('color_hex'),
            'icon_key': row.readNullable<String>('icon_key'),
            'sort_order': row.read<int>('sort_order'),
          },
        )
        .toList();
  }

  Future<void> replaceJobStatuses(
    String businessId,
    List<Map<String, dynamic>> statuses,
  ) async {
    await _database.transaction(() async {
      await _database.customStatement(
        'DELETE FROM local_job_statuses WHERE business_id = ?',
        [businessId],
      );

      for (final status in statuses) {
        final code = status['code']?.toString() ?? '';
        if (code.isEmpty) continue;
        await _database.customStatement(
          '''
          INSERT INTO local_job_statuses (
            business_id, code, name, color_hex, icon_key, sort_order
          ) VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [
            businessId,
            code,
            status['name']?.toString() ?? code,
            _text(status['color_hex']),
            _text(status['icon_key']),
            _int(status['sort_order']) ?? 0,
          ],
        );
      }
    });
  }

  Future<void> applyServerListDecorations(
    String businessId,
    List<Map<String, dynamic>> jobs,
  ) async {
    await _database.transaction(() async {
      for (final job in jobs) {
        final id = job['id']?.toString() ?? '';
        if (id.isEmpty ||
            await LocalJobRetirement.isJobBlocked(_database, businessId, id)) {
          continue;
        }
        await _database.customStatement(
          '''
          UPDATE local_jobs
          SET pending_request_count = ?,
              payment_state = ?
          WHERE business_id = ? AND id = ?
          ''',
          [
            _int(job['pending_requests']) ?? 0,
            _text(job['payment_state']),
            businessId,
            id,
          ],
        );
      }
    });
  }

  Future<LocalJobDetailSnapshot?> jobDetail(
    String businessId,
    String jobId,
  ) async {
    if (await LocalJobRetirement.isJobBlocked(_database, businessId, jobId)) {
      return null;
    }
    final jobRows = await _database
        .customSelect(
          '''
      SELECT *
      FROM local_jobs
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    if (jobRows.isEmpty) return null;
    final row = jobRows.first;

    final assignmentRows = await _database
        .customSelect(
          '''
      SELECT *
      FROM local_job_assignments
      WHERE business_id = ? AND job_id = ? AND active = 1
      ORDER BY assigned_at, assignment_id
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    final assignments = assignmentRows
        .map(
          (assignment) => <String, dynamic>{
            'assignment_id': assignment.read<String>('assignment_id'),
            'employee_id': assignment.read<String>('employee_id'),
            'employee_name': assignment.readNullable<String>('employee_name'),
            'position': assignment.readNullable<String>('position'),
            'assigned_at': _isoFromDb(assignment.data['assigned_at']),
            'released_at': _isoFromDb(assignment.data['released_at']),
            'source': assignment.readNullable<String>('source'),
          },
        )
        .toList();

    final visitRows = await _database
        .customSelect(
          '''
      SELECT *
      FROM local_job_visits
      WHERE business_id = ? AND job_id = ?
      ORDER BY visit_number DESC, opened_at DESC, id
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    final visits = visitRows
        .map(
          (visit) => <String, dynamic>{
            'id': visit.read<String>('id'),
            'visit_number': visit.read<int>('visit_number'),
            'reason': visit.readNullable<String>('reason'),
            'planned_hours': visit.data['planned_hours'],
            'work_summary': visit.readNullable<String>('work_summary'),
            'opened_at': _isoFromDb(visit.data['opened_at']),
            'closed_at': _isoFromDb(visit.data['closed_at']),
            'updated_at': _isoFromDb(visit.data['server_updated_at']),
            'row_version': visit.readNullable<int>('row_version'),
            'sync_state': visit.read<String>('sync_state'),
            'mechanics': const <dynamic>[],
          },
        )
        .toList();

    final vehicleId = row.readNullable<String>('vehicle_id');
    final capabilities = _jsonMap(row.read<String>('capabilities_json'));

    final job = <String, dynamic>{
      'id': row.read<String>('id'),
      'job_number': row.readNullable<String>('job_number'),
      'title': row.read<String>('title'),
      'requested_work': row.readNullable<String>('requested_work'),
      'status': row.read<String>('status'),
      'status_name': row.readNullable<String>('status_name'),
      'status_color': row.readNullable<String>('status_color'),
      'status_icon': row.readNullable<String>('status_icon'),
      'planned_hours': row.data['planned_hours'],
      'odometer_in': row.data['odometer_in'],
      'created_at': _isoFromDb(row.data['created_at']),
      'completed_at': _isoFromDb(row.data['completed_at']),
      'updated_at': _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'customer_id': row.readNullable<String>('customer_id'),
      'customer_name': row.readNullable<String>('customer_name'),
      'customer_problem_flag': row.read<int>('customer_problem_flag') == 1,
      'customer_problem_flag_note': row.readNullable<String>(
        'customer_problem_flag_note',
      ),
      'vehicle_id': vehicleId,
      'vehicle': row.readNullable<String>('vehicle_label'),
      'vehicle_vin': row.readNullable<String>('vehicle_vin'),
      'vehicle_plate': row.readNullable<String>('vehicle_plate'),
      'is_unassigned': row.read<int>('is_unassigned') == 1,
      'capabilities': capabilities,
      'assignments': assignments,
      'pending_requests': const <dynamic>[],
      'visits': visits,
      'status_history': const <dynamic>[],
      '_local_snapshot': true,
    };

    final preInspection = await _preInspection(businessId, jobId);
    final findings = vehicleId == null
        ? <Map<String, dynamic>>[]
        : await _findings(businessId, vehicleId);
    final statuses = await jobStatuses(businessId);

    // A retirement observed while assembling nested rows also hides this load.
    if (await LocalJobRetirement.isJobBlocked(_database, businessId, jobId)) {
      return null;
    }
    return LocalJobDetailSnapshot(
      job: job,
      preInspection: preInspection,
      findings: findings,
      statuses: statuses,
    );
  }

  Map<String, dynamic> _jobListMap(QueryRow row) {
    final capabilities = _jsonMap(row.read<String>('capabilities_json'));
    return <String, dynamic>{
      'id': row.read<String>('id'),
      'job_number': row.readNullable<String>('job_number'),
      'title': row.read<String>('title'),
      'requested_work': row.readNullable<String>('requested_work'),
      'status': row.read<String>('status'),
      'status_name': row.readNullable<String>('status_name'),
      'status_color': row.readNullable<String>('status_color'),
      'status_icon': row.readNullable<String>('status_icon'),
      'customer_name': row.readNullable<String>('customer_name'),
      'vehicle': row.readNullable<String>('vehicle_label'),
      'planned_hours': row.data['planned_hours'],
      'assigned_employee': row.readNullable<String>('assigned_employee_name'),
      'assigned_employee_id': row.readNullable<String>('assigned_employee_id'),
      'assigned_position': row.readNullable<String>('assigned_position'),
      'open_findings': row.read<int>('open_findings'),
      'pending_requests': row.read<int>('pending_request_count'),
      'can_request': capabilities['request_job'] == true,
      'created_at': _isoFromDb(row.data['created_at']),
      'completed_at': _isoFromDb(row.data['completed_at']),
      'payment_state': row.readNullable<String>('payment_state'),
      'updated_at': _isoFromDb(row.data['activity_at']),
      'job_date': row.data['job_date_at'] == 0
          ? null
          : _isoFromDb(row.data['job_date_at']),
      'last_accessed_at': row.data['last_accessed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('last_accessed_at'),
              isUtc: true,
            ).toIso8601String(),
      '_temporary':
          row.readNullable<String>('job_number') == 'Pending sync' ||
          (row.readNullable<String>('job_number') ?? '')
              .toUpperCase()
              .startsWith('TEMP-'),
      '_local_snapshot': true,
    };
  }

  Future<Map<String, dynamic>?> _preInspection(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT *
      FROM local_pre_inspections
      WHERE business_id = ? AND job_id = ?
      LIMIT 1
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    if (rows.isEmpty) return null;
    final row = rows.first;
    final inspectionId = row.read<String>('id');

    final photoRows = await _database
        .customSelect(
          '''
      SELECT *
      FROM local_pre_inspection_photos
      WHERE business_id = ? AND inspection_id = ?
      ORDER BY captured_at, id
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(inspectionId),
          ],
        )
        .get();

    return <String, dynamic>{
      'id': inspectionId,
      'job_id': jobId,
      'vehicle_id': row.readNullable<String>('vehicle_id'),
      'inspected_at': _isoFromDb(row.data['inspected_at']),
      'odometer': row.data['odometer'],
      'notes': row.readNullable<String>('notes'),
      'created_by': row.readNullable<String>('created_by'),
      'updated_at': _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
      'photos': photoRows
          .map(
            (photo) => <String, dynamic>{
              'id': photo.read<String>('id'),
              'attachment_id': photo.read<String>('attachment_id'),
              'filename': photo.readNullable<String>('filename'),
              'bucket': photo.readNullable<String>('storage_bucket'),
              'key': photo.readNullable<String>('storage_key'),
              'mime_type': photo.readNullable<String>('mime_type'),
              'byte_size': photo.readNullable<int>('byte_size'),
              'captured_at': _isoFromDb(photo.data['captured_at']),
              'note': photo.readNullable<String>('note'),
              'created_by': photo.readNullable<String>('created_by'),
              'can_edit_note': photo.read<int>('can_edit_note') == 1,
              'can_delete': false,
              'local_file_path': photo.readNullable<String>('local_file_path'),
              'upload_state': photo.read<String>('upload_state'),
              'last_error': photo.readNullable<String>('last_error'),
            },
          )
          .toList(),
    };
  }

  Future<List<Map<String, dynamic>>> _findings(
    String businessId,
    String vehicleId,
  ) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT *
      FROM local_findings
      WHERE business_id = ? AND vehicle_id = ?
      ORDER BY
        CASE status
          WHEN 'open' THEN 0
          WHEN 'in_job' THEN 1
          ELSE 2
        END,
        created_at DESC,
        id
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(vehicleId),
          ],
        )
        .get();

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final findingId = row.read<String>('id');
      final photoRows = await _database
          .customSelect(
            '''
        SELECT *
        FROM local_finding_photos
        WHERE business_id = ? AND finding_id = ?
        ORDER BY captured_at, id
        ''',
            variables: [
              Variable<String>(businessId),
              Variable<String>(findingId),
            ],
          )
          .get();

      result.add(<String, dynamic>{
        'id': findingId,
        'body': row.read<String>('body'),
        'status': row.read<String>('status'),
        'include_on_invoice': row.read<int>('include_on_invoice') == 1,
        'created_at': _isoFromDb(row.data['created_at']),
        'resolved_at': _isoFromDb(row.data['resolved_at']),
        'updated_at': _isoFromDb(row.data['server_updated_at']),
        'row_version': row.readNullable<int>('row_version'),
        'created_by': row.readNullable<String>('created_by'),
        'vehicle_id': row.readNullable<String>('vehicle_id'),
        'found_job_id': row.readNullable<String>('found_job_id'),
        'repair_job_id': row.readNullable<String>('repair_job_id'),
        'can_edit': row.read<int>('can_edit') == 1,
        'can_delete': false,
        'sync_state': row.read<String>('sync_state'),
        'attachments': photoRows
            .map(
              (photo) => <String, dynamic>{
                'id': photo.read<String>('id'),
                'attachment_id': photo.read<String>('attachment_id'),
                'bucket': photo.readNullable<String>('storage_bucket'),
                'key': photo.readNullable<String>('storage_key'),
                'filename': photo.readNullable<String>('filename'),
                'mime_type': photo.readNullable<String>('mime_type'),
                'byte_size': photo.readNullable<int>('byte_size'),
                'captured_at': _isoFromDb(photo.data['captured_at']),
                'can_delete': false,
                'local_file_path': photo.readNullable<String>(
                  'local_file_path',
                ),
                'upload_state': photo.read<String>('upload_state'),
                'last_error': photo.readNullable<String>('last_error'),
              },
            )
            .toList(),
      });
    }

    return result;
  }

  Map<String, dynamic> _jsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  int? _int(Object? value) => int.tryParse(value?.toString() ?? '');

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  String? _isoFromDb(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return DateTime.tryParse(value.toString())?.toUtc().toIso8601String();
  }
}

