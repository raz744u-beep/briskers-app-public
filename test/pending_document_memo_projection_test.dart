import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/pending_document_memo_rules.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/pending_document_memo_projection.dart';

const _snapshot = <String, dynamic>{
  'id': 'TEST-NOTES-001',
  'business_id': 'synthetic-shop',
  'memo': 'Older server note',
  'row_version': 7,
  'total_amount': 200,
  'paid_amount': 50,
  'pending_payment': 25,
  'signature_current': false,
  'disclaimers': [
    {'body': 'Original disclaimer'},
  ],
};

Map<String, dynamic> _row(int id, Object? memo, {String state = 'pending'}) => {
  'id': id,
  'business_id': 'synthetic-shop',
  'entity_id': 'TEST-NOTES-001',
  'entity_type': 'document_edit',
  'operation': 'memo',
  'state': state,
  'payload_json': jsonEncode({'memo': memo}),
};

Map<String, dynamic> _project(
  Iterable<Map<String, dynamic>> rows, {
  Map<String, dynamic> detail = _snapshot,
}) => projectPendingDocumentMemo(
  detail,
  rows,
  businessId: 'synthetic-shop',
  documentId: 'TEST-NOTES-001',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final state in ['pending', 'inflight', 'conflict']) {
    test(
      '$state note survives stale server refresh without changing finances or versions',
      () {
        final result = _project([
          _row(1, 'Unsynced warranty text', state: state),
        ]);
        expect(result['memo'], 'Unsynced warranty text');
        expect(result['_local_pending_memo'], isTrue);
        expect(result['_local_pending_memo_state'], state);
        for (final field in [
          'total_amount',
          'paid_amount',
          'pending_payment',
          'row_version',
          'disclaimers',
        ]) {
          expect(result[field], _snapshot[field]);
        }
        expect(_snapshot['memo'], 'Older server note');
      },
    );
  }

  test('newest active memo wins regardless of row order or a newer unrelated operation', () {
    final result = _project([
      _row(8, 'Latest edit', state: 'conflict'),
      _row(2, 'First edit'),
      {..._row(90, 'Wrong business'), 'business_id': 'other-shop'},
      {..._row(91, 'Wrong invoice'), 'entity_id': 'other-invoice'},
      {..._row(92, 'Wrong operation'), 'operation': 'warranty'},
      {..._row(93, 'Wrong entity'), 'entity_type': 'other'},
      _row(94, 'Canceled edit', state: 'cancelled'),
      _row(95, 'Acknowledged edit', state: 'synced'),
    ]);
    expect(result['memo'], 'Latest edit');
    expect(result['_local_pending_memo_queue_id'], 8);
  });

  test(
    'explicit null and empty-string clears survive projection and repetition',
    () {
      for (final clear in [null, '']) {
        final rows = [_row(1, 'Earlier edit'), _row(2, clear)];
        final projected = _project(rows);
        expect(projected.containsKey('memo'), isTrue);
        expect(projected['memo'], clear);
        expect(_project(rows, detail: projected), projected);
      }
    },
  );

  test('idempotent cached projection restores server baseline when queue no longer exists', () {
    final rows = [_row(1, 'Local text')];
    final once = _project(rows);
    expect(_project(rows, detail: once), once);
    expect(_project([], detail: once), _snapshot);
    final missingMemo = Map<String, dynamic>.from(_snapshot)..remove('memo');
    final projectedMissing = _project(rows, detail: missingMemo);
    expect(_project([], detail: projectedMissing), missingMemo);
  });

  test(
    'invalid latest payload fails closed rather than silently using older text',
    () {
      for (final bad in ['', '{', '{}', '[]', '{"memo":42}']) {
        expect(
          () => _project([
            _row(1, 'Earlier'),
            {..._row(2, null), 'payload_json': bad},
          ]),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
      }
    },
  );

  test(
    'a mismatched snapshot cannot receive another document or business memo',
    () {
      expect(
        () =>
            _project([_row(1, 'Text')], detail: {..._snapshot, 'id': 'other'}),
        throwsStateError,
      );
      expect(
        () => _project(
          [_row(1, 'Text')],
          detail: {..._snapshot, 'business_id': 'other'},
        ),
        throwsStateError,
      );
    },
  );

  test('projection reads persistent outbox again after database restart and never retires rows', () async {
    final directory = await Directory.systemTemp.createTemp(
      'briskers-notes-test-',
    );
    final file = File('${directory.path}/local.sqlite');
    var database = BriskersLocalDatabase(NativeDatabase(file));
    try {
      for (final row in [
        _row(1, 'First'),
        _row(2, 'Restart-safe local text', state: 'inflight'),
      ]) {
        await database.customStatement(
          '''
          INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json,state,attempt_count,created_at)
          VALUES (?, 'document_edit', ?, 'memo', ?, ?, 3, 1)
        ''',
          [
            row['business_id'],
            row['entity_id'],
            row['payload_json'],
            row['state'],
          ],
        );
      }
      final before = await database
          .customSelect('SELECT * FROM sync_outbox ORDER BY id')
          .get();
      await database.close();
      database = BriskersLocalDatabase(NativeDatabase(file));
      final service = PendingDocumentMemoProjection(database: database);
      final projected = await service.project(
        'synthetic-shop',
        'TEST-NOTES-001',
        _snapshot,
      );
      expect(projected['memo'], 'Restart-safe local text');
      final repeated = await service.project(
        'synthetic-shop',
        'TEST-NOTES-001',
        projected,
      );
      expect(repeated, projected);
      final unrelated = await service.project('other-shop', 'TEST-NOTES-001', {
        ..._snapshot,
        'business_id': 'other-shop',
      });
      expect(unrelated['_local_pending_memo'], isNull);
      final after = await database
          .customSelect('SELECT * FROM sync_outbox ORDER BY id')
          .get();
      expect(
        after.map((row) => row.data).toList(),
        before.map((row) => row.data).toList(),
      );
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
