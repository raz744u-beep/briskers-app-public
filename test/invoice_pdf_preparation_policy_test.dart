import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/invoice_pdf_preparation_policy.dart';

void main() {
  test('numbered invoice does not reissue because local status says draft', () {
    expect(InvoicePdfPreparationPolicy.needsIssue({
      'kind':'invoice','status':'draft','document_number':'6340'
    }), isFalse);
    expect(InvoicePdfPreparationPolicy.needsIssue({
      'kind':'invoice','status':'draft','document_number':null
    }), isTrue);
    expect(InvoicePdfPreparationPolicy.needsIssue({
      'kind':'estimate','status':'issued','document_number':''
    }), isTrue);
  });

  test('Auto transport errors may offer a local copy only with exact identity', () {
    final valid = <String,dynamic>{
      'id':'invoice-id','kind':'invoice','document_number':'6340',
      'customer_id':'customer-id','vehicle_id':'vehicle-id',
      'lines':[{'name':'Water pump'}],
      'status':'issued'
    };
    expect(InvoicePdfPreparationPolicy.canOfferCachedPdf(valid),isTrue);
    expect(InvoicePdfPreparationPolicy.canOfferCachedPdf({...valid,'vehicle_id':null}),isFalse);
    expect(InvoicePdfPreparationPolicy.canOfferCachedPdf({...valid,'document_number':null}),isFalse);
    expect(InvoicePdfPreparationPolicy.canOfferCachedPdf({...valid,'lines':[]}),isFalse);
    expect(InvoicePdfPreparationPolicy.canOfferCachedPdf({...valid,'status':'void'}),isFalse);
    expect(InvoicePdfPreparationPolicy.canOfferCachedPdf({...valid,'kind':'estimate'}),isFalse);
  });

  test('transport exception recognized; permission failures are not', () {
    expect(InvoicePdfPreparationPolicy.isTransportFailure(
      Exception('ClientException: Software caused connection abort')),isTrue);
    expect(InvoicePdfPreparationPolicy.isTransportFailure(
      Exception('SocketException: Failed host lookup')),isTrue);
    expect(InvoicePdfPreparationPolicy.isTransportFailure(
      Exception('PostgrestException: permission denied')),isFalse);
  });
}
