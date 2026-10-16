import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/work_finding_merge.dart';

Map<String, dynamic> finding(String id, {int? version = 1}) => {
  'id': id,
  'body': 'Finding note',
  'row_version': version,
  'sync_state': 'synced',
  'status': 'open',
  'repair_job_id': null,
  'attachments': <Map<String, dynamic>>[],
};

Map<String, dynamic> photo(String id, {bool pending = false}) => {
  'attachment_id': id,
  'upload_state': pending ? 'pending' : 'synced',
  if (pending) 'local_file_path': '/offline/$id.jpg',
};

void main() {
  test('refresh removes remapped finding and photo placeholders repeatedly', () {
    final original = finding('local-finding-create-1', version: null)
      ..['sync_state'] = 'pending'
      ..['attachments'] = [photo('local-finding-photo-1', pending: true)];
    final synced = finding('server-finding-1')
      ..['attachments'] = [photo('server-photo-1')];
    var display = [original];
    for (var retry = 0; retry < 5; retry++) {
      display = mergeWorkFindings(display, [synced]);
      expect(display, hasLength(1));
      expect(display.single['id'], 'server-finding-1');
      expect(display.single['attachments'], [photo('server-photo-1')]);
    }
  });

  test('newer repair state and photos survive pending edits and refreshes', () {
    final local = finding('finding-1')
      ..['body'] = 'Offline mechanic note'
      ..['sync_state'] = 'pending'
      ..['attachments'] = [photo('local-finding-photo-1', pending: true)];
    final server = finding('finding-1', version: 2)
      ..['status'] = 'in_job'
      ..['repair_job_id'] = 'job-12'
      ..['repair_job_number'] = 'J12'
      ..['attachments'] = [photo('server-photo-1')];
    var display = [server];
    for (var retry = 0; retry < 5; retry++) {
      display = mergeWorkFindings(display, [local]);
      expect(display.single['body'], 'Offline mechanic note');
      expect(display.single['sync_state'], 'pending');
      expect(display.single['status'], 'in_job');
      expect(display.single['repair_job_id'], 'job-12');
      expect(display.single['repair_job_number'], 'J12');
      expect(display.single['attachments'], hasLength(2));
    }
    expect(local['status'], 'open');
    expect(server['attachments'], hasLength(1));
  });

  test('newer server repair state overrides an older clean cached row', () {
    final local = finding('finding-1');
    final server = finding('finding-1', version: 2)
      ..['status'] = 'resolved'
      ..['repair_job_id'] = 'job-12'
      ..['resolved_at'] = '2026-10-13T00:00:00Z';
    final merged = mergeWorkFindings([server], [local]).single;
    expect(merged['status'], 'resolved');
    expect(merged['repair_job_id'], 'job-12');
    expect(merged['resolved_at'], '2026-10-13T00:00:00Z');
  });

  test('older server snapshot cannot replace an acknowledged local edit', () {
    final local = finding('finding-1', version: 3)
      ..['body'] = 'Acknowledged latest note'
      ..['attachments'] = [photo('latest-photo')];
    final server = finding('finding-1', version: 2);
    final merged = mergeWorkFindings([server], [local]).single;
    expect(merged['body'], 'Acknowledged latest note');
    expect(merged['attachments'], [photo('latest-photo')]);
  });

  test('current local photo ID replaces stale displayed placeholder', () {
    final display = finding('finding-1')
      ..['attachments'] = [photo('local-finding-photo-1', pending: true)];
    final local = finding('finding-1')
      ..['attachments'] = [photo('photo-server-1')];
    final merged = mergeWorkFindings([display], [local]);
    expect(merged.single['attachments'], [photo('photo-server-1')]);
  });

  test('photo remap survives a display with newer repair metadata', () {
    final display = finding('finding-1', version: 2)
      ..['status'] = 'in_job'
      ..['repair_job_id'] = 'job-12'
      ..['attachments'] = [
        photo('remote-photo'),
        photo('local-finding-photo-1', pending: true),
      ];
    final uploaded = photo('photo-server-1')
      ..['local_file_path'] = '/offline/saved.jpg';
    final local = finding('finding-1')
      ..['sync_state'] = 'conflict'
      ..['attachments'] = [photo('remote-photo'), uploaded];
    var merged = [display];
    for (var refresh = 0; refresh < 3; refresh++) {
      merged = mergeWorkFindings(merged, [local]);
      expect(merged.single['repair_job_id'], 'job-12');
      expect(merged.single['attachments'], [photo('remote-photo'), uploaded]);
    }
  });

  test('conflicts preserve notes and photos and input duplicates do not multiply', () {
    final local = finding('finding-1')
      ..['body'] = 'Preserved conflict note'
      ..['sync_state'] = 'conflict'
      ..['attachments'] = [photo('local-finding-photo-1', pending: true)];
    final remote = finding('finding-1', version: 4);
    final other = finding('finding-2');
    final merged = mergeWorkFindings([remote, other, other], [local, local]);
    expect(merged, hasLength(2));
    expect(merged.first['body'], 'Preserved conflict note');
    expect(merged.first['sync_state'], 'conflict');
    expect(merged.first['attachments'], hasLength(1));
  });
}
