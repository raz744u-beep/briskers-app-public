import 'package:briskers_app/services/customer_note_cache_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Remote refresh preserves pending body edits and staged photos', () {
    final remote = <Map<String, dynamic>>[
      {'id': 'note-1', 'body': 'Old server text',
        'attachments': [{'attachment_id': 'server-photo',
                         'key':'server.jpg'}]},
      {'id': 'note-2', 'body': 'Current remote text'},
    ];
    final local = <Map<String, dynamic>>[
      {'id':'note-1', 'body':'Corrected local text',
        'sync_state':'pending',
        'attachments':[
          {'attachment_id':'local-photo','local_file_path':'/test/staged.jpg',
           'upload_state':'pending'}]},
      {'id':'note-2', 'body':'Stale local text', 'sync_state':'synced'},
      {'id':'local-note-3', 'body':'Draft', 'sync_state':'pending'},
      {'id':'deleted-server-note','body':'Clean orphan','sync_state':'synced'},
    ];
    final merged = mergeCustomerNotesPreservingPending(remote, local);
    expect(merged.length, 3);
    expect(merged.first['id'], 'local-note-3');
    final first = merged.firstWhere((n)=>n['id']=='note-1');
    expect(first['body'], 'Corrected local text');
    final images = List<dynamic>.from(first['attachments'] as List);
    expect(images.length, 2);
    expect(images.any((p)=>(p as Map)['attachment_id']=='local-photo'), true);
    expect(images.any((p)=>(p as Map)['attachment_id']=='server-photo'), true);
    expect(merged.firstWhere((n)=>n['id']=='note-2')['body'],
        'Current remote text');
    expect(merged.any((n)=>n['id']=='deleted-server-note'), false);
  });

  test('Pending photo on synced note keeps local attachment on refresh', () {
    final cached = <Map<String,dynamic>>[
      {'id':'note-4', 'body':'Not edited',
        'attachments':[{'id':'pending-photo','upload_state':'pending',
          'local_file_path':'/test/pending'}]},
    ];
    final merged = mergeCustomerNotesPreservingPending(
      <Map<String,dynamic>>[{'id':'note-4','body':'Not edited'}],
      cached);
    final attachments = merged.single['attachments'] as List;
    expect((attachments.single as Map)['id'],'pending-photo');
  });
}
