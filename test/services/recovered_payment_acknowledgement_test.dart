import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/recovered_payment_acknowledgement.dart';

class _ReadOnlyApi extends BriskersApi {
  _ReadOnlyApi(this.response);
  final Map<String,dynamic> response;
  int reads = 0;
  @override
  Future<Map<String,dynamic>> documentDetail(
      String businessId, String documentId) async {
    reads++;
    return response;
  }
}

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db = BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());
  const b = 'test-shop', invoice = 'invoice-test',
      operation = 'receipt-test', receipt = 'remote-receipt-test',
      method = 'card-test';
  Map<String,dynamic> server() => {
    'id':invoice, 'status':'issued',
    'payments':[{
      'id':receipt,'operation_id':operation,
      'amount':30.00,'method_id':method,'payment_date':'2026-10-19',
    }],
  };
  Future<void> seed({String state='conflict'}) async {
    await db.customStatement(
      '''INSERT INTO sync_outbox(business_id,entity_type,entity_id,
        operation,payload_json,state,attempt_count,created_at)
        VALUES(?, 'invoice_payment_received', ?, 'record_received_payment',
        ?, ?, 0, 1793301845)''',
      [b, invoice, jsonEncode({
        'operation_id':operation,'invoice_id':invoice,
        'amount_cents':3000,'method_id':method,'payment_date':'2026-10-19',
      }),state],
    );
  }
  Future<void> acknowledge(_ReadOnlyApi api, {bool owner=true}) =>
      RecoveredPaymentAcknowledgement(database:db,api:api).acknowledge(
        isOwner:owner,businessId:b,invoiceId:invoice,
        paymentOperationId:operation,paymentId:receipt,
        amountCents:3000,methodId:method,paymentDate:'2026-10-19',
      );
  Future<int> remaining() async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id=?',
      variables:[const Variable<String>(b)],
    ).getSingle();
    return row.read<int>('n');
  }

  test('exact fresh server receipt retires only quarantined operation',() async {
    await seed();
    final api = _ReadOnlyApi(server());
    await acknowledge(api);
    expect(api.reads,1);
    expect(await remaining(),0);
  });
  test('non-Owner never reads or changes receipt',() async {
    await seed();
    final api=_ReadOnlyApi(server());
    await expectLater(acknowledge(api,owner:false),throwsStateError);
    expect(api.reads,0);
    expect(await remaining(),1);
  });
  test('missing server operation ID fails closed',() async {
    await seed();
    final api=_ReadOnlyApi(server()..['payments']=[{
      'id':receipt,'amount':30.00,'method_id':method,
      'payment_date':'2026-10-19',
    }]);
    await expectLater(acknowledge(api),throwsStateError);
    expect(await remaining(),1);
  });
  test('duplicate server receipts fail closed',() async {
    await seed();
    final details=server();
    details['payments']=[...details['payments'] as List,
        ...details['payments'] as List];
    await expectLater(acknowledge(_ReadOnlyApi(details)),throwsStateError);
    expect(await remaining(),1);
  });
  test('server read outage preserves quarantined financial operation',() async {
    await seed();
    final api=_ReadOnlyApi(server()..remove('payments'));
    await expectLater(acknowledge(api),throwsStateError);
    expect(api.reads,1);
    expect(await remaining(),1);
    final state=await db.customSelect(
      "SELECT state,payload_json FROM sync_outbox WHERE business_id=?",
      variables:[const Variable<String>(b)],
    ).getSingle();
    expect(state.read<String>('state'),'conflict');
    final original=jsonDecode(state.read<String>('payload_json')) as Map;
    expect(original['operation_id'],operation);
    expect(original['amount_cents'],3000);
  });
  test('unquarantined payment remains untouched',() async {
    await seed(state:'pending');
    await expectLater(acknowledge(_ReadOnlyApi(server())),throwsStateError);
    expect(await remaining(),1);
  });
}
