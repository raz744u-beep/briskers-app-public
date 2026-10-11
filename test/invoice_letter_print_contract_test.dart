import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice document uses US Letter for PDF, preview and print', () async {
    final pdf=await File('lib/services/document_pdf_service.dart').readAsString();
    final screen=await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    expect(pdf,contains('pageFormat: PdfPageFormat.letter'));
    expect(screen,contains('initialPageFormat: PdfPageFormat.letter'));
    expect(screen,contains('format: PdfPageFormat.letter'));
    expect(screen,contains('dynamicLayout: false'));
    expect(screen,contains("MethodChannel('com.briskers/pdf')"));
    expect(screen,contains("'openPdfInApp'"));
  });
}
