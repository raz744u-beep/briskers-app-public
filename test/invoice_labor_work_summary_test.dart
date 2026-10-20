import 'dart:async';
import 'dart:io';

import 'package:briskers_app/services/invoice_labor_work_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'copies labor descriptions only, never hours, rates, parts or totals',
    () {
      expect(
        invoiceLaborWorkSummary({
          'kind': 'invoice',
          'total_amount': 1555.75,
          'lines': [
            {
              'line_kind': 'labor',
              'name': 'Labor',
              'description': '  Replace front brakes.  ',
              'quantity': 3.5,
              'unit_price': 125,
              'total_amount': 437.5,
            },
            {
              'line_kind': 'item',
              'name': 'Pads',
              'description': 'Do not copy this part',
              'quantity': 2,
              'unit_price': 100,
            },
            {
              'line_kind': 'discount',
              'name': 'Discount',
              'description': 'Do not copy this discount',
            },
            {
              'line_kind': 'labor',
              'name': 'Road test',
              'description': null,
              'quantity': .5,
              'unit_price': 125,
            },
            {'line_kind': 'labor', 'name': '', 'description': ' '},
            {
              'name': 'Unknown type',
              'description': 'Do not guess this is labor',
            },
          ],
        }),
        'Replace front brakes.\nRoad test',
      );
    },
  );
  test('reads explicitly typed labor in offline item snapshots', () {
    expect(
      invoiceLaborWorkSummary({
        'kind': 'invoice',
        'items': [
          {
            'item_type': 'Labor',
            'name': 'Labor',
            'description': 'Replace rear air springs. Calibrate air suspension',
          },
          {
            'type': 'labor',
            'description': 'Replace airmatic compressor, valve block and filter',
          },
          {
            'type': 'part',
            'description': 'Never copy part descriptions',
          },
          {'name': 'Unclassified line', 'description': 'Do not guess labor'},
        ],
      }),
      'Replace rear air springs. Calibrate air suspension\n'
      'Replace airmatic compressor, valve block and filter',
    );
  });
  test('labor edits and removals recalculate without stale copied descriptions', () {
    final invoice = <String, dynamic>{
      'kind': 'invoice',
      'lines': [
        {'line_kind': 'labor', 'description': 'Replace oil pan gasket'},
        {'line_kind': 'labor', 'description': 'Replace front brakes'},
        {'line_kind': 'part', 'description': 'Oil pan gasket'},
      ],
    };
    const manual = 'Customer approved repair; road test pending.';
    expect(
      appendInvoiceLaborWorkSummary(manual, invoiceLaborWorkSummary(invoice)),
      '$manual\\nReplace oil pan gasket\\nReplace front brakes',
    );
    invoice['lines'] = [
      {'line_kind': 'labor', 'description': 'Reseal oil pan and replace O-ring'},
      {'line_kind': 'part', 'description': 'Oil pan gasket'},
    ];
    expect(
      appendInvoiceLaborWorkSummary(manual, invoiceLaborWorkSummary(invoice)),
      '$manual\\nReseal oil pan and replace O-ring',
    );
    invoice['lines'] = [
      {'line_kind': 'part', 'description': 'Oil pan gasket'},
    ];
    expect(
      appendInvoiceLaborWorkSummary(manual, invoiceLaborWorkSummary(invoice)),
      manual,
    );
  });

  test('estimates and missing labor produce no draft', () {
    expect(
      invoiceLaborWorkSummary({
        'kind': 'estimate',
        'lines': [
          {'line_kind': 'labor', 'description': 'Not an invoice'},
        ],
      }),
      isEmpty,
    );
    expect(invoiceLaborWorkSummary({'kind': 'invoice'}), isEmpty);
    expect(
      invoiceLaborWorkSummary({
        'kind': 'invoice',
        'lines': [null, 'invalid'],
      }),
      isEmpty,
    );
  });
  test('invoice descriptions and appended text are deduplicated', () {
    expect(
      invoiceLaborWorkSummary({
        'kind': 'invoice',
        'lines': [
          {'line_kind': 'labor', 'description': 'Replace brakes'},
          {'line_kind': 'labor', 'description': ' replace   BRAKES '},
          {'line_kind': 'labor', 'description': 'Road test'},
        ],
      }),
      'Replace brakes\nRoad test',
    );
    expect(
      appendInvoiceLaborWorkSummary(
        'My manual note\nReplace brakes',
        'replace brakes\nRoad test\nRoad test',
      ),
      'My manual note\nReplace brakes\nRoad test',
    );
  });
  test('Auto mode falls back only on connectivity failure', () async {
    for (final error in [
      const SocketException('Network down'),
      TimeoutException('Timed out'),
    ]) {
      expect(
        await readInvoiceLaborSource<String>(
          onlineRead: () async => throw error,
          cachedRead: () async => 'Saved labor',
        ),
        'Saved labor',
      );
    }
    var cacheReads = 0;
    await expectLater(
      readInvoiceLaborSource<String>(
        onlineRead: () async => throw StateError('Access denied'),
        cachedRead: () async {
          cacheReads++;
          return 'Private cached labor';
        },
      ),
      throwsStateError,
    );
    expect(cacheReads, 0);
    await expectLater(
      readInvoiceLaborSource<String>(
        onlineRead: () async => throw const SocketException('Network down'),
        cachedRead: () async => 'Saved labor',
        forceOnline: true,
      ),
      throwsA(isA<SocketException>()),
    );
  });
  test('Force Offline never calls the network', () async {
    var networkReads = 0;
    expect(
      await readInvoiceLaborSource<String>(
        onlineRead: () async {
          networkReads++;
          return 'Online';
        },
        cachedRead: () async => 'Saved labor',
        forceOffline: true,
      ),
      'Saved labor',
    );
    expect(networkReads, 0);
  });
}
