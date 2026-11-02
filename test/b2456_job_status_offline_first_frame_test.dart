import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/services/job_status_local_events.dart';
import 'package:briskers_app/widgets/job_financial_status_card.dart';

void main() {
  test('A locally committed status change is published immediately and scoped', () async {
    final received = <LocalJobStatusChanged>[];
    final subscription = LocalJobStatusEvents.changes.listen(received.add);
    LocalJobStatusEvents.committed(const LocalJobStatusChanged(
      businessId: 'synthetic-business',
      jobId: 'synthetic-j-35',
      code: 'completed',
      name: 'Completed',
      colorHex: '#159447',
    ));
    expect(received, hasLength(1));
    expect(received.single.jobId, 'synthetic-j-35');
    expect(received.single.businessId, 'synthetic-business');
    expect(received.single.code, 'completed');
    await subscription.cancel();
  });

  test('Cached financial labels require actual positive invoice totals and confirmed receipts', () {
    expect(cachedVerifiedJobPaymentState(const []), isNull);
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'invoice', 'total_amount': 100},
    ]), isNull);
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'estimate', 'total_amount': 100, 'paid_amount': 0},
    ]), isNull);
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'invoice', 'total_amount': 0, 'paid_amount': 0},
    ]), isNull);
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'invoice', 'total_amount': 100, 'paid_amount': 100},
    ]), 'paid');
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'invoice', 'total_amount': 100, 'paid_amount': 50},
    ]), 'awaiting_payment');
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'invoice', 'total_amount': 100,
       'paid_amount': 70, 'pending_payment': 30},
    ]), 'awaiting_clearance');
    expect(cachedVerifiedJobPaymentState([
      {'kind': 'invoice', 'total_amount': 100, 'paid_amount': 100},
      {'kind': 'invoice', 'total_amount': 50},
    ]), isNull, reason: 'Never infer Paid with a missing receipt ledger.');
    expect(savedJobFinancialStatus('paid'), 'Paid');
    expect(savedJobFinancialStatus(null), isNull);
  });

  testWidgets('Completed Job financial status stays one line with valid offline snapshot', (tester) async {
    Widget card(String? state) => MaterialApp(
      home: Scaffold(
        body: Column(children: [
          JobFinancialStatusCard(
            status: savedJobFinancialStatus(state),
            offline: true,
          ),
          const Text('Next tile', key: ValueKey('next-tile')),
        ]),
      ),
    );
    await tester.pumpWidget(card(null));
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    final top = tester.getTopLeft(find.byKey(const ValueKey('next-tile'))).dy;
    await tester.pumpWidget(card('paid'));
    expect(find.text('Paid'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('next-tile'))).dy, top);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('Jobs status and offline car actions do not wait on a remote reload', () {
    final list = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final detail = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final admin = File('lib/services/offline_job_admin_service.dart').readAsStringSync();
    final event = File('lib/services/job_status_local_events.dart').readAsStringSync();
    expect(list, contains('LocalJobStatusEvents.changes.listen('));
    expect(list, contains('void _applyLocalStatus(LocalJobStatusChanged event)'));
    expect(list, contains("_selectedStatus == '__open__'"));
    expect(list, contains("'status': event.code"));
    expect(list, contains('updated.removeAt(index);'));
    expect(list, contains('_pendingStatusIds.add(jobId);'));
    expect(list, contains('_applyLocalStatus(optimistic);'));
    expect(list, contains('unawaited(_load(refreshRemote: false))'));
    expect(admin, contains('LocalJobStatusEvents.committed('));
    expect(event, contains('StreamController<LocalJobStatusChanged>.broadcast(sync: true)'));
    expect(detail, contains('++_loadEpoch;'));
    expect(detail, contains("setState(() => _busy = false);"));
    expect(detail, contains('await _offlineJobAdmin.queueStatus('));
    expect(detail, contains('unawaited(() async {'));
    expect(detail, contains('bool get _canEditVehicleLocally'));
    expect(detail, contains("_job?['_local_snapshot'] == true"));
    expect(detail, contains('bool get _showVehicleChevron'));
    expect(detail, contains('showChevron: _showVehicleChevron'));
    expect(detail, contains('LocalCustomerRepository().customerDetail('));
    expect(detail, contains('replaceVehicle: true'));
    expect(admin, contains('vehicle_label = CASE WHEN ? THEN ? ELSE vehicle_label END'));
    expect(admin, contains('vehicle_vin = CASE WHEN ? THEN ? ELSE vehicle_vin END'));
    expect(detail, contains('_hydrateCachedFinancialStatus(epoch, documents)'));
    expect(detail, contains('cachedVerifiedJobPaymentState(verified)'));
    expect(detail, contains('if (total <= 0) return null;'));
  });
}
