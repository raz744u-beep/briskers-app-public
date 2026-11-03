import 'package:briskers_app/services/local_receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Worldpac fixture preserves descriptions, part numbers and totals', () {
    final extracted = LocalReceiptParser.parse('''
WORLDPAC
Invoice 74966713
Date 10/27/2026
34 11 6 886 478 Brake Disc 2 56.70 113.40
34 11 6 852 253 Brake Pad Set 1 62.25 62.25
34 35 6 792 567 Brake Pad Sensor 1 15.70 15.70
TOTAL \$191.35
''');
    expect(extracted['vendor_name'], 'Worldpac');
    expect(extracted['vendor_invoice_number'], '74966713');
    expect(extracted['receipt_date'], '2026-10-27');
    expect(extracted['receipt_total'], 191.35);
    final items = (extracted['items'] as List).cast<Map<String, dynamic>>();
    expect(items, hasLength(3));
    expect(items[0]['description'], 'Brake Disc');
    expect(items[0]['sku'], '34 11 6 886 478');
    expect(items[0]['quantity'], 2);
    expect(items[0]['unit_price'], 56.7);
    expect(LocalReceiptParser.formatDescription(extracted),
        'Brake Disc, Brake Pad Set, Brake Pad Sensor — Inv. 74966713 — 10/27/26 — \$191.35');
  });

  test('AutoZone leading-zero invoice and trailing SKU', () {
    final extracted = LocalReceiptParser.parse('''
AUTOZONE
Invoice # 04290190370
Date: 10/24/26
NGK Laser Iridium NGK Spark Plug 96008 6 18.00 108.00
Engine Air Filter STP Air Filter SA6900 2 11.65 23.30
Grand Total \$131.30
''');
    expect(extracted['vendor_name'], 'AutoZone');
    expect(extracted['vendor_invoice_number'], '04290190370');
    final items = extracted['items'] as List;
    expect(items, hasLength(2));
    expect((items[0] as Map)['sku'], '96008');
    expect((items[1] as Map)['sku'], 'SA6900');
    expect(LocalReceiptParser.formatDescription(extracted),
      'NGK Laser Iridium NGK Spark Plug, Engine Air Filter STP Air Filter — Inv. 04290190370 — 10/24/26 — \$131.30');
  });

  test('Peake BMW hyphenated part numbers', () {
    final extracted = LocalReceiptParser.parse('''
Peake BMW
INVOICE: 603162
10/23/2026
21-52-6-864-478 Connecting link 1 21.50 21.50
21-52-1-164-603 Grommet 1 4.62 4.62
TOTAL 26.12
''');
    expect(extracted['vendor_name'], 'Peake BMW');
    expect((extracted['items'] as List), hasLength(2));
    expect(((extracted['items'] as List).first as Map)['sku'],
      '21-52-6-864-478');
    expect(LocalReceiptParser.formatDescription(extracted),
      'Connecting link, Grommet — Inv. 603162 — 10/23/26 — \$26.12');
  });

  test('receipt date and invoice total labels never become invoice numbers', () {
    final extracted = LocalReceiptParser.parse('''
Worldpac
Receipt date 10/27/2026
Invoice total 191.35
''');
    expect(extracted.containsKey('vendor_invoice_number'), isFalse);
    expect(extracted['receipt_date'], '2026-10-27');
    expect(extracted['receipt_total'], 191.35);
  });

  test('Worldpac column layout restores separated SKU, description and price', () {
    final parsed = LocalReceiptParser.parse('''
WORLDPAC
Invoice
74966713
Date
10/27/2026
34 11 6 886 478
Brake Disc
2
56.70
113.40
Total
191.35
''', positionedLines: const [
      ReceiptOcrFragment(text: 'WORLDPAC', left: 20, top: 5, height: 12),
      ReceiptOcrFragment(text: 'Invoice', left: 20, top: 25, height: 12),
      ReceiptOcrFragment(text: '74966713', left: 20, top: 45, height: 12),
      ReceiptOcrFragment(text: 'Date', left: 20, top: 65, height: 12),
      ReceiptOcrFragment(text: '10/27/2026', left: 20, top: 85, height: 12),
      ReceiptOcrFragment(text: '34 11 6 886 478', left: 20, top: 115, height: 12),
      ReceiptOcrFragment(text: 'Brake Disc', left: 180, top: 114, height: 12),
      ReceiptOcrFragment(text: '2', left: 395, top: 115, height: 12),
      ReceiptOcrFragment(text: '56.70', left: 445, top: 115, height: 12),
      ReceiptOcrFragment(text: '113.40', left: 525, top: 115, height: 12),
      ReceiptOcrFragment(text: 'TOTAL', left: 20, top: 145, height: 12),
      ReceiptOcrFragment(text: '191.35', left: 525, top: 146, height: 12),
    ]);
    expect(parsed['vendor_name'], 'Worldpac');
    expect(parsed['vendor_invoice_number'], '74966713');
    expect(parsed['receipt_date'], '2026-10-27');
    expect(parsed['receipt_total'], 191.35);
    final items = parsed['items'] as List;
    expect(items, hasLength(1));
    expect((items.first as Map)['description'], 'Brake Disc');
    expect((items.first as Map)['sku'], '34 11 6 886 478');
    expect((items.first as Map)['quantity'], 2);
    expect((parsed['raw_data'] as Map)['ocr_line_count'], 12);
  });

  test('standalone invoice fields work without location coordinates', () {
    final parsed = LocalReceiptParser.parse('''
Worldpac
Invoice
74966713
Date
10/27/2026
Total
191.35
''');
    expect(parsed['vendor_invoice_number'], '74966713');
    expect(parsed['receipt_date'], '2026-10-27');
    expect(parsed['receipt_total'], 191.35);
  });

  test('do not mistake subtotal or line total for missing printed total', () {
    final parsed = LocalReceiptParser.parse('''
Worldpac
Invoice 74966713
Brake Disc 2 56.70 113.40
Subtotal 113.40
Tax 7.92
''');
    expect(parsed.containsKey('receipt_total'), isFalse);
    expect(parsed['subtotal'], 113.40);
    expect(parsed['items'], hasLength(1));
  });

  test('missing or weak OCR never fabricates invoice number or total', () {
    final extracted = LocalReceiptParser.parse('Brake repair\nSomething unreadable');
    expect(extracted.containsKey('vendor_invoice_number'), isFalse);
    expect(extracted.containsKey('receipt_total'), isFalse);
    expect(extracted['items'], isEmpty);
    expect((extracted['review_flags'] as List), isNotEmpty);
  });

  test('invalid line math and invalid dates are not accepted', () {
    final extracted = LocalReceiptParser.parse('''
WORLDPAC
DATE 02/31/2026
Item ZZ123 2 18.00 100.00
TOTAL \$100.00
''');
    expect(extracted.containsKey('receipt_date'), isFalse);
    expect(extracted['items'], isEmpty);
    expect(extracted['receipt_total'], 100);
  });

  test('formatter takes 10 distinct descriptions, not part SKUs', () {
    final extracted = <String, dynamic>{
      'vendor_name': 'Worldpac',
      'vendor_invoice_number': '0001234',
      'receipt_date': '2026-10-27',
      'receipt_total': 100,
      'items': [
        for (var i = 1; i <= 12; i++)
          {'description': 'Part $i', 'sku': 'SKU$i'},
        {'description': 'Part 1', 'sku': 'OTHER'},
      ],
    };
    final description = LocalReceiptParser.formatDescription(extracted);
    expect(description, contains('Part 10'));
    expect(description, isNot(contains('Part 11')));
    expect(description, isNot(contains('SKU')));
    expect(description, endsWith('Inv. 0001234 — 10/27/26 — \$100.00'));
  });

  test('formatter falls back to separate vendor label only without items', () {
    final summary = LocalReceiptParser.formatDescription({
      'vendor_name': 'Worldpac', 'items': [], 'receipt_total': 26.12,
    });
    expect(summary, 'Worldpac — \$26.12');
  });
}
