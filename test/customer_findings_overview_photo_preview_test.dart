import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/customer_finding_overview_service.dart';
import 'package:briskers_app/widgets/customer_findings_overview_row.dart';

class _FakeOverview extends CustomerFindingOverviewService {
  int reads = 0;

  @override
  Future<CustomerFindingCounts> load({
    required String businessId,
    required String customerId,
    required List<dynamic> vehicles,
  }) async {
    reads++;
    expect(businessId, 'shop');
    expect(customerId, 'customer');
    expect(vehicles.length, 2);
    return reads == 1
        ? const CustomerFindingCounts(open: 2, inJob: 1, resolved: 3)
        : const CustomerFindingCounts(open: 1, inJob: 1, resolved: 4);
  }
}

void main() {
  test('aggregate totals count unique identities from all statuses', () {
    final counts = CustomerFindingCounts.fromRows([
      {'id': 'a', 'status': 'open', 'vehicle_id': 'vehicle-a'},
      {'id': 'b', 'status': 'in_job', 'vehicle_id': 'vehicle-b'},
      {'id': 'c', 'status': 'resolved', 'vehicle_id': 'vehicle-a'},
      // Same finding also appears in a past Job; never count it twice.
      {'id': 'b', 'status': 'in_job', 'vehicle_id': 'vehicle-b'},
      {'id': '', 'status': 'open'},
    ]);
    expect(counts.total, 3);
    expect(counts.open, 1);
    expect(counts.inJob, 1);
    expect(counts.resolved, 1);
  });

  testWidgets('overview opens existing findings and refreshes after return', (
    tester,
  ) async {
    final reader = _FakeOverview();
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomerFindingsOverviewRow(
          businessId: 'shop',
          customerId: 'customer',
          vehicles: const [
            {'id': 'vehicle-a'},
            {'id': 'vehicle-b'},
          ],
          service: reader,
          onOpen: () async { opened++; },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Vehicle Findings'), findsOneWidget);
    expect(find.text('Open 2 • In Job 1 • Resolved 3'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    await tester.tap(find.byKey(
      const ValueKey('customer-overview-vehicle-findings'),
    ));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(reader.reads, 2);
    expect(find.text('Open 1 • In Job 1 • Resolved 4'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  test('overview button navigates to existing vehicle-scoped detail screen', () {
    final source = File('lib/screens/customers/customer_detail_screen.dart')
        .readAsStringSync();
    expect(source, contains('CustomerFindingsOverviewRow('));
    final overview = source.indexOf("link('Jobs', Icons.build_outlined");
    final findings = source.indexOf('CustomerFindingsOverviewRow(', overview);
    final invoices = source.indexOf("link('Invoices',", overview);
    expect(findings, greaterThan(overview));
    expect(findings, lessThan(invoices));
    expect(source, contains('Future<void> _openAllVehicleFindings('));
    expect(source, contains('CustomerVehicleFindingsSection('));
    expect(source, contains('onOpen: () => _openAllVehicleFindings('));
  });

  test('draft finding photo strip shows images, enlargement and remove', () {
    final source = File(
      'lib/screens/customers/customer_vehicle_findings_section.dart',
    ).readAsStringSync();
    expect(source, contains('finding-selected-photo-strip'));
    expect(source, contains('Image.file('));
    expect(source, contains('finding-photo-preview-'));
    expect(source, contains('finding-photo-remove-'));
    expect(source, contains('_previewStagedFindingPhoto('));
    expect(source, contains('InteractiveViewer('));
    expect(source, contains('photos.removeAt(index)'));
    expect(source, contains('await photo.readAsBytes()'));
  });
}
