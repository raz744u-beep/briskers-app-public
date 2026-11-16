import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_document_detail_cache.dart';
import 'local_number_allocator.dart';
import 'local_owner_authorization.dart';

class LocalInvoiceNumberService {
  LocalInvoiceNumberService(this.db);
  final BriskersLocalDatabase db;
  Future<void> assign(String business,String invoice,int number,LocalOwnerGrant grant) async {
    grant.assertValid(business,grant.actorId);
    await db.transaction(() async {
      grant.assertValid(business,grant.actorId);
      final rows=await db.customSelect("SELECT id,document_number FROM local_documents WHERE business_id=? AND id=? AND kind='invoice'",
        variables:[Variable<String>(business),Variable<String>(invoice)]).get();
      if(rows.length!=1) throw StateError('Invoice is not present locally.');
      final allocator=LocalNumberAllocator(db);
      // A failed assignment rolls back the old reservation as well.
      await allocator.release(business,'invoice',invoice,previousNumber:rows.single.data['document_number']);
      await allocator.allocate(business,'invoice',invoice,requested:number);
      await db.customStatement('UPDATE local_documents SET document_number=? WHERE business_id=? AND id=?',
        ['$number',business,invoice]);
      final cache=LocalDocumentDetailCache(database:db);
      final detail=await cache.load(business,invoice);
      if(detail!=null) await cache.save(business,invoice,{...detail,'document_number':'$number'});
      final queued=await db.customSelect("SELECT id,payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type='document_draft_create'",
        variables:[Variable<String>(business),Variable<String>(invoice)]).get();
      for(final row in queued) {
        final payload=Map<String,dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map);
        payload['local_document_number']='$number';
        await db.customStatement('UPDATE sync_outbox SET payload_json=? WHERE id=?',[jsonEncode(payload),row.read<int>('id')]);
      }
      grant.assertValid(business,grant.actorId);
    });
    db.notifyUpdates({const TableUpdate('local_documents')});
  }
}
