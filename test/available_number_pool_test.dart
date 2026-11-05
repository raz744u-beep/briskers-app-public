import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_number_allocator.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';

class _Store implements OwnerEnrollmentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late Directory dir;
  late LocalOwnerAuthorization authority;
  late LocalOwnerGrant grant;
  const identity = OwnerSessionIdentity('owner', 'session');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('available-numbers-');
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    BriskersConnectionModeController.instance.useSafeOfflineFallback();
    authority = LocalOwnerAuthorization(
      store: _Store(), currentIdentity: () => identity,
      verifyOwner: (b) async => VerifiedOwnerEnrollment(identity, b),
      verifyLocalOwner: (b) async => VerifiedOwnerEnrollment(identity, b),
      authenticateDevice: () async => true,
    );
    grant = await authority.authorizeLocal('shop');
    final numbers = LocalNumberAllocator(db);
    for (final kind in ['invoice', 'job']) {
      await numbers.allocate('shop', kind, 'old', requested: 34);
      await numbers.allocate('shop', kind, 'later', requested: 45);
      await numbers.release('shop', kind, 'old', previousNumber: 34);
    }
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<String> create({int? invoice = 34, int? job = 34}) =>
      OfflineDocumentDraftService(database: db).createQuickInvoice(
        'shop', customerId: 'customer', customerName: 'Synthetic customer',
        vehicleId: 'vehicle', vehicleLabel: 'Synthetic vehicle',
        reuseInvoiceNumber: invoice, reuseJobNumber: job, reuseGrant: grant,
      );

  test('pool contains explicit releases only, scoped by shop and kind', () async {
    final numbers = LocalNumberAllocator(db);
    expect(await numbers.availableNumbers('shop', 'invoice'), [34]);
    expect(await numbers.availableNumbers('shop', 'job'), [34]);
    expect(await numbers.availableNumbers('other', 'invoice'), isEmpty);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) "
      "VALUES('occupied','shop','full','Test','open','J34')");
    expect(await numbers.availableNumbers('shop', 'job'), isEmpty);
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,kind,status,document_number) "
      "VALUES('occupied','shop','invoice','issued','I-34')");
    expect(await numbers.availableNumbers('shop', 'invoice'), isEmpty);
  });

  test('reuse persists once through restart and cannot be offered again', () async {
    final id = await create();
    final doc = await db.customSelect("SELECT * FROM local_documents").getSingle();
    expect(doc.read<String>('id'), id);
    expect(doc.read<String>('document_number'), '34');
    expect(doc.read<String>('customer_id'), 'customer');
    final job = await db.customSelect("SELECT * FROM local_jobs").getSingle();
    expect(job.read<String>('job_number'), 'J-34');
    expect(job.read<String>('vehicle_id'), 'vehicle');
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    expect(await LocalNumberAllocator(db).availableNumbers('shop', 'invoice'), isEmpty);
    expect(await LocalNumberAllocator(db).availableNumbers('shop', 'job'), isEmpty);
    await expectLater(create(), throwsStateError);
    expect((await db.customSelect("SELECT * FROM local_documents").get()).length, 1);
  });

  test('invoice and job choices are independent', () async {
    await create(job: null);
    final job = await db.customSelect("SELECT job_number FROM local_jobs").getSingle();
    expect(job.read<String>('job_number'), 'J-46');
    expect(await LocalNumberAllocator(db).availableNumbers('shop', 'job'), [34]);
  });

  test('stale second choice rolls back invoice reservation and all creation', () async {
    await LocalNumberAllocator(db).allocate('shop', 'job', 'racer', requested: 34);
    await expectLater(create(), throwsStateError);
    expect(await LocalNumberAllocator(db).availableNumbers('shop', 'invoice'), [34]);
    expect(await db.customSelect("SELECT * FROM local_documents").get(), isEmpty);
    expect(await db.customSelect("SELECT * FROM sync_outbox").get(), isEmpty);
  });

  test('expired Owner authorization leaves numbers and records unchanged', () async {
    authority.lock();
    await expectLater(create(), throwsStateError);
    expect(await LocalNumberAllocator(db).availableNumbers('shop', 'invoice'), [34]);
    expect(await db.customSelect("SELECT * FROM local_documents").get(), isEmpty);
  });
}
