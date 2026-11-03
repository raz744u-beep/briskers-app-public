// ignore_for_file: prefer_interpolation_to_compose_strings, use_null_aware_elements, curly_braces_in_flow_control_structures
/// OCR line geometry; pure Dart so invoice parsing can be tested offline.
class ReceiptOcrFragment {
  const ReceiptOcrFragment({
    required this.text,
    required this.left,
    required this.top,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double height;
}

/// Conservative receipt parser. Never requires internet or database access.
/// All recognized values remain suggestions until user confirmation.
class LocalReceiptParser {
  const LocalReceiptParser._();

  static final _datePattern = RegExp(
    r'\b(0?[1-9]|1[0-2])[/\-](0?[1-9]|[12]\d|3[01])[/\-](20\d{2}|\d{2})\b',
  );
  static final _isoDatePattern = RegExp(
    r'\b(20\d{2})-(0?[1-9]|1[0-2])-(0?[1-9]|[12]\d|3[01])\b',
  );
  static final _moneyPattern = RegExp(r'\$?\s*([0-9][0-9,]*\.[0-9]{2})');
  static final _invoicePattern = RegExp(
    r'\b(?:invoice|inv\.?|receipt|ticket)\s*(?:no\.?|number|#)?\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-]{3,})\b',
    caseSensitive: false,
  );
  static final _linePattern = RegExp(
    r'^(.+?)\s+([1-9]\d{0,3})(?:\s*(?:x|@)\s*|\s+)\$?([0-9,]+\.[0-9]{2})\s+\$?([0-9,]+\.[0-9]{2})\s*$',
    caseSensitive: false,
  );
  static final _skuStart = RegExp(
    r'^((?:[A-Z]{1,5}\d[A-Z0-9\-]*|\d{4,12}|\d{2}(?:[\s\-]\d{1,3}){3,6}))\s+(.+)$',
    caseSensitive: false,
  );
  static final _skuEnd = RegExp(
    r'^(.+?)\s+((?:[A-Z]{1,5}\d[A-Z0-9\-]*|\d{4,12}|\d{2}(?:[\s\-]\d{1,3}){3,6}))$',
    caseSensitive: false,
  );
  static const _knownNames = ['Worldpac', 'AutoZone', 'Peake BMW'];

  /// ML Kit sometimes returns one text block per invoice column. Grouping
  /// fragments by row center restores SKU / description / quantity / prices.
  static List<String> _layoutRows(List<ReceiptOcrFragment> fragments) {
    final measured = fragments.where(
      (line) => line.height > 0 && line.text.trim().isNotEmpty,
    ).toList()
      ..sort((a, b) => (a.top + a.height / 2)
        .compareTo(b.top + b.height / 2));
    final groups = <List<ReceiptOcrFragment>>[];
    for (final fragment in measured) {
      if (groups.isEmpty) {
        groups.add([fragment]);
        continue;
      }
      final row = groups.last;
      final center = fragment.top + fragment.height / 2;
      final first = row.first;
      final rowCenter = first.top + first.height / 2;
      if ((center - rowCenter).abs() <=
          (fragment.height + first.height) * 0.31) {
        row.add(fragment);
      } else {
        groups.add([fragment]);
      }
    }
    return groups.map((row) {
      row.sort((a, b) => a.left.compareTo(b.left));
      return row.map((entry) => entry.text.trim()).join(' ');
    }).toList();
  }

  static bool _isOnlyAmount(String line) =>
      RegExp(r'^(?:USD\s*)?\$?\s*[0-9][0-9,]*\.[0-9]{2}\s*$',
        caseSensitive: false).hasMatch(line.trim());

  static String _norm(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static num? _amount(String value) =>
      num.tryParse(value.replaceAll(',', '').replaceAll(r'$', '').trim());

  static num? _lastMoney(String value) {
    final matches = _moneyPattern.allMatches(value).toList();
    if (matches.isEmpty) return null;
    return _amount(matches.last.group(1)!);
  }

  static String? _validatedDate(int year, int month, int day) {
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return year.toString() + '-' + month.toString().padLeft(2, '0') +
        '-' + day.toString().padLeft(2, '0');
  }

  static String? _date(String line) {
    final iso = _isoDatePattern.firstMatch(line);
    if (iso != null) {
      return _validatedDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final match = _datePattern.firstMatch(line);
    if (match == null) return null;
    final suffix = int.parse(match.group(3)!);
    return _validatedDate(suffix < 100 ? 2000 + suffix : suffix,
      int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static bool _isTotal(String line) => RegExp(
    r'^\s*(?:grand\s+total|invoice\s+total|total\s+due|amount\s+due|balance\s+due|total\s+paid|total)\s*[:\$#\-]?\s*',
    caseSensitive: false,
  ).hasMatch(line);

  static Map<String, dynamic> parse(
    String ocrText, {
    List<Map<String, dynamic>> vendors = const [],
    List<ReceiptOcrFragment> positionedLines = const [],
  }) {
    final originalLines = ocrText.split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim().replaceAll(RegExp(r'\s{2,}'), ' '))
        .where((line) => line.isNotEmpty).toList();
    final rowLines = _layoutRows(positionedLines);
    final lines = <String>[
      ...rowLines,
      for (final original in originalLines)
        if (!rowLines.contains(original)) original,
    ];
    String? vendor;
    String? receiptDate;
    String? invoiceNumber;
    num? total;
    num? subtotal;
    final flags = <String>[];
    final items = <Map<String, dynamic>>[];

    final candidates = <String>[..._knownNames,
      for (final entry in vendors)
        if ((entry['name']?.toString() ?? '').trim().isNotEmpty)
          entry['name'].toString().trim(),
    ];
    for (final line in lines.take(12)) {
      for (final candidate in candidates) {
        if (_norm(candidate).length < 4) continue;
        if (_norm(line) == _norm(candidate) ||
            (line.length <= candidate.length + 32 &&
             _norm(line).contains(_norm(candidate)))) {
          vendor = candidate;
          break;
        }
      }
      if (vendor != null) break;
    }
    if (vendor == null) flags.add('Vendor not confidently identified');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (receiptDate == null &&
          (lower.contains('date') || lower.contains('sold') || i < 10)) {
        receiptDate = _date(line);
      }
      if (invoiceNumber == null) {
        final candidate = _invoicePattern.firstMatch(line)?.group(1);
        if (candidate != null && RegExp(r'\d').hasMatch(candidate) &&
            !candidate.contains('/') && !candidate.contains('.') &&
            !RegExp(r'^20\d{2}-\d{1,2}-\d{1,2}').hasMatch(candidate)) {
          invoiceNumber = candidate; // Preserve leading zeros.
        }
      }
      if (RegExp(r'^\s*sub\s*total\b', caseSensitive: false).hasMatch(line)) {
        subtotal = _lastMoney(line) ?? subtotal;
      }
      if (_isTotal(line) && !lower.contains('subtotal')) {
        // Never infer a total from the line items or add a vendor surcharge.
        final found = _lastMoney(line) ??
          (i + 1 < lines.length &&
            RegExp(r'^\$?\s*\d').hasMatch(lines[i + 1])
              ? _lastMoney(lines[i + 1]) : null);
        if (found != null) total = found;
        continue;
      }
      if (RegExp(
        r'^(tax|subtotal|shipping|discount|change|visa|mastercard|credit|cash|paid|balance|amount|invoice|receipt|total)\b',
        caseSensitive: false,
      ).hasMatch(line)) continue;
      final match = _linePattern.firstMatch(line);
      if (match == null) continue;
      final qty = int.tryParse(match.group(2)!);
      final unit = _amount(match.group(3)!);
      final lineTotal = _amount(match.group(4)!);
      if (qty == null || unit == null || lineTotal == null ||
          (qty * unit - lineTotal).abs() > 0.03) continue;
      var description = match.group(1)!.trim();
      String? sku;
      final start = _skuStart.firstMatch(description);
      final end = _skuEnd.firstMatch(description);
      if (start != null) {
        sku = start.group(1)!.trim();
        description = start.group(2)!.trim();
      } else if (end != null) {
        sku = end.group(2)!.trim();
        description = end.group(1)!.trim();
      }
      if (description.isEmpty || RegExp(r'^\d+$').hasMatch(description)) {
        continue;
      }
      // A geometrically reconstructed row can also occur as raw OCR text.
      if (items.any((item) =>
          item['description'] == description && item['sku'] == sku &&
          item['quantity'] == qty && item['total_amount'] == lineTotal)) {
        continue;
      }
      items.add(<String, dynamic>{
        'position': items.length + 1,
        'description': description,
        if (sku != null) 'sku': sku,
        'quantity': qty,
        'unit_price': unit,
        'total_amount': lineTotal,
      });
    }

    // Second pass for column-oriented invoices with label and value on
    // different OCR lines. Never fall back to today's date or summed totals.
    for (var i = 0; i < lines.length; i++) {
      final label = lines[i].trim();
      final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      if (invoiceNumber == null &&
          RegExp(r'^(?:invoice|inv\.?|invoice no\.?|invoice number|inv\.? #|invoice #|receipt #)\s*[:#-]?\s*$',
            caseSensitive: false).hasMatch(label) &&
          RegExp(r'^[A-Z0-9-]{4,25}$', caseSensitive: false).hasMatch(next) &&
          RegExp(r'\d').hasMatch(next) &&
          !RegExp(r'^20\d{2}-\d{1,2}-\d{1,2}$').hasMatch(next)) {
        invoiceNumber = next;
      }
      if (receiptDate == null &&
          RegExp(r'^(?:date|invoice date|receipt date|sale date|sold on)\s*[:#-]?\s*$',
            caseSensitive: false).hasMatch(label)) {
        receiptDate = _date(next);
      }
      if (total == null && _isTotal(label) && _isOnlyAmount(next)) {
        total = _lastMoney(next);
      }
    }

    if (receiptDate == null) {
      // Accept a date without a label only if it is the ONE distinct date
      // in the recognized document. Multiple plausible dates need review.
      final candidates = <String>{};
      for (final line in originalLines) {
        final found = _date(line);
        if (found != null) candidates.add(found);
      }
      if (candidates.length == 1) receiptDate = candidates.single;
    }

    if (receiptDate == null) flags.add('Date needs review');
    if (invoiceNumber == null) flags.add('Invoice number needs review');
    if (total == null) flags.add('Total needs manual entry');
    if (items.isEmpty) flags.add('Part lines need review');
    return <String, dynamic>{
      if (vendor != null) 'vendor_name': vendor,
      if (receiptDate != null) 'receipt_date': receiptDate,
      if (invoiceNumber != null) 'vendor_invoice_number': invoiceNumber,
      if (total != null) 'receipt_total': total,
      if (subtotal != null) 'subtotal': subtotal,
      'items': items,
      'review_flags': flags,
      'extraction_source': 'on_device_ocr',
      'raw_data': <String, dynamic>{
        'ocr_text': ocrText.length > 25000
            ? ocrText.substring(0, 25000) : ocrText,
        'ocr_line_count': positionedLines.length,
        'reconstructed_rows': rowLines.take(120).toList(),
      },
    };
  }

  static String formatDescription(
    Map<String, dynamic> extraction, {
    num? finalAmount,
  }) {
    final descriptions = <String>[];
    final rawItems = extraction['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final description = raw['description']?.toString().trim() ?? '';
        if (description.isNotEmpty && !descriptions.contains(description)) {
          descriptions.add(description);
        }
        if (descriptions.length >= 10) break;
      }
    }
    final vendor = extraction['vendor_name']?.toString().trim() ?? '';
    final invoice = extraction['vendor_invoice_number']?.toString().trim() ?? '';
    final receiptDate = DateTime.tryParse(
      extraction['receipt_date']?.toString() ?? '',
    );
    final dateLabel = receiptDate == null ? '' :
      receiptDate.month.toString() + '/' + receiptDate.day.toString() + '/' +
      receiptDate.year.toString().substring(2);
    final parsed = num.tryParse(extraction['receipt_total']?.toString() ?? '');
    final amount = finalAmount ?? parsed;
    return <String>[
      if (descriptions.isNotEmpty) descriptions.join(', ')
      else if (vendor.isNotEmpty) vendor,
      if (invoice.isNotEmpty) 'Inv. ' + invoice,
      if (dateLabel.isNotEmpty) dateLabel,
      if (amount != null && amount > 0) '\$' + amount.toStringAsFixed(2),
    ].join(' — ');
  }
}
