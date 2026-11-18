import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'job_status_local_events.dart';

/// Durable task activity and explicit status intent, independent of sync state.
class LocalJobWorkState {
  LocalJobWorkState(this.db);
  final BriskersLocalDatabase db;
  static final _observers = Expando<StreamSubscription<List<QueryRow>>>();
  static const terminal = {
    'complete',
    'completed',
    'closed',
    'cancelled',
    'canceled',
    'deleted',
  };

  Future<void> prepare() async {
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_task_activity_v1 (
      business_id TEXT NOT NULL,job_id TEXT NOT NULL,allocation_id TEXT NOT NULL,
      revision INTEGER NOT NULL,state TEXT NOT NULL,started INTEGER NOT NULL,
      PRIMARY KEY(business_id,allocation_id))''',
    );
    await db.customStatement(
      '''CREATE INDEX IF NOT EXISTS local_job_task_activity_job
      ON local_job_task_activity_v1(business_id,job_id)''',
    );
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_status_intent_v1 (
      business_id TEXT NOT NULL,job_id TEXT NOT NULL,code TEXT NOT NULL,
      origin TEXT NOT NULL,revision INTEGER NOT NULL,recorded_at INTEGER NOT NULL,
      PRIMARY KEY(business_id,job_id))''',
    );
  }

  Future<bool> record(
    String business,
    String job,
    String allocation,
    int revision,
    String state, {
    required String previousState,
    required bool history,
  }) async {
    await prepare();
    final changed = await db.customUpdate(
      '''INSERT INTO local_job_task_activity_v1 VALUES(?,?,?,?,?,?)
      ON CONFLICT(business_id,allocation_id) DO UPDATE SET
        job_id=excluded.job_id,revision=excluded.revision,state=excluded.state,
        started=MAX(local_job_task_activity_v1.started,excluded.started)
      WHERE excluded.revision>local_job_task_activity_v1.revision''',
      variables: [
        Variable(business),
        Variable(job),
        Variable(allocation),
        Variable(revision),
        Variable(state),
        Variable(state != 'Open' || previousState != 'Open' ? 1 : 0),
      ],
    );
    if (changed > 0) db.notifyUpdates({const TableUpdate('local_jobs')});
    final intent = await db
        .customSelect(
          '''SELECT code,origin FROM local_job_status_intent_v1
      WHERE business_id=? AND job_id=?''',
          variables: [Variable(business), Variable(job)],
        )
        .getSingleOrNull();
    // An explicit Open decision can describe a new visit or correct a bad
    // imported state. Old completed labor cannot undo that decision.
    if (intent?.data['code'] == 'open' && intent?.data['origin'] == 'owner') {
      return !history && state != 'Open' && previousState != state;
    }
    final started = await db
        .customSelect(
          '''SELECT 1 FROM local_job_task_activity_v1
      WHERE business_id=? AND job_id=? AND started=1 LIMIT 1''',
          variables: [Variable(business), Variable(job)],
        )
        .getSingleOrNull();
    return started != null;
  }

  Future<void> saveIntent(
    String business,
    String job,
    String code, {
    required bool fromTask,
  }) async {
    await prepare();
    await db.customStatement(
      '''INSERT INTO local_job_status_intent_v1 VALUES(?,?,?,?,1,?)
      ON CONFLICT(business_id,job_id) DO UPDATE SET code=excluded.code,origin=excluded.origin,
        revision=local_job_status_intent_v1.revision+1,recorded_at=excluded.recorded_at''',
      [
        business,
        job,
        code,
        fromTask ? 'task' : 'owner',
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  static String retainedSql(String business, String id) =>
      '''(
    EXISTS(SELECT 1 FROM local_job_status_intent_v1 w WHERE w.business_id=$business AND w.job_id=$id)
    OR EXISTS(SELECT 1 FROM local_job_task_activity_v1 w WHERE w.business_id=$business AND w.job_id=$id))''';

  Future<Set<String>> retainedJobIds(String business) async {
    await prepare();
    return (await db
            .customSelect(
              'SELECT job_id FROM local_job_status_intent_v1 WHERE business_id=? UNION SELECT job_id FROM local_job_task_activity_v1 WHERE business_id=?',
              variables: [Variable(business), Variable(business)],
            )
            .get())
        .map((r) => r.read<String>('job_id'))
        .toSet();
  }

  Future<void> remap(String business, String oldId, String newId) async {
    await prepare();
    await db.customStatement(
      'UPDATE local_job_task_activity_v1 SET job_id=? WHERE business_id=? AND job_id=?',
      [newId, business, oldId],
    );
    await db.customStatement(
      '''INSERT INTO local_job_status_intent_v1
      SELECT business_id,?,code,origin,revision,recorded_at FROM local_job_status_intent_v1 WHERE business_id=? AND job_id=?
      ON CONFLICT(business_id,job_id) DO UPDATE SET code=excluded.code,origin=excluded.origin,revision=excluded.revision,recorded_at=excluded.recorded_at
      WHERE excluded.recorded_at>local_job_status_intent_v1.recorded_at''',
      [newId, business, oldId],
    );
    await db.customStatement(
      'DELETE FROM local_job_status_intent_v1 WHERE business_id=? AND job_id=?',
      [business, oldId],
    );
  }

  /// Drift invalidates this query after the outermost transaction commits.
  /// Bulk changes and rolled-back changes therefore produce no partial cards.
  static Future<StreamSubscription<List<QueryRow>>> observe(
    BriskersLocalDatabase db,
  ) async {
    final existing = _observers[db];
    if (existing != null) return existing;
    await LocalJobWorkState(db).prepare();
    final ready = Completer<void>();
    var prior = <String, String>{};
    final subscription = db
        .customSelect(
          '''SELECT j.business_id,j.id,j.status,j.status_name,
      j.status_color,j.status_icon,COALESCE(i.revision,0) AS intent_revision,
      COALESCE((SELECT SUM(a.revision+1) FROM local_job_task_activity_v1 a
        WHERE a.business_id=j.business_id AND a.job_id=j.id),0) AS task_revision
      FROM local_jobs j LEFT JOIN local_job_status_intent_v1 i
        ON i.business_id=j.business_id AND i.job_id=j.id
      WHERE i.job_id IS NOT NULL OR EXISTS(SELECT 1 FROM local_job_task_activity_v1 a
        WHERE a.business_id=j.business_id AND a.job_id=j.id)''',
          readsFrom: {db.localJobs},
        )
        .watch()
        .listen(
          (rows) {
            final next = <String, String>{};
            for (final row in rows) {
              final business = row.read<String>('business_id'),
                  job = row.read<String>('id');
              final key = jsonEncode([business, job]);
              final version = jsonEncode([
                row.data['status'],
                row.data['intent_revision'],
                row.data['task_revision'],
              ]);
              next[key] = version;
              if (ready.isCompleted && prior[key] != version) {
                LocalJobStatusEvents.committed(
                  LocalJobStatusChanged(
                    businessId: business,
                    jobId: job,
                    code: row.read<String>('status'),
                    name:
                        row.readNullable<String>('status_name') ??
                        row.read<String>('status'),
                    colorHex: row.readNullable<String>('status_color'),
                    iconKey: row.readNullable<String>('status_icon'),
                  ),
                );
              }
            }
            prior = next;
            if (!ready.isCompleted) ready.complete();
          },
          onError: (Object error, StackTrace stack) {
            if (!ready.isCompleted) ready.completeError(error, stack);
          },
        );
    _observers[db] = subscription;
    await ready.future;
    return subscription;
  }

  static bool observed(BriskersLocalDatabase db) => _observers[db] != null;

  /// Protect local intent from old or unversioned history snapshots. A later
  /// version with a later server timestamp can still carry a new Owner decision.
  Future<Map<String, dynamic>> projectStatus(
    String business,
    Map<String, dynamic> remote,
    Map<String, dynamic> local, {
    required bool pending,
  }) async {
    await prepare();
    final id = local['id'] as String;
    final intent = await db
        .customSelect(
          'SELECT * FROM local_job_status_intent_v1 WHERE business_id=? AND job_id=?',
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    final started = await db
        .customSelect(
          'SELECT 1 FROM local_job_task_activity_v1 WHERE business_id=? AND job_id=? AND started=1 LIMIT 1',
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    final code = '${local['status']}'.toLowerCase();
    final incoming = '${remote['status']}'.toLowerCase();
    final localVersion = num.tryParse('${local['row_version']}');
    final remoteVersion = num.tryParse('${remote['row_version']}');
    final remoteTime = DateTime.tryParse('${remote['updated_at']}')
        ?.millisecondsSinceEpoch;
    final localTime =
        intent?.read<int>('recorded_at') ??
        (local['server_updated_at'] is int
            ? (local['server_updated_at'] as int) * 1000
            : null);
    final newer =
        localVersion != null &&
        remoteVersion != null &&
        remoteVersion > localVersion &&
        remoteTime != null &&
        localTime != null &&
        remoteTime > localTime;
    // An acknowledged matching completion may normalize its server date. It
    // cannot regress the lifecycle, and a missing date cannot erase history.
    if (!pending &&
        code == incoming &&
        const {'completed', 'closed'}.contains(code) &&
        remoteVersion != null &&
        localVersion != null &&
        remoteVersion > localVersion &&
        DateTime.tryParse('${remote['completed_at']}') != null)
      return remote;
    final protect =
        pending ||
        intent != null && !newer ||
        code == 'closed' && incoming != 'closed' ||
        terminal.contains(code) && !terminal.contains(incoming) ||
        code == 'in_progress' &&
            incoming == 'open' &&
            (started != null || intent != null) ||
        intent?.data['origin'] == 'owner' &&
            code == 'open' &&
            incoming == 'in_progress';
    if (!protect) return remote;
    return {
      ...remote,
      for (final field in [
        'status',
        'status_name',
        'status_color',
        'status_icon',
      ])
        field: local[field],
      'completed_at': local['completed_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              (local['completed_at'] as int) * 1000,
              isUtc: true,
            ).toIso8601String()
          : local['completed_at'],
      if (localVersion != null &&
          (remoteVersion == null || localVersion > remoteVersion))
        'row_version': local['row_version'],
      if (pending) '_local_status_pending': true,
    };
  }
}
