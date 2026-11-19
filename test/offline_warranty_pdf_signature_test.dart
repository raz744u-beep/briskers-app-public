import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:briskers_app/core/invoice_warranty_pdf_projection.dart';
import 'package:briskers_app/core/warranty_payment_amounts.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/document_pdf_service.dart';
import 'package:briskers_app/services/local_invoice_signature_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String,dynamic> invoice() => {
    'id':'invoice','business_id':'shop','kind':'invoice','document_number':'QA-6380',
    'customer_name':'Synthetic Warranty Customer','vehicle':'2017 Jaguar XF',
    'vehicle_vin':'SYNTHETIC-VIN','odometer_in':85440,'document_date':'2026-11-17',
    'net_amount':1504.16,'tax_amount':0,'total_amount':1504.16,
    'paid_amount':0,'pending_payment':0,'memo':'Regular repair notes',
    'lines':[{'id':'line','name':'Cooling repairs','line_kind':'labor','quantity':4.5,'net_amount':1504.16}],
    'offline_warranty_detail':{
      'extended_warranty':true,'warranty_company_name':'Synthetic Warranty Company',
      'claim_number':'QA-CLAIM','authorization_number':'QA-AUTH',
      'submission_email':'warranty@example.invalid','approved_amount':792.73,
      'terminal_amount':769.64,'net_applied':769.64,'processor_fee':23.09,
      'customer_responsibility':734.52,'surcharge_rate':0.03,
    },
  };
  test('saved warranty appears before payments without altering invoice or credit', () async {
    final detail=invoice(); final original=jsonEncode(detail);
    final projected=InvoiceWarrantyPdfProjection.apply(detail);
    final allocation=WarrantyPaymentAllocation.fromWarranty(invoiceTotal:projected['total_amount'],warranty:projected);
    expect(allocation.customerBase,711.43); expect(allocation.processorFee,23.09);
    expect(allocation.customerTotal,734.52); expect(allocation.requiresReview,false);
    expect(projected['claim_number'],'QA-CLAIM');expect(projected['authorization_number'],'QA-AUTH');
    expect(DocumentPdfService.invoicePaymentAmounts(projected)['remaining'],1504.16);
    final bytes=await DocumentPdfService.build(detail);
    final out=Directory('build/pdf-qa')..createSync(recursive:true);
    await File('${out.path}/offline-warranty-before-payment.pdf').writeAsBytes(bytes);
    expect(bytes.length,greaterThan(1000)); expect(jsonEncode(detail),original);
  });
  test('signature survives offline restart, embeds in PDF, and edits require signing again', () async {
    final dir=await Directory.systemTemp.createTemp('signature');
    final file=File('${dir.path}/local.sqlite');
    var db=BriskersLocalDatabase(NativeDatabase(file));
    try {
      final detail=InvoiceWarrantyPdfProjection.apply(invoice());
      final image=img.Image(width:160,height:45);
      img.fill(image,color:img.ColorRgb8(255,255,255));
      img.drawLine(image,x1:5,y1:30,x2:145,y2:10,color:img.ColorRgb8(0,0,0),thickness:3);
      final png=Uint8List.fromList(img.encodePng(image));
      await LocalInvoiceSignatureStore(database:db).save('shop','invoice',detail,signerName:'Synthetic signer',bytes:png);
      await db.close();db=BriskersLocalDatabase(NativeDatabase(file));
      final store=LocalInvoiceSignatureStore(database:db);
      final signed=await store.project('shop','invoice',detail);
      expect(signed['signature_current'],true);expect(signed['signature_bytes'],png);
      final pdf=await DocumentPdfService.build(signed);
      Directory('build/pdf-qa').createSync(recursive:true);
      await File('build/pdf-qa/offline-warranty-signed.pdf').writeAsBytes(pdf);
      for(final changed in [{...detail,'memo':'Changed notes'}, {...detail,'total_amount':1600},
        {...detail,'claim_number':'OTHER','offline_warranty_detail':null}]) {
        expect((await store.project('shop','invoice',changed))['signature_current'],false);
      }
      expect((await store.project('other-shop','invoice',signed))['signature_bytes'],isNull);
      expect((await store.project('shop','other-invoice',signed))['signature_bytes'],isNull);
      expect((await store.project('shop','invoice',{...detail,'paid_amount':734.52}))['signature_current'],true,
        reason:'Receipt entry does not rewrite the signed invoice allocation or consent.');
    } finally {await db.close();await dir.delete(recursive:true);}
  });
  test('contradictory nested warranty cannot lend another invoice its data', () {
    final detail=invoice();detail['offline_warranty_detail']={...detail['offline_warranty_detail'] as Map,'document_id':'other'};
    expect(InvoiceWarrantyPdfProjection.apply(detail)['extended_warranty'],isNull);
  });
}
