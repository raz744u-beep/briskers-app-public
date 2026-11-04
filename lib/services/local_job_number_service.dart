import 'dart:convert';
import 'package:drift/drift.dart' show TableUpdate, Variable;
import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import 'local_number_allocator.dart';
import 'local_owner_authorization.dart';

/// Renumbers the existing, unsent job linked to an invoice. No record relinking,
/// customer edits, payment edits or network calls.
class LocalJobNumberService {
  LocalJobNumberService(this.db, {bool Function()? forceOffline})
      : _forceOffline = forceOffline ??
          (() => BriskersConnectionModeController.instance.forceOffline);
  final BriskersLocalDatabase db;
  final bool Function() _forceOffline;

  static int parse(String input) {
    final value = input.trim().toUpperCase().replaceFirst(RegExp(r'^J-?'), '');
    final number = RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null;
    if (number == null || number < 1 || number > 999999999) {
      throw StateError('Enter a job number from 1 to 999,999,999, such as J-34.');
    }
    return number;
  }

  Future<void> assign(String business, String invoice, String expectedJob,
      int number, LocalOwnerGrant grant) async {
    void check() {
      grant.assertValid(business, grant.actorId);
      if (!_forceOffline()) {
        throw StateError('Keep Force Offline enabled while changing a local job number.');
      }
    }
    check();
    await db.transaction(() async {
      check();
      final rows = await db.customSelect(
        "SELECT j.id,j.job_number,j.sync_state AS job_state,d.sync_state AS doc_state "
        "FROM local_documents d JOIN local_jobs j "
        "ON j.business_id=d.business_id AND j.id=d.job_id "
        "WHERE d.business_id=? AND d.id=? AND d.kind='invoice'",
        variables: [Variable<String>(business), Variable<String>(invoice)],
      ).get();
      if (rows.length != 1 || rows.single.read<String>('id') != expectedJob) {
        throw StateError('The invoice job changed. Reopen the invoice and try again.');
      }
      final job = rows.single;
      if (job.read<String>('job_state') != 'pending' ||
          job.read<String>('doc_state') != 'pending') {
        throw StateError('This option is for an invoice and job still saved locally.');
      }
      final creates = await db.customSelect(
        "SELECT id,entity_type,entity_id,payload_json,state,attempt_count "
        "FROM sync_outbox WHERE business_id=? AND "
        "((entity_type='job_create' AND entity_id=?) OR "
        "(entity_type='document_draft_create' AND entity_id IN "
        "(SELECT id FROM local_documents WHERE business_id=? AND job_id=?)))",
        variables: [Variable<String>(business), Variable<String>(expectedJob),
          Variable<String>(business), Variable<String>(expectedJob)],
      ).get();
      final changes = <int, Map<String, dynamic>>{};
      var ownsJobCreation = false;
      for (final row in creates) {
        if (row.read<int>('attempt_count') != 0 ||
            !['pending', 'conflict'].contains(row.read<String>('state'))) {
          throw StateError('This job may already have been uploaded. Its number was not changed.');
        }
        final payload = Map<String, dynamic>.from(
            jsonDecode(row.read<String>('payload_json')) as Map);
        final jobCreate = row.read<String>('entity_type') == 'job_create';
        if (jobCreate || payload['provisional_job_id'] == expectedJob) {
          ownsJobCreation = true;
          payload['local_job_number'] = 'J-$number';
          // Existing draft replay already defers locally numbered documents.
          if (!jobCreate && payload['local_document_number'] == null) {
            throw StateError('The local invoice number must be assigned first.');
          }
          changes[row.read<int>('id')] = payload;
        }
      }
      if (!ownsJobCreation) {
        throw StateError('The original unsent job creation is not available locally.');
      }
      final allocator = LocalNumberAllocator(db);
      await allocator.release(business, 'job', expectedJob,
          previousNumber: job.data['job_number']);
      await allocator.allocate(business, 'job', expectedJob, requested: number);
      await db.customStatement(
        'UPDATE local_jobs SET job_number=? WHERE business_id=? AND id=?',
        ['J-$number', business, expectedJob],
      );
      for (final entry in changes.entries) {
        await db.customStatement(
          'UPDATE sync_outbox SET payload_json=? WHERE business_id=? AND id=?',
          [jsonEncode(entry.value), business, entry.key],
        );
      }
      check();
    });
    db.notifyUpdates({const TableUpdate('local_jobs'),
      const TableUpdate('local_documents')});
  }
}
