import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DocumentPdfService {
  const DocumentPdfService._();

  static String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return '\u0024${value.toStringAsFixed(2)}';
  }

  static String _address(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final preferred = <String>[
        map['street']?.toString() ?? '',
        map['address1']?.toString() ?? '',
        map['address2']?.toString() ?? '',
        map['city']?.toString() ?? '',
        map['state']?.toString() ?? '',
        map['zip']?.toString() ?? '',
        map['postal_code']?.toString() ?? '',
      ].where((value) => value.trim().isNotEmpty).toList();

      if (preferred.isNotEmpty) {
        return preferred.join(', ');
      }

      return map.values
          .where((value) => value != null && value.toString().trim().isNotEmpty)
          .map((value) => value.toString())
          .join(', ');
    }
    return raw.toString();
  }

  static String fileName(Map<String, dynamic> detail) {
    final kind = detail['kind']?.toString() == 'estimate'
        ? 'Estimate'
        : 'Invoice';
    final number = detail['document_number']?.toString().trim() ?? '';
    return number.isEmpty ? 'Briskers-$kind.pdf' : 'Briskers-$kind-$number.pdf';
  }

  static Future<Uint8List> build(Map<String, dynamic> detail) async {
    final doc = pw.Document();
    final lines = List<dynamic>.from(detail['lines'] ?? const []);
    final kind = detail['kind']?.toString() == 'estimate'
        ? 'ESTIMATE'
        : 'INVOICE';
    final documentNumber =
        detail['document_number']?.toString().trim() ?? '';
    final shopName = detail['shop_name']?.toString() ?? 'Briskers';
    final shopAddress = _address(detail['shop_address']);
    final shopPhone = detail['shop_phone']?.toString() ?? '';
    final shopEmail = detail['shop_email']?.toString() ?? '';
    final customer = detail['customer_name']?.toString() ?? '';
    final customerPhone = detail['customer_phone']?.toString() ?? '';
    final customerEmail = detail['customer_email']?.toString() ?? '';
    final vehicle = detail['vehicle']?.toString() ?? '';
    final vin = detail['vehicle_vin']?.toString() ?? '';
    final jobNumber = detail['job_number']?.toString() ?? '';
    final jobTitle = detail['job_title']?.toString() ?? '';
    final total = num.tryParse(detail['total_amount']?.toString() ?? '') ?? 0;
    final finalizedPaid =
        num.tryParse(detail['paid_amount']?.toString() ?? '') ?? 0;
    final pendingPaid =
        num.tryParse(detail['pending_payment']?.toString() ?? '') ?? 0;
    final shownPaid = finalizedPaid + pendingPaid;
    final balance = total - shownPaid;
    final findingNotes = List<dynamic>.from(
      detail['finding_notes'] ?? const [],
    )
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .map((finding) => finding['body']?.toString().trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList();
    final memo = detail['memo']?.toString().trim() ?? '';
    final odometer = detail['odometer_in']?.toString().trim() ?? '';
    final claimNumber = detail['claim_number']?.toString().trim() ?? '';
    final authorizationNumber =
        detail['authorization_number']?.toString().trim() ?? '';
    final noteLines = <String>[
      if (odometer.isNotEmpty) 'Mileage: $odometer',
      if (claimNumber.isNotEmpty) 'Claim #: $claimNumber',
      if (authorizationNumber.isNotEmpty)
        'Authorization #: $authorizationNumber',
      if (memo.isNotEmpty) memo,
      ...findingNotes.map((finding) => 'Finding: $finding'),
    ];


    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      shopName,
                      style: const pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (shopAddress.isNotEmpty) pw.Text(shopAddress),
                    if (shopPhone.isNotEmpty) pw.Text(shopPhone),
                    if (shopEmail.isNotEmpty) pw.Text(shopEmail),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    kind,
                    style: const pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (documentNumber.isNotEmpty)
                    pw.Text('#$documentNumber'),
                  if ((detail['document_date']?.toString() ?? '').isNotEmpty)
                    pw.Text(detail['document_date'].toString()),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Customer',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(customer),
                      if (customerPhone.isNotEmpty) pw.Text(customerPhone),
                      if (customerEmail.isNotEmpty) pw.Text(customerEmail),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Vehicle / Job',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      if (vehicle.isNotEmpty) pw.Text(vehicle),
                      if (vin.isNotEmpty) pw.Text('VIN: $vin'),
                      if (jobNumber.isNotEmpty) pw.Text('Job: $jobNumber'),
                      if (jobTitle.isNotEmpty) pw.Text(jobTitle),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              bottom: pw.BorderSide(color: PdfColors.grey400),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FlexColumnWidth(1.1),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(1.7),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                children: [
                  _headerCell('Item / Description'),
                  _headerCell('Qty'),
                  _headerCell('Price'),
                  _headerCell('Amount'),
                ],
              ),
              ...lines.map((raw) {
                final line = Map<String, dynamic>.from(raw as Map);
                final name = line['name']?.toString() ?? '';
                final description = line['description']?.toString() ?? '';
                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 7,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            name,
                            style: const pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (description.isNotEmpty)
                            pw.Text(
                              description,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                        ],
                      ),
                    ),
                    _bodyCell(line['quantity']?.toString() ?? ''),
                    _bodyCell(_money(line['unit_price'])),
                    _bodyCell(
                      _money(line['net_amount']),
                    ),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 235,
              child: pw.Column(
                children: [
                  _totalRow(
                    'Subtotal',
                    _money(
                      lines
                          .where((line) => line['line_kind'] != 'discount')
                          .fold<num>(
                            0,
                            (sum, line) =>
                                sum +
                                (num.tryParse(
                                      line['net_amount']?.toString() ?? '',
                                    ) ??
                                    0),
                          ),
                    ),
                  ),
                  if (lines.any((line) => line['line_kind'] == 'discount'))
                    _totalRow(
                      'Discount',
                      _money(
                        lines
                            .where((line) => line['line_kind'] == 'discount')
                            .fold<num>(
                              0,
                              (sum, line) =>
                                  sum +
                                  (num.tryParse(
                                        line['net_amount']?.toString() ?? '',
                                      ) ??
                                      0),
                            ),
                      ),
                    ),
                  _totalRow('Tax', _money(detail['tax_amount'])),
                  pw.Divider(),
                  _totalRow(
                    'Total',
                    _money(detail['total_amount']),
                    bold: true,
                  ),
                  if (kind == 'INVOICE') ...[
                    _totalRow('Paid', _money(shownPaid)),
                    pw.Divider(),
                    _totalRow(
                      'Balance Due',
                      _money(balance),
                      bold: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (noteLines.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Notes',
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            ...noteLines.map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(line),
              ),
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Text(
            'Thank you for choosing $shopName.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        text,
        style: const pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
  }

  static pw.Widget _bodyCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontSize: bold ? 11 : 10,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }
}
