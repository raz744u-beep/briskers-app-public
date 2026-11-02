import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/invoice_finalization_guard.dart';
import 'package:briskers_app/services/owner_invoice_auto_close_service.dart';
import 'package:briskers_app/services/local_document_repository.dart';

class _Api extends BriskersApi {
  Map<String,dynamic> job = {'status':'completed'};
  final entries = <String,Map<String,dynamic>>{};
  final closed = <String>[];
  @override
  Future<Map<String,dynamic>> jobDetail(String businessId,String jobId) async =>
    job;
  @override
  Future<List<Map<String,dynamic>>> jobDocuments(
      String businessId,String jobId) async =>
      entries.keys.map((id) => {'id':id,'kind':'invoice'}).toList();
  @override
  Future<Map<String,dynamic>> documentDetail(
      String businessId,String documentId) async =>
      entries[documentId]!;
  @override
  Future<void> closeInvoice(String businessId,String invoiceId) async {
    closed.add(invoiceId);
  }
}
class _Guard extends InvoiceFinalizationGuard {
  _Guard(BriskersLocalDatabase database) : super(database:database);
  @override
  Future<T> run<T>({
    required String businessId,
    required Iterable<String> invoiceIds,
    required bool isOwner,
    required Future<T> Function() action,
  }) async {
    if (!isOwner) throw StateError('Owner required');
    return action();
  }
}
Map<String,dynamic> _invoice(String jobId,{
    num total=100,num paid=100,num pending=0,
    String status='issued'}) => {
  'kind':'invoice','job_id':jobId,'status':status,
  'total_amount':total,'paid_amount':paid,
  'pending_payment':pending,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('secretary cannot close any paid invoice',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_Api()..entries['inv'] = _invoice('job');
    final service=OwnerInvoiceAutoCloseService(
      api:api,guard:_Guard(db),
      localDocuments:LocalDocumentRepository(database:db));
    expect(await service.closeEligible(
      businessId:'shop',jobId:'job',isOwner:false),0);
    expect(api.closed,isEmpty);
    await db.close();
  });
  test('owner closes fully posted eligible invoices only',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_Api();
    api.entries.addAll({
      'paid':_invoice('job'),
      'advance':_invoice('job',paid:0,pending:100),
      'balance':_invoice('job',paid:90),
      'reopened':_invoice('job',status:'reopened'),
      'other-job':_invoice('different'),
    });
    final service=OwnerInvoiceAutoCloseService(
      api:api,guard:_Guard(db),
      localDocuments:LocalDocumentRepository(database:db));
    expect(await service.closeEligible(
      businessId:'shop',jobId:'job',isOwner:true),1);
    expect(api.closed,['paid']);
    await db.close();
  });
  test('job still under repair never triggers closeout',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_Api()..entries['paid']=_invoice('job');
    api.job={'status':'in_progress'};
    expect(await OwnerInvoiceAutoCloseService(
      api:api,guard:_Guard(db),
      localDocuments:LocalDocumentRepository(database:db))
        .closeEligible(businessId:'shop',jobId:'job',isOwner:true),0);
    expect(api.closed,isEmpty);
    await db.close();
  });
}
