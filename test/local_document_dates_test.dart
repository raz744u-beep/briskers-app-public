import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline invoices preserve issue dates rather than import dates',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final repository = LocalDocumentRepository(database: db);
    const business = 'test-shop';
    const importTime = '2026-10-08T12:50:53Z';

    await repository.replaceFromServer(
      business,
      [
        {
          'id': 'invoice-5969',
          'business_id': business,
          'kind': 'invoice',
          'document_number': '5969',
          'document_date': '2026-02-20',
          'created_at': importTime,
          'status': 'issued',
          'total_amount': 197.78,
        },
        {
          'id': 'invoice-6330',
          'business_id': business,
          'kind': 'invoice',
          'document_number': '6330',
          'document_date': '2026-10-08',
          'created_at': importTime,
          'status': 'issued',
          'total_amount': 820.66,
        },
        {
          'id': 'invoice-5180',
          'business_id': business,
          'kind': 'invoice',
          'document_number': '5180',
          'document_date': '2026-12-25',
          'future_date_flag': true,
          'created_at': importTime,
          'status': 'issued',
          'total_amount': 1130.74,
        },
      ],
      kind: 'invoice',
    );

    final offline = await repository.listByKind(business, kind: 'invoice');
    final byNumber = {
      for (final row in offline) row['document_number']: row,
    };

    expect(byNumber['5969']?['document_date'], '2026-02-20');
    expect(byNumber['6330']?['document_date'], '2026-10-08');
    // Do not silently rewrite an anomalous MobileBiz source date.
    expect(byNumber['5180']?['document_date'], '2026-12-25');
    expect(byNumber['5180']?['future_date_flag'], isTrue);
    expect(byNumber['6330']?['future_date_flag'], isFalse);
    expect(byNumber['5969']?['created_at'], isNotNull);

    await repository.upsertFromServer(business, [
      {
        'id': 'invoice-5969',
        'business_id': business,
        'kind': 'invoice',
        'document_number': '5969',
        'document_date': '2026-02-21',
        'created_at': importTime,
        'status': 'issued',
        'total_amount': 197.78,
      },
    ]);

    final refreshed = await repository.listByKind(business, kind: 'invoice');
    final row = refreshed.singleWhere(
      (invoice) => invoice['document_number'] == '5969',
    );
    expect(row['document_date'], '2026-02-21');

    await db.close();
  });

  test('missing invoice dates never silently become imported-at dates',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final repository = LocalDocumentRepository(database: db);
    await repository.upsertFromServer('test-shop', [
      {
        'id': 'undated',
        'kind': 'invoice',
        'document_number': '6000',
        'created_at': '2026-10-08T12:50:53Z',
        'status': 'issued',
        'total_amount': 10,
      },
    ]);

    final cached = await repository.listByKind(
      'test-shop',
      kind: 'invoice',
    );
    expect(cached.single['document_date'], isNull);
    await db.close();
  });
}
