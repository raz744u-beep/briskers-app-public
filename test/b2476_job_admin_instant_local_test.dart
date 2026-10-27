import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mechanic and hours commit locally in same retryable outbox operation',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await db.customStatement(
        """INSERT INTO local_jobs
          (id, business_id, access_scope, job_number, title, status,
           created_at, sync_state)
          VALUES (?, ?, 'all', ?, ?, 'open', ?, 'synced')""",
        ['fixture-j', 'shop', 'J-6', 'Synthetic repair', 100],
      );
      final offline = OfflineJobAdminService(database: db);
      await offline.queueAssignment(
        'shop', 'fixture-j',
        employeeId: 'fixture-mechanic', employeeName: 'Synthetic Kam',
        position: 'Mechanic',
      );
      var stored = await db.customSelect(
        'SELECT assigned_employee_id, assigned_employee_name, sync_state '
        'FROM local_jobs WHERE business_id = ? AND id = ?',
        variables: [
          const Variable<String>('shop'),
          const Variable<String>('fixture-j'),
        ],
      ).getSingle();
      expect(stored.readNullable<String>('assigned_employee_id'),
          'fixture-mechanic');
      expect(stored.readNullable<String>('assigned_employee_name'),
          'Synthetic Kam');
      expect(stored.read<String>('sync_state'), 'pending');

      await offline.queuePlannedHours('shop', 'fixture-j', 3.5);
      stored = await db.customSelect(
        'SELECT planned_hours, assigned_employee_id, sync_state '
        'FROM local_jobs WHERE business_id = ? AND id = ?',
        variables: [
          const Variable<String>('shop'),
          const Variable<String>('fixture-j'),
        ],
      ).getSingle();
      expect((stored.data['planned_hours'] as num).toDouble(), 3.5);
      expect(stored.readNullable<String>('assigned_employee_id'),
          'fixture-mechanic');

      final queued = await db.customSelect(
        "SELECT payload_json FROM sync_outbox WHERE business_id = ? "
        "AND entity_id = ? AND entity_type = 'job_admin' AND state = 'pending'",
        variables: [
          const Variable<String>('shop'),
          const Variable<String>('fixture-j'),
        ],
      ).get();
      expect(queued, hasLength(1),
          reason: 'Rapid edits must merge into one durable replay');
      final payload = Map<String, dynamic>.from(
        jsonDecode(queued.single.read<String>('payload_json')) as Map);
      expect(payload['assignment_changed'], true);
      expect(payload['employee_id'], 'fixture-mechanic');
      expect(payload['core_changed'], true);
      expect((payload['planned_hours'] as num).toDouble(), 3.5);
    } finally {
      await db.close();
    }
  });

  test('Job Detail assignment and hours never await RPC/full rehydration',
      () {
    final src =
        File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final hours = src.substring(
      src.indexOf('Future<void> _changePlannedHours() async {'),
      src.indexOf('Future<String?> _editTextSheet(', 
        src.indexOf('Future<void> _changePlannedHours() async {')),
    );
    final picker = src.substring(
      src.indexOf('Future<void> _changeAssignment() async {'),
      src.indexOf('Future<void> _requestJob() async {'),
    );
    for (final action in [hours, picker]) {
      expect(action, contains('await _offlineJobAdmin.queue'));
      expect(action, contains('_scheduleJobAdminSync();'));
      expect(action, isNot(contains('await _offlineJobAdmin.flush(')));
      expect(action, isNot(contains('await _load();')));
      expect(action, contains('++_loadEpoch;'),
          reason: 'Stale server response may not overwrite local edit');
    }
    expect(picker, isNot(contains('await _offlineJobAdmin.refreshEmployees(')));
    expect(picker, contains('unawaited(_offlineJobAdmin.refreshEmployees('));
    expect(hours, contains("'planned_hours': value"));
    expect(picker, contains("'assignments': assigned"));
  });

  test('Jobs list quick editors patch visible cards without querying all Jobs',
      () {
    final src = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(src, contains('void _patchQuickAdminCard('));
    final a = src.indexOf('Future<void> _quickEditMechanic(');
    final b = src.indexOf('Future<void> _quickEditPlannedTime(', a);
    final c = src.indexOf('void _applyLocalStatus(', b);
    final mechanic = src.substring(a, b);
    final hours = src.substring(b, c);
    for (final flow in [mechanic, hours]) {
      expect(flow, contains('_patchQuickAdminCard('));
      expect(flow, contains('_scheduleQuickEditSync();'));
      expect(flow, isNot(contains('await _load(refreshRemote: false);')));
      expect(flow, isNot(contains('await _offlineJobAdmin.flush(')));
    }
  });
}
