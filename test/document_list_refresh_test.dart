import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/document_list_refresh.dart';

void main() {
  test('repeated navigation shares one in-flight refresh', () async {
    final refresh = DocumentListRefresh();
    final response = Completer<void>();
    var reads = 0;
    Future<void> read() async {
      reads++;
      await response.future;
    }

    final first = refresh.run(read);
    final others = List.generate(20, (_) => refresh.run(read));
    expect(reads, 1);
    expect(others.every((future) => identical(future, first)), isTrue);
    response.complete();
    await Future.wait([first, ...others]);
    expect(reads, 1);
  });

  test(
    'post-action refresh queues one new pass and waits for fresh data',
    () async {
      final refresh = DocumentListRefresh();
      final responses = [Completer<void>(), Completer<void>()];
      var reads = 0;
      var concurrent = 0;
      var maxConcurrent = 0;
      Future<void> read() async {
        final index = reads++;
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        await responses[index].future;
        concurrent--;
      }

      var completed = false;
      final first = refresh.run(read)..then((_) => completed = true);
      final afterPayment = refresh.run(read, afterCurrent: true);
      final afterDetail = refresh.run(read, afterCurrent: true);
      responses[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 2);
      expect(completed, isFalse);
      expect(maxConcurrent, 1);
      responses[1].complete();
      await Future.wait([first, afterPayment, afterDetail]);
      expect(completed, isTrue);
      expect(reads, 2);
    },
  );

  test(
    'an action during the queued pass still receives a newer pass',
    () async {
      final refresh = DocumentListRefresh();
      final responses = List.generate(3, (_) => Completer<void>());
      var reads = 0;
      Future<void> read() => responses[reads++].future;
      final result = refresh.run(read);
      refresh.run(read, afterCurrent: true);
      responses[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 2);
      refresh.run(read, afterCurrent: true);
      responses[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 3);
      responses[2].complete();
      await result;
    },
  );

  test('failed refresh releases the coalescer for retry', () async {
    final refresh = DocumentListRefresh();
    await expectLater(
      refresh.run(() async => throw StateError('synthetic read failed')),
      throwsStateError,
    );
    var reads = 0;
    await refresh.run(() async => reads++);
    expect(reads, 1);
  });

  test('structural snapshots ignore map key ordering without encoding', () {
    expect(
      documentListDataEquals(
        [
          {
            'id': 'synthetic',
            'paid_amount': 10,
            'nested': {'a': 1, 'b': 2},
          },
        ],
        [
          {
            'nested': {'b': 2, 'a': 1},
            'paid_amount': 10.0,
            'id': 'synthetic',
          },
        ],
      ),
      isTrue,
    );
  });

  test(
    'payment, status, and version changes cannot be skipped as unchanged',
    () {
      final before = <String, dynamic>{
        'id': 'synthetic-invoice',
        'paid_amount': 0,
        'pending_payment': 0,
        'total_amount': 100,
        'display_status_code': 'open',
        'closed_at': null,
        'row_version': 1,
        '_payment_reconciliation_required': false,
      };
      for (final change in <MapEntry<String, dynamic>>[
        const MapEntry('paid_amount', 100),
        const MapEntry('pending_payment', 100),
        const MapEntry('total_amount', 125),
        const MapEntry('display_status_code', 'closed'),
        const MapEntry('closed_at', '2026-10-20T10:00:00Z'),
        const MapEntry('row_version', 2),
        const MapEntry('_payment_reconciliation_required', true),
      ]) {
        expect(
          documentListDataEquals(
            [before],
            [
              {...before, change.key: change.value},
            ],
          ),
          isFalse,
          reason: '${change.key} must trigger a fresh list and cache',
        );
      }
      final missingBalance = Map<String, dynamic>.from(before)
        ..remove('paid_amount');
      expect(documentListDataEquals([before], [missingBalance]), isFalse);
      expect(documentListDataEquals([before], const []), isFalse);
    },
  );

  test(
    'estimate order is latest number first regardless of date or status',
    () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 'old-draft',
          'document_number': 'E-99',
          'status': 'draft',
          'document_date': '2027-01-01',
        },
        {
          'id': 'new-issued',
          'document_number': 'E-2002',
          'status': 'issued',
          'document_date': '2026-01-01',
        },
        {'id': 'middle-draft', 'document_number': 'E-100', 'status': 'draft'},
        {'id': 'unnumbered', 'document_date': '2028-01-01'},
      ];
      final ordered = orderDocumentListRows(rows, estimate: true);
      expect(ordered.map((row) => row['id']), [
        'new-issued',
        'middle-draft',
        'old-draft',
        'unnumbered',
      ]);
      expect(
        rows.first['id'],
        'old-draft',
        reason: 'Do not mutate API snapshots',
      );
      expect(
        ordered
            .where((row) => row['status'] == 'draft')
            .map((row) => row['id']),
        ['middle-draft', 'old-draft'],
      );
    },
  );

  test(
    'invoice order retains working drafts then highest numbered invoices',
    () {
      final ordered = orderDocumentListRows([
        {'id': 'older', 'document_number': 'I-9', 'created_at': '2027-01-01'},
        {'id': 'newer', 'document_number': 'I-100', 'created_at': '2026-01-01'},
        {'id': 'draft', 'created_at': '2025-01-01'},
      ], estimate: false);
      expect(ordered.map((row) => row['id']), ['draft', 'newer', 'older']);
    },
  );
}
