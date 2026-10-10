import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';

class DocumentPdfService {
  const DocumentPdfService._();

  /// Amounts shown on an invoice. Entered-but-unfinalized payments are
  /// separate from confirmed paid amounts and are subtracted exactly once.
  /// This mirrors the balance calculation on JobDocumentScreen.
  static Map<String, num> invoicePaymentAmounts(Map<String, dynamic> detail) {
    num nonNegative(Object? raw) {
      final value = num.tryParse(raw?.toString() ?? '') ?? 0;
      return value.isFinite && value > 0 ? value : 0;
    }

    final total = nonNegative(detail['total_amount']);
    final paid = nonNegative(detail['paid_amount']);
    final pending = nonNegative(detail['pending_payment']);
    final difference = total - paid - pending;
    return <String, num>{
      'total': total,
      'paid': paid,
      'pending': pending,
      'remaining': difference > 0 ? difference : 0,
    };
  }

  /// Presentation-only payment rows for invoice PDFs.
  /// Use an ASCII separator because PDF Helvetica lacks em dash support. The aggregate amounts
  /// remain authoritative; never double-count or label pending as finalized.
  /// If a stale/offline detail lacks a complete payment breakdown, preserve
  /// the correct totals rather than guessing payment methods.
  static List<Map<String, dynamic>> invoicePaymentLines(
    Map<String, dynamic> detail,
  ) {
    final amounts = invoicePaymentAmounts(detail);
    int cents(num value) => (value * 100).round();
    final paidCents = cents(amounts['paid'] ?? 0);
    final pendingCents = cents(amounts['pending'] ?? 0);

    final rows = <Map<String, dynamic>>[];
    var matchedPaid = 0;
    var matchedPending = 0;
    final rawPayments = detail['payments'];
    if (rawPayments is List) {
      for (final raw in rawPayments) {
        if (raw is! Map) continue;
        final payment = Map<String, dynamic>.from(raw);
        final state =
            payment['state']?.toString().trim().toLowerCase() ?? '';
        if (const {
          'void',
          'voided',
          'cancelled',
          'canceled',
          'reversed',
          'deleted',
          'failed',
        }.contains(state)) {
          continue;
        }
        final amount = num.tryParse(payment['amount']?.toString() ?? '');
        if (amount == null || !amount.isFinite || amount <= 0) continue;
        final amountCents = cents(amount);
        if (amountCents <= 0) continue;

        final pending = state == 'pending';
        final method =
            payment['payment_method_name']?.toString().trim() ?? '';
        final displayMethod =
            method.isEmpty ? 'Method not recorded' : method;
        rows.add({
          'label':
              'Payment - $displayMethod${pending ? ' (Pending)' : ''}',
          'amount': amountCents / 100,
          'pending': pending,
        });
        if (pending) {
          matchedPending += amountCents;
        } else {
          matchedPaid += amountCents;
        }
      }
    }

    if (matchedPaid == paidCents && matchedPending == pendingCents) {
      return rows;
    }

    // Incomplete/old payment detail: do not invent card/check information,
    // apply some entries twice, or misstate the invoice balance.
    return [
      if (paidCents > 0)
        {
          'label': 'Payment - Method not recorded',
          'amount': paidCents / 100,
          'pending': false,
        },
      if (pendingCents > 0)
        {
          'label': 'Payment - Method not recorded (Pending)',
          'amount': pendingCents / 100,
          'pending': true,
        },
    ];
  }

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
    final invoicePayments =
        kind == 'INVOICE' ? invoicePaymentAmounts(detail) : null;
    final paymentRows = kind == 'INVOICE'
        ? invoicePaymentLines(detail)
        : <Map<String, dynamic>>[];
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
    final extendedWarranty = detail['extended_warranty'] == true;
    final warrantyCompany =
        detail['warranty_company_name']?.toString().trim() ?? '';
    final warrantyApproved =
        num.tryParse(detail['approved_amount']?.toString() ?? '') ?? 0;
    final warrantyTerminal =
        num.tryParse(detail['terminal_amount']?.toString() ?? '') ?? 0;
    final warrantyProcessorFee =
        num.tryParse(detail['processor_fee']?.toString() ?? '') ?? 0;
    final warrantyNetApplied =
        num.tryParse(detail['net_applied']?.toString() ?? '') ?? 0;
    final customerResponsibility =
        num.tryParse(
          detail['customer_responsibility']?.toString() ?? '',
        ) ??
        0;
    final disclaimers = List<dynamic>.from(
      detail['disclaimers'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final signatureBytes = detail['signature_bytes'];
    final signatureCurrent = detail['signature_current'] == true;
    final signerName = detail['signer_name']?.toString().trim() ?? '';
    final signedAtRaw = detail['signed_at']?.toString() ?? '';
    final signedAt = DateTime.tryParse(signedAtRaw);
    final showSignature =
        signatureCurrent && signatureBytes is Uint8List;
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
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
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
            crossAxisAlignment: pw.CrossAxisAlignment.start,
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
            crossAxisAlignment: pw.CrossAxisAlignment.start,
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
                  payments: invoicePayments,
                  paymentRows: paymentRows,
                ),
              ),
            ],
          ),
          if (extendedWarranty) ...[
            pw.SizedBox(height: 10),
            _warrantyAllocationBox(
              company: warrantyCompany,
              approved: warrantyApproved,
              terminal: warrantyTerminal,
              processorFee: warrantyProcessorFee,
              netApplied: warrantyNetApplied,
              customerResponsibility: customerResponsibility,
            ),
          ],
          if (warrantyMessage.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _fullWidthSection(
              'Warranty Information',
              warrantyMessage,
              minHeight: 46,
            ),
          ],
          if (disclaimers.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            ...disclaimers.expand(
              (item) => [
                _fullWidthSection(
                  'Customer Acknowledgment — '
                  '${item['title']?.toString().trim() ?? 'Disclaimer'}',
                  item['body']?.toString().trim() ?? '',
                  minHeight: 42,
                ),
                pw.SizedBox(height: 8),
              ],
            ),
          ],
          _fullWidthSection(
            'Notes',
            notes.join('\n'),
            minHeight: 44,
          ),
          if (showSignature) ...[
            pw.SizedBox(height: 10),
            _signatureBox(
              bytes: signatureBytes,
              signerName: signerName,
              signedAt: signedAt,
            ),
          ],
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
              crossAxisAlignment: pw.CrossAxisAlignment.start,
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
    required Map<String, num>? payments,
    required List<Map<String, dynamic>> paymentRows,
  }) {
    final paid = payments?['paid'] ?? 0;
    final pending = payments?['pending'] ?? 0;
    final remaining = payments?['remaining'] ?? 0;

    return pw.Container(
      // Invoices need room for any number of individual payment rows.
      height: payments == null ? 76 : null,
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
          if (payments != null) ...[
            if (paymentRows.isNotEmpty)
              pw.Divider(height: 8, color: PdfColors.grey600),
            for (final payment in paymentRows)
              _totalRow(
                payment['label']?.toString() ?? 'Payment',
                _money(payment['amount']),
              ),
            pw.Divider(height: 8, color: PdfColors.grey600),
            _totalRow(
              'Total Payments Received',
              _money(paid + pending),
              bold: true,
            ),
            _totalRow('Balance Due', _money(remaining), bold: true),
            if (pending > 0.005)
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Pending entries are not yet finalized',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _signatureBox({
    required Uint8List bytes,
    required String signerName,
    required DateTime? signedAt,
  }) {
    final signature = pw.MemoryImage(bytes);
    final dateText = signedAt == null
        ? ''
        : '${signedAt.month.toString().padLeft(2, '0')}/'
          '${signedAt.day.toString().padLeft(2, '0')}/'
          '${signedAt.year}';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            child: pw.Text(
              'Customer Signature',
              style: const pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 7),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.SizedBox(
                    height: 48,
                    child: pw.Image(
                      signature,
                      fit: pw.BoxFit.contain,
                      alignment: pw.Alignment.centerLeft,
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (signerName.isNotEmpty)
                      pw.Text(
                        signerName,
                        style: const pw.TextStyle(
                          fontSize: 8.8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (dateText.isNotEmpty)
                      pw.Text(
                        'Signed: $dateText',
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _warrantyAllocationBox({
    required String company,
    required num approved,
    required num terminal,
    required num processorFee,
    required num netApplied,
    required num customerResponsibility,
  }) {
    pw.Widget row(String label, num value, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 8.8,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Text(
              _money(value),
              style: pw.TextStyle(
                fontSize: bold ? 10 : 8.8,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            child: pw.Text(
              company.isEmpty
                  ? 'Extended Warranty Payment Allocation'
                  : 'Extended Warranty — $company',
              style: const pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
            child: pw.Column(
              children: [
                row('Approved warranty amount', approved),
                row('Run warranty card for', terminal, bold: true),
                row('Processor surcharge (not shop revenue)', processorFee),
                row('Warranty applied to invoice', netApplied),
                pw.Divider(height: 8, color: PdfColors.grey500),
                row(
                  'Customer responsibility',
                  customerResponsibility,
                  bold: true,
                ),
              ],
            ),
          ),
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
