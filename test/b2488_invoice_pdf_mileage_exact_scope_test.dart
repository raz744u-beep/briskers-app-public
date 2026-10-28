import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/invoice_pdf_mileage_projection.dart';
import 'package:briskers_app/core/mileage_workflow.dart';

const invoice = <String, dynamic>{
  'id': 'invoice-6358', 'kind': 'invoice',
  'job_id': 'job-j39', 'vehicle_id': 'porsche-cayenne',
  'mileage_schema_version': 2,
  'total_amount': 301.81, 'paid_amount': 301.81,
  'pending_payment': 0.0, 'display_status_code': 'pending_close',
};

void main() {
  test('Invoice #6358 PDF restores exact visible Miles Out when RPC omits it', () {
    final visible = {...invoice, 'mileage_out': 67445};
    final server = Map<String, dynamic>.from(invoice)
      ..remove('mileage_schema_version');
    final projected = InvoicePdfMileageProjection.reconcile(
      documentId: 'invoice-6358', pdfDetail: server, visibleDetail: visible);
    expect(MileageWorkflow.printableReadings(projected),
      [('Miles Out', 67445)]);
    expect(projected['total_amount'], 301.81);
    expect(projected['paid_amount'], 301.81);
    expect(projected['display_status_code'], 'pending_close');
  });

  test('Official saved Miles Out outranks a conflicting on-screen snapshot', () {
    final projected = InvoicePdfMileageProjection.reconcile(
      documentId: 'invoice-6358',
      pdfDetail: {...invoice, 'mileage_out': 67450},
      visibleDetail: {...invoice, 'mileage_out': 67445});
    expect(projected['mileage_out'], 67450);
  });

  test('Incorrect invoice, Job or vehicle cannot leak its miles onto PDF', () {
    final server = Map<String, dynamic>.from(invoice);
    for (final alternate in [
      {...invoice, 'id': 'invoice-other', 'mileage_out': 67445},
      {...invoice, 'job_id': 'job-other', 'mileage_out': 67445},
      {...invoice, 'vehicle_id': 'vehicle-other', 'mileage_out': 67445},
      {...invoice, 'kind': 'estimate', 'mileage_out': 67445},
    ]) {
      final projected = InvoicePdfMileageProjection.reconcile(
        documentId: 'invoice-6358', pdfDetail: server, visibleDetail: alternate);
      expect(projected['mileage_out'], isNull);
    }
  });

  test('Legacy or invalid readings stay neutral and never fabricate Miles Out', () {
    final legacy = {
      ...invoice, 'mileage_schema_version': 1, 'odometer_in': 90000,
    };
    final projected = InvoicePdfMileageProjection.reconcile(
      documentId: 'invoice-6358', pdfDetail: legacy,
      visibleDetail: {...invoice, 'mileage_out': 67445});
    expect(MileageWorkflow.printableReadings(projected), [('Miles', 90000)]);
    expect(InvoicePdfMileageProjection.reconcile(
      documentId: 'invoice-6358',
      pdfDetail: invoice,
      visibleDetail: {...invoice, 'mileage_out': '-2'})['mileage_out'], isNull);
  });

  test('Miles In uses only exact invoice/Job/vehicle on-screen intake record', () {
    final projected = InvoicePdfMileageProjection.reconcile(
      documentId: 'invoice-6358', pdfDetail: invoice,
      visibleDetail: {...invoice, 'mileage_in': 67430, 'mileage_out': 67445});
    expect(MileageWorkflow.printableReadings(projected),
      [('Miles In', 67430), ('Miles Out', 67445)]);
  });

  test('PDF source uses durable mileage queue and exact display projection', () {
    final detail = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final start = detail.indexOf('Future<Map<String, dynamic>?> _preparePdf()');
    final finish = detail.indexOf('Future<void> _previewPdf()', start);
    final code = detail.substring(start, finish);
    expect(code, contains('await _invoiceMileage.project('));
    expect(code, contains('InvoicePdfMileageProjection.reconcile('));
    expect(code, contains('pdfDetail: queuedMileage'));
    expect(code, contains('visibleDetail: _detail'));
    expect(code, contains('await _withPdfUnits(detail)'));
    expect(code, contains("final result = await Future.wait<dynamic>(["));
    expect(code, contains('_api.documentDetail(widget.businessId, widget.documentId)'));
    expect(code, isNot(contains('closeInvoice(')));
    expect(code, isNot(contains('finalizePendingInvoicePayment(')));
    final pdf = File('lib/services/document_pdf_service.dart').readAsStringSync();
    expect(pdf, contains('MileageWorkflow.printableReadings(detail)'));
  });
}
