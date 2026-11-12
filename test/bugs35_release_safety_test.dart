import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/job_task_summary.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_recurring_repository.dart';
import 'package:briskers_app/services/recurring_financial_projection.dart';
import 'package:briskers_app/services/offline_invoice_finalization.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdempotentFinalizer extends BriskersApi {
  final requests = <String, String>{};
  final paidReceipts = <String>{};
  final calls = <String>[];
  bool loseCloseReply = true;
  @override
  Future<Map<String, dynamic>> finalizeInvoiceOnce(
    String business,
    String invoice,
    String operation,
    Map<String, dynamic> request,
  ) async {
    calls.add(operation);
    final payload = jsonEncode(request);
    if (requests.containsKey(operation)) expect(requests[operation], payload);
    requests[operation] = payload;
    for (final receipt in request['receipts'] as List) {
      paidReceipts.add(receipt['id'] as String);
    }
    if (request['close'] == true && loseCloseReply) {
      loseCloseReply = false;
      throw StateError('Reply lost after commit');
    }
    return {
      'operation_id': operation,
      'invoice_id': invoice,
      'finalized': true,
      'closed': request['close'] == true,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });
  test(
    'Nov 8 paid history is editable without changing credits or payment coverage, survives restart',
    () async {
      final directory = await Directory.systemTemp.createTemp('bugs35-history');
      final file = File('${directory.path}/shop.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      await LocalDocumentDetailCache.initialize(db);
      var repo = LocalPayrollRepository(
        db,
        business: 'shop',
        owner: true,
        deviceId: 'owner',
      );
      await repo.prepare();
      await repo.bindPaymentAuthority(
        writerDeviceId: 'owner',
        assertVerifiedPairing: () {},
      );
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES('job','shop','owner','Repair','closed','J-40')",
      );
      await db.customStatement(
        "INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-09','invoice','shop','job','invoice','6359')",
      );
      await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {
        'id': 'invoice',
        'job_id': 'job',
        'kind': 'invoice',
        'status': 'closed',
        'total_amount': 100,
        'paid_amount': 100,
        'pending_payment': 0,
        'lines': [
          {
            'id': 'labor',
            'line_kind': 'labor',
            'description': 'Replace struts',
            'quantity': 3.6,
          },
        ],
      });
      await repo.saveEmployeeCompensation(
        employee: 'chris',
        name: 'Chris',
        rate: 4000,
        weeklyBase: false,
      );
      await repo.saveEmployeeCompensation(
        employee: 'kam',
        name: 'Kam',
        rate: 4000,
        weeklyBase: false,
      );
      await repo.setMainMechanic('job', 'chris', 'Chris');
      final allocation = (await repo.work()).single;
      expect(allocation['state'], 'Open');
      await repo.recordAllocatedTime(
        allocation['id'] as String,
        'Done',
        216,
        216,
        '2026-11-09',
      );
      final earned = (await repo.work()).single;
      await repo.verify(
        operation: 'paid-once',
        employee: 'chris',
        week: '2026-11-09',
        date: '2026-11-09',
        method: 'Cash',
        selected: [
          {...earned, 'pay_minutes': 216},
        ],
        base: 0,
        hourlyAdjustment: 0,
        adjustmentReason: '',
        repayment: 0,
        confirmedNet: 14400,
      );
      await db.customStatement(
        "UPDATE local_documents SET document_date='2026-11-08' WHERE id='invoice'",
      );
      Future<String> ledger() async => jsonEncode([
        for (final table in [
          'local_mechanic_work_credits_v1',
          'regular_payroll_work_coverage',
          'regular_payroll_payments',
        ])
          (await db.customSelect('SELECT * FROM $table').get())
              .map((r) => r.data)
              .toList(),
      ]);
      final before = await ledger();
      await repo.editAllocation(
        task: allocation['task_id'] as String,
        previous: 'chris',
        employee: 'kam',
        name: 'Kam',
        minutes: 240,
      );
      final corrected = (await repo.work()).single;
      expect(corrected['state'], 'Done');
      expect(corrected['employee_id'], 'kam');
      expect(corrected['estimated_minutes'], 240);
      expect(corrected['paid_minutes'], 216);
      expect(await ledger(), before);
      await expectLater(
        repo.reviewUnpaidCarry('kam', allocation['id'] as String),
        throwsStateError,
      );
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      expect((await repo.work()).single['estimated_minutes'], 240);
      expect(await ledger(), before);
      expect((await JobTaskSummary(db).hours('shop', ['job']))['job'], {
        'Kam': 240,
      });
      await repo.assignExistingService(
        job: 'job',
        invoice: 'invoice',
        line: 'labor',
        employee: 'second',
        name: 'Second',
        rate: 4000,
        minutes: 60,
      );
      final added = (await repo.work()).singleWhere(
        (r) => r['employee_id'] == 'second',
      );
      expect(added['state'], 'Done');
      expect(added['actual_minutes'], 0);
      expect(added['remaining_cents'], 0);
      expect((await JobTaskSummary(db).progress('shop', 'job')).done, 1);
      expect(await repo.historyWithWork('chris'), hasLength(1));
      await db.close();
      await directory.delete(recursive: true);
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
    },
  );
  test(
    'historical general tasks complete once; future and newly added reminders stay active',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      await repo.prepare();
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status,created_at) VALUES('job','shop','owner','Repair','open','2026-11-08T12:00:00Z')",
      );
      for (final id in [1, 2]) {
        await db.customStatement(
          "INSERT INTO regular_payroll_shop_tasks(id,business_id,employee_id,description,category,due_at) VALUES(?,'shop','chris','Reminder','General',?)",
          [
            id,
            id == 1 ? null : DateTime.utc(2026, 11, 20).millisecondsSinceEpoch,
          ],
        );
        await db.customStatement(
          "INSERT INTO regular_payroll_shop_task_jobs VALUES('shop',?,'job')",
          [id],
        );
      }
      final initial = await repo.shopTasks('chris');
      expect(initial.singleWhere((r) => r['id'] == 1)['status'], 'done');
      expect(initial.singleWhere((r) => r['id'] == 2)['status'], 'planned');
      await repo.addShopTask('chris', 'New reminder', 'General', job: 'job');
      expect(
        (await repo.shopTasks(
          'chris',
        )).singleWhere((r) => r['description'] == 'New reminder')['status'],
        'planned',
      );
      expect((await JobTaskSummary(db).progress('shop', 'job')).done, 1);
      await repo.setShopTaskStatus('chris', 1, 'planned');
      expect(
        (await repo.shopTasks('chris')).every((r) => r['status'] == 'planned'),
        isTrue,
      );
    },
  );
  test(
    'Cintas cached fields adopt original ID, edit amount, preserve photos and history on empty server refresh',
    () async {
      final directory = await Directory.systemTemp.createTemp('bugs35-cintas');
      final file = File('${directory.path}/shop.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      var cache = LocalFinancialCache(database: db);
      OfflineRecurringRepository repository() => OfflineRecurringRepository(
        database: db,
        businessId: 'shop',
        userId: 'owner',
        currentUserId: () => 'owner',
        canRead: () => true,
        canWrite: () => true,
        projectOccurrence: const RecurringFinancialProjection('shop').call,
      );
      final rule = <String, dynamic>{
        'id': 'cintas',
        'business_id': 'shop',
        'direction': 'expense',
        'vendor_id': 'vendor',
        'account_id': 'checking',
        'category_id': 'uniforms',
        'amount_minor': 10529,
        'frequency': 'weekly',
        'interval_count': 1,
        'next_date': '2026-11-11',
        'is_repeating': true,
      };
      await cache.saveTransactions('shop', [
        {
          'id': 'historical',
          'business_id': 'shop',
          'amount': 80,
          'direction': 'expense',
          'date': '2026-10-28',
        },
        {
          ...rule,
          'id': 'nov4-original',
          'date': '2026-11-04',
          'amount': 105.29,
          'counterparty': {'id': 'vendor', 'name': 'Cintas'},
          'recurring_rule_id': 'cintas',
          'recurring_occurrence_date': '2026-11-04',
          'recurring_rule': rule,
          'attachments': [
            {'id': 'old-photo', 'local_file_path': '/original.jpg'},
          ],
        },
      ]);
      final saved = (await cache.loadTransactionForEdit(
        'shop',
        'nov4-original',
      ))!;
      expect(saved['amount'], 105.29);
      expect(saved['account_id'], 'checking');
      var repo = repository();
      await repo.adoptSavedExpense(saved);
      await repo.editSavedExpense('nov4-original', {'amount_minor': 11000});
      await OfflineFinancialWriteService(
        database: db,
        cache: cache,
        mediaDirectoryProvider: () async => directory,
      ).attachRecurringReceipts(
        'shop',
        'nov4-original',
        receipts: [
          {
            'bytes': Uint8List.fromList([1, 2, 3, 4]),
            'filename': 'cintas.jpg',
            'mime_type': 'image/jpeg',
          },
        ],
        assertAuthorized: () {},
      );
      expect(await repo.generateThrough('2026-11-18'), 2);
      expect(await repo.generateThrough('2026-11-18'), 0);
      await cache.mergeServerTransactions('shop', []);
      expect(await cache.loadTransactions('shop'), hasLength(4));
      final edited = (await cache.loadTransactionForEdit(
        'shop',
        'nov4-original',
      ))!;
      expect(edited['amount'], 110);
      expect((edited['attachments'] as List).first['id'], 'old-photo');
      expect(edited['attachments'], hasLength(2));
      final photo = (edited['attachments'] as List).last as Map;
      expect(await File(photo['local_file_path'] as String).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect(
        await db
            .customSelect(
              "SELECT * FROM sync_outbox WHERE entity_type='financial_create'",
            )
            .get(),
        isEmpty,
      );
      await expectLater(
        repo.adoptSavedExpense({...saved, 'id': 'duplicate'}),
        throwsStateError,
      );
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      cache = LocalFinancialCache(database: db);
      repo = repository();
      expect(
        (await cache.loadTransactionForEdit(
          'shop',
          'nov4-original',
        ))!['amount'],
        110,
      );
      expect(await repo.generateThrough('2026-11-18'), 0);
      expect(await cache.loadTransactions('shop'), hasLength(4));
      await db.close();
      await directory.delete(recursive: true);
    },
  );
  test(
    'close after finalize uses a durable no-payment followup through lost response and restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bugs35-finalize',
      );
      final file = File('${directory.path}/shop.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      await LocalDocumentDetailCache.initialize(db);
      await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {
        'id': 'invoice',
        'kind': 'invoice',
        'total_amount': 100,
        'paid_amount': 0,
        'pending_payment': 100,
        'payments': [
          {
            'id': 'receipt',
            'state': 'pending',
            'amount': 100,
            'payment_method_id': 'cash',
            'payment_date': '2026-11-10',
          },
        ],
      });
      final api = IdempotentFinalizer();
      var service = OfflineInvoiceFinalization(database: db, api: api);
      await service.save('shop', ['invoice'], isOwner: true, close: false);
      final original =
          (await db
                  .customSelect(
                    'SELECT operation_id,payload FROM invoice_finalization_intents_v1',
                  )
                  .getSingle())
              .data;
      await service.save('shop', ['invoice'], isOwner: true, close: true);
      await service.save('shop', ['invoice'], isOwner: true, close: true);
      expect(
        (await db
                .customSelect(
                  'SELECT operation_id,payload FROM invoice_finalization_intents_v1',
                )
                .getSingle())
            .data,
        original,
      );
      await service.flush('shop');
      expect(await service.state('shop', 'invoice'), 'review');
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      service = OfflineInvoiceFinalization(database: db, api: api);
      await service.retry('shop', 'invoice', isOwner: true);
      expect(await service.state('shop', 'invoice'), 'confirmed');
      expect(api.requests, hasLength(2));
      expect(api.paidReceipts, {'receipt'});
      expect(api.calls, hasLength(4));
      final close = jsonDecode(api.requests.values.last) as Map;
      expect(close['receipts'], isEmpty);
      expect(close['paid_cents'], 10000);
      await db.close();
      await directory.delete(recursive: true);
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
    },
  );
}
