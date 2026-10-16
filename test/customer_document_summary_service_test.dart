import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/customer_document_summary_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late CustomerDocumentSummaryService summaries;
  late LocalDocumentDetailCache cache;

  Future<void> document(
    String id, {
    num total = 100,
    num paid = 0,
    num pending = 0,
    String kind = 'invoice',
    String status = 'draft',
    int? closed,
    int version = 1,
    List<Map<String, dynamic>> payments = const [],
  }) async {
    await db.customStatement(
      'INSERT INTO local_documents(id,business_id,customer_id,kind,status,total,document_number,closed_at,row_version) VALUES(?,?,?,?,?,?,?,?,?)',
      [id, 'shop', 'synthetic-customer', kind, status, total, id, closed, version],
    );
    await cache.save('shop', id, {
      'id': id,
      'kind': kind,
      'status': status,
      'document_number': id,
      'total_amount': total,
      'paid_amount': paid,
      'pending_payment': pending,
      'closed_at': closed,
      'row_version': version,
      'payments': payments,
    });
  }

  Future<void> receipt(
    String invoiceId,
    String operation,
    num amount, {
    bool attempted = false,
  }) => db.customStatement(
    "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state) VALUES('shop','invoice_payment_received',?,'record_received_payment',?,'pending')",
    [
      invoiceId,
      jsonEncode({
        'operation_id': operation,
        'amount_cents': (amount * 100).round(),
        'replay_attempted': attempted,
        'method_name': 'Cash',
        'method_id': 'cash',
      }),
    ],
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalDocumentDetailCache(database: db);
    summaries = CustomerDocumentSummaryService(database: db);
  });
  tearDown(() => db.close());

  test('Synthetic open and fully pending invoices normalize without database status changes', () async {
    await document('TEST-INV-OPEN', total: 875.25);
    await document('TEST-INV-PENDING', total: 200, pending: 200);
    await document(
      'estimate',
      kind: 'estimate',
      status: 'accepted',
      total: 1000,
    );
    final rows = await summaries.forCustomer('shop', 'synthetic-customer');
    final views = {
      for (final row in rows) row['id']: DocumentPresentation(row),
    };
    expect(views['TEST-INV-OPEN']!.statusCode, 'open');
    expect(views['TEST-INV-OPEN']!.balanceDueCents, 87525);
    expect(views['TEST-INV-PENDING']!.statusCode, 'pending_close');
    expect(views['TEST-INV-PENDING']!.balanceDueCents, 0);
    expect(views['TEST-INV-PENDING']!.finalizedCents, 0);
    expect(views['estimate']!.statusCode, 'accepted');
    expect(views['estimate']!.balanceDueCents, isNull);
    final stored = await db
        .customSelect("SELECT status FROM local_documents WHERE kind='invoice'")
        .get();
    expect(stored.every((row) => row.read<String>('status') == 'draft'), true);
  });

  test(
    'offline receipts cover balance once, including acknowledged queue rows',
    () async {
      await document('queued');
      await receipt('queued', 'local-operation', 100);
      await document(
        'acknowledged',
        pending: 100,
        payments: [
          {
            'id': 'server-payment',
            'operation_id': 'shared-operation',
            'amount': 100,
            'state': 'pending',
          },
        ],
      );
      await receipt('acknowledged', 'shared-operation', 100);
      final rows = await summaries.forCustomer('shop', 'synthetic-customer');
      for (final row in rows) {
        final view = DocumentPresentation(row);
        expect(view.pendingCents, 10000);
        expect(view.balanceDueCents, 0);
        expect(view.statusCode, 'pending_close');
      }
      // Hydrating repeatedly does not write a projected amount into the cache.
      expect((await cache.load('shop', 'queued'))!['pending_payment'], 0);
      expect(
        (await summaries.forCustomer('shop', 'synthetic-customer')).first['pending_payment'],
        100,
      );
    },
  );

  test(
    'ambiguous attempted receipt cannot claim paid or invent balance',
    () async {
      await document(
        'ambiguous',
        paid: 100,
        payments: [
          {'id': 'unrelated-finalized', 'amount': 100, 'state': 'posted'},
        ],
      );
      await receipt('ambiguous', 'old-operation', 100, attempted: true);
      final view = DocumentPresentation(
        (await summaries.forCustomer('shop', 'synthetic-customer')).single,
      );
      expect(view.requiresReconciliation, true);
      expect(view.fullyCovered, false);
      expect(view.balanceDueCents, isNull);
    },
  );

  test(
    'index newer than cached detail does not show stale numeric balance',
    () async {
      await document('stale');
      await db.customStatement(
        "UPDATE local_documents SET row_version=2,display_status_code='paid' WHERE id='stale'",
      );
      final view = DocumentPresentation(
        (await summaries.forCustomer('shop', 'synthetic-customer')).single,
      );
      expect(view.statusCode, 'pending_close');
      expect(view.balanceDueCents, isNull);
      expect(view.paymentDetailsKnown, false);
    },
  );

  test(
    'closed invoices excluded from active overview and normalized in history',
    () async {
      await document('closed', paid: 100, closed: 123);
      await document('open');
      final active = await summaries.forCustomer('shop', 'synthetic-customer');
      expect(active.map((row) => row['id']), ['open']);
      final history = await summaries.forCustomer(
        'shop',
        'synthetic-customer',
        includeClosed: true,
      );
      expect(
        DocumentPresentation(
          history.singleWhere((row) => row['id'] == 'closed'),
        ).statusCode,
        'closed',
      );
    },
  );

  test(
    'missing cache or payment fields stay unknown rather than assumed unpaid',
    () async {
      await db.customStatement(
        "INSERT INTO local_documents(id,business_id,customer_id,kind,status,total) VALUES('unknown','shop','synthetic-customer','invoice','draft',500)",
      );
      final view = DocumentPresentation(
        (await summaries.forCustomer('shop', 'synthetic-customer')).single,
      );
      expect(view.statusCode, 'open');
      expect(view.balanceDueCents, isNull);
    },
  );
}

