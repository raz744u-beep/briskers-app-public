import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';

class DocumentPdfService {
  const DocumentPdfService._();

  static String _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    return '\u0024${value.toStringAsFixed(2)}';
  }

  static String _quantity(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    if (value == value.roundToDouble()) return value.toInt().toString();
    var text = value.toStringAsFixed(2);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  static String _address(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final formatted = map['formatted']?.toString().trim() ?? '';
      if (formatted.isNotEmpty) return formatted;

      final street = <String>[
        map['line1']?.toString().trim() ?? '',
        map['line2']?.toString().trim() ?? '',
      ].where((value) => value.isNotEmpty).join(' ');

      final cityStateZip = <String>[
        map['city']?.toString().trim() ?? '',
        <String>[
          map['state']?.toString().trim() ?? '',
          map['postal_code']?.toString().trim() ??
              map['zip']?.toString().trim() ??
              '',
        ].where((value) => value.isNotEmpty).join(' '),
      ].where((value) => value.isNotEmpty).join(', ');

      return <String>[
        if (street.isNotEmpty) street,
        if (cityStateZip.isNotEmpty) cityStateZip,
      ].join('\n');
    }
    return raw.toString().trim();
  }

  static String _date(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '$month/$day/${parsed.year}';
  }

  static String _displayNumber(String kind, String raw) {
    var number = raw.trim();
    if (kind == 'INVOICE') {
      final upper = number.toUpperCase();
      if (upper.startsWith('I-')) {
        number = number.substring(2);
      } else if (upper.startsWith('I') && number.length > 1) {
        number = number.substring(1);
        if (number.startsWith('-')) number = number.substring(1);
      }
    }
    return number;
  }

  static String _taxLabel(List<Map<String, dynamic>> lines) {
    final rates = lines
        .map((line) => num.tryParse(line['tax_rate']?.toString() ?? '') ?? 0)
        .where((rate) => rate > 0)
        .toSet();

    if (rates.length != 1) return 'Sales Tax';

    var percent = (rates.single * 100).toStringAsFixed(3);
    while (percent.contains('.') && percent.endsWith('0')) {
      percent = percent.substring(0, percent.length - 1);
    }
    if (percent.endsWith('.')) percent = percent.substring(0, percent.length - 1);
    return 'Sales Tax ($percent%)';
  }

  static Future<pw.MemoryImage?> _monochromeLogo() async {
    try {
      final data = await rootBundle.load('assets/briskers_header_logo.png');
      final source = img.decodeImage(data.buffer.asUint8List());
      if (source == null) return null;

      final monochrome = img.grayscale(source);
      for (final pixel in monochrome) {
        final value = pixel.r < 190 ? 0 : 255;
        pixel
          ..r = value
          ..g = value
          ..b = value;
      }

      return pw.MemoryImage(
        Uint8List.fromList(img.encodePng(monochrome)),
      );
    } catch (_) {
      return null;
    }
  }

  static String fileName(Map<String, dynamic> detail) {
    final kind =
        detail['kind']?.toString() == 'estimate' ? 'Estimate' : 'Invoice';
    final number = detail['document_number']?.toString().trim() ?? '';
    return number.isEmpty ? 'Briskers-$kind.pdf' : 'Briskers-$kind-$number.pdf';
  }

  static Future<Uint8List> build(Map<String, dynamic> detail) async {
    final doc = pw.Document();
    final logo = await _monochromeLogo();

    final allLines = List<dynamic>.from(detail['lines'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final laborLines = allLines
        .where((line) => line['line_kind']?.toString() == 'labor')
        .toList();
    final itemLines = allLines
        .where((line) => line['line_kind']?.toString() != 'labor')
        .toList();

    final kind =
        detail['kind']?.toString() == 'estimate' ? 'ESTIMATE' : 'INVOICE';
    final kindTitle = kind == 'INVOICE' ? 'Invoice' : 'Estimate';
    final rawDocumentNumber =
        detail['document_number']?.toString().trim() ?? '';
    final documentNumber = _displayNumber(kind, rawDocumentNumber);

    final shopName = detail['shop_name']?.toString().trim() ?? 'Briskers';
    final shopAddress = _address(detail['shop_address']);
    final shopPhone = formatUsPhone(detail['shop_phone']?.toString());
    final shopEmail = detail['shop_email']?.toString().trim() ?? '';

    final customer = detail['customer_name']?.toString().trim() ?? '';
    final customerAddress = _address(detail['customer_address']);
    final customerPhone = formatUsPhone(detail['customer_phone']?.toString());
    final customerEmail = detail['customer_email']?.toString().trim() ?? '';

    final vehicle = detail['vehicle']?.toString().trim() ?? '';
    final vin = detail['vehicle_vin']?.toString().trim() ?? '';
    final odometer = detail['odometer_in']?.toString().trim() ?? '';
    final color = detail['vehicle_color']?.toString().trim() ?? '';
    final plate = detail['vehicle_license_plate']?.toString().trim() ?? '';
    final plateState = detail['vehicle_license_state']?.toString().trim() ?? '';

    final jobNumber = detail['job_number']?.toString().trim() ?? '';
    final paymentTerms =
        detail['payment_terms']?.toString().trim() ?? 'Due on receipt';
    final claimNumber = detail['claim_number']?.toString().trim() ?? '';
    final authorizationNumber =
        detail['authorization_number']?.toString().trim() ?? '';
    final warrantyMessage =
        detail['warranty_message']?.toString().trim() ?? '';
    final memo = detail['memo']?.toString().trim() ?? '';

    final findingNotes = List<dynamic>.from(
      detail['finding_notes'] ?? const [],
    )
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .map((finding) => finding['body']?.toString().trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList();

    final notes = <String>[
      if (memo.isNotEmpty) memo,
      ...findingNotes,
    ];

    final subtotal =
        num.tryParse(detail['net_amount']?.toString() ?? '') ??
            allLines.fold<num>(
              0,
              (sum, line) =>
                  sum +
                  (num.tryParse(line['net_amount']?.toString() ?? '') ?? 0),
            );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null)
                      pw.SizedBox(
                        width: 138,
                        height: 42,
                        child: pw.Image(
                          logo,
                          fit: pw.BoxFit.contain,
                        ),
                      )
                    else
                      pw.Text(
                        shopName,
                        style: const pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    pw.SizedBox(height: 5),
                    if (shopAddress.isNotEmpty)
                      pw.Text(
                        shopAddress,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    if (shopPhone.isNotEmpty)
                      pw.Text(
                        'Phone: $shopPhone',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    if (shopEmail.isNotEmpty)
                      pw.Text(
                        shopEmail,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 18),
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        documentNumber.isEmpty
                            ? kindTitle
                            : '$kindTitle #$documentNumber',
                        style: const pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    _metadataRow(
                      'Date',
                      _date(detail['document_date']),
                    ),
                    if (jobNumber.isNotEmpty)
                      _metadataRow('Job #', jobNumber),
                    _metadataRow(
                      'Payment Terms',
                      paymentTerms.isEmpty ? 'Due on receipt' : paymentTerms,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: _infoBox(
                  title: 'Bill To',
                  children: [
                    if (customer.isNotEmpty)
                      pw.Text(
                        customer,
                        style: const pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (customerAddress.isNotEmpty)
                      pw.Text(
                        customerAddress,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    if (customerPhone.isNotEmpty)
                      pw.Text(
                        'Phone: $customerPhone',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    if (customerEmail.isNotEmpty)
                      pw.Text(
                        'Email: $customerEmail',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _infoBox(
                  title: 'Vehicle',
                  children: [
                    if (vehicle.isNotEmpty)
                      pw.Text(
                        vehicle,
                        style: const pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (vin.isNotEmpty)
                      pw.Text('VIN: $vin', style: const pw.TextStyle(fontSize: 9)),
                    if (odometer.isNotEmpty)
                      pw.Text(
                        'Mileage: ${_quantity(odometer)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    if (color.isNotEmpty)
                      pw.Text(
                        'Color: $color',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    if (plate.isNotEmpty)
                      pw.Text(
                        'License: ${plateState.isEmpty ? plate : '$plateState $plate'}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          if (itemLines.isNotEmpty)
            _lineTable(
              itemLines,
              quantityHeading: 'Qty',
            ),
          if (laborLines.isNotEmpty) ...[
            if (itemLines.isNotEmpty) pw.SizedBox(height: 10),
            _laborTable(laborLines),
          ],
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: _claimBox(
                  claimNumber: claimNumber,
                  authorizationNumber: authorizationNumber,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalsBox(
                  subtotal: subtotal,
                  taxLabel: _taxLabel(allLines),
                  tax: detail['tax_amount'],
                  total: detail['total_amount'],
                ),
              ),
            ],
          ),
          if (warrantyMessage.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _fullWidthSection(
              'Warranty Information',
              warrantyMessage,
              minHeight: 46,
            ),
          ],
          pw.SizedBox(height: 10),
          _fullWidthSection(
            'Notes',
            notes.join('\n'),
            minHeight: 44,
          ),
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              'Thank you for choosing Briskers!',
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _metadataRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 80,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoBox({
    required String title,
    required List<pw.Widget> children,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            color: PdfColors.grey200,
            child: pw.Text(
              title,
              style: const pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: children.isEmpty ? [pw.SizedBox(height: 42)] : children,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _lineTable(
    List<Map<String, dynamic>> lines, {
    required String quantityHeading,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey500,
        width: 0.45,
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.55),
        1: pw.FlexColumnWidth(4.2),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.45),
        4: pw.FlexColumnWidth(1.55),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _headerCell('#', align: pw.TextAlign.center),
            _headerCell('Description'),
            _headerCell(quantityHeading, align: pw.TextAlign.center),
            _headerCell('Unit Price', align: pw.TextAlign.right),
            _headerCell('Amount', align: pw.TextAlign.right),
          ],
        ),
        for (var index = 0; index < lines.length; index++)
          _lineRow(lines[index], index + 1),
      ],
    );
  }

  static pw.Widget _laborTable(List<Map<String, dynamic>> lines) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            border: pw.Border.all(color: PdfColors.grey500, width: 0.45),
          ),
          child: pw.Text(
            'Labor',
            style: const pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(color: PdfColors.grey500, width: 0.45),
            right: pw.BorderSide(color: PdfColors.grey500, width: 0.45),
            bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.45),
            verticalInside:
                pw.BorderSide(color: PdfColors.grey500, width: 0.45),
            horizontalInside:
                pw.BorderSide(color: PdfColors.grey500, width: 0.45),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.55),
            1: pw.FlexColumnWidth(4.2),
            2: pw.FlexColumnWidth(1.0),
            3: pw.FlexColumnWidth(1.45),
            4: pw.FlexColumnWidth(1.55),
          },
          children: [
            for (var index = 0; index < lines.length; index++)
              _lineRow(lines[index], index + 1),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _lineRow(
    Map<String, dynamic> line,
    int index,
  ) {
    final name = line['name']?.toString().trim() ?? '';
    final description = line['description']?.toString().trim() ?? '';
    final display = <String>[
      if (name.isNotEmpty) name,
      if (description.isNotEmpty) description,
    ].join(' - ');

    return pw.TableRow(
      children: [
        _bodyCell(index.toString(), align: pw.TextAlign.center),
        _bodyCell(display),
        _bodyCell(
          _quantity(line['quantity']),
          align: pw.TextAlign.center,
        ),
        _bodyCell(_money(line['unit_price']), align: pw.TextAlign.right),
        _bodyCell(_money(line['net_amount']), align: pw.TextAlign.right),
      ],
    );
  }

  static pw.Widget _claimBox({
    required String claimNumber,
    required String authorizationNumber,
  }) {
    final hasInfo = claimNumber.isNotEmpty || authorizationNumber.isNotEmpty;

    return pw.Container(
      height: 76,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
      ),
      child: hasInfo
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  color: PdfColors.grey200,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: pw.Text(
                    'Insurance / Extended Warranty',
                    style: const pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (claimNumber.isNotEmpty)
                        pw.Text(
                          'Claim Number:  $claimNumber',
                          style: const pw.TextStyle(fontSize: 8.8),
                        ),
                      if (authorizationNumber.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text(
                            'Authorization Number:  $authorizationNumber',
                            style: const pw.TextStyle(fontSize: 8.8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : pw.SizedBox(),
    );
  }

  static pw.Widget _totalsBox({
    required num subtotal,
    required String taxLabel,
    required Object? tax,
    required Object? total,
  }) {
    return pw.Container(
      height: 76,
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
      ),
      child: pw.Column(
        children: [
          _totalRow('Subtotal', _money(subtotal)),
          _totalRow(taxLabel, _money(tax)),
          pw.Divider(height: 10, color: PdfColors.grey600),
          _totalRow('Total', _money(total), bold: true),
        ],
      ),
    );
  }

  static pw.Widget _fullWidthSection(
    String title,
    String body, {
    required double minHeight,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(
              title,
              style: const pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Container(
            constraints: pw.BoxConstraints(minHeight: minHeight),
            padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: body.isEmpty
                ? pw.SizedBox()
                : pw.Text(
                    body,
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      lineSpacing: 1.5,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _headerCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 8.2,
        ),
      ),
    );
  }

  static pw.Widget _bodyCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontSize: bold ? 12 : 9.5,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
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
