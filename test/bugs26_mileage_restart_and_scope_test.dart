import 'dart:io';

import 'package:briskers_app/core/invoice_pdf_mileage_projection.dart';
import 'package:briskers_app/core/job_mileage_summary.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_invoice_mileage_service.dart';
import 'package:briskers_app/services/offline_preinspection_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Miles In and each exact invoice Miles Out survive SQLite close/reopen and PDF projection', () async {
    final root = await Directory.systemTemp.createTemp('mileage-restart-');
    final file = File('${root.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    try {
      final inspection = OfflinePreInspectionService(database: db);
      await inspection.saveLocalInspection(
        'shop-a',
        'job-a',
        vehicleId: 'car-a',
        notes: 'Existing inspection notes',
        odometer: 50000,
      );
      var out = OfflineInvoiceMileageService(database: db);
      await out.queue(
        'shop-a',
        'invoice-a',
        expectedVersion: 2,
        mileageOut: 50015,
      );
      await out.queue(
        'shop-a',
        'invoice-b',
        expectedVersion: 4,
        mileageOut: 50030,
      );
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      final savedIn = await OfflinePreInspectionService(database: db)
          .loadLocalInspection('shop-a', 'job-a');
      expect(JobMileageSummary.mileageIn({}, savedIn), 50000);
      expect(savedIn?['notes'], 'Existing inspection notes');
      expect(
        await OfflinePreInspectionService(database: db)
            .loadLocalInspection('shop-b', 'job-a'),
        isNull,
      );
      out = OfflineInvoiceMileageService(database: db);
      const first = <String, dynamic>{
        'id': 'invoice-a',
        'kind': 'invoice',
        'business_id': 'shop-a',
        'job_id': 'job-a',
        'vehicle_id': 'car-a',
        'mileage_schema_version': 2,
        'mileage_in': 50000,
        'mileage_out': 50001,
        'total_amount': 73.51,
        'paid_amount': 0,
      };
      final projected = await out.project('shop-a', 'invoice-a', first);
      expect(projected['mileage_out'], 50015);
      expect(projected['mileage_in'], 50000);
      // An older cached invoice may have the explicit Miles Out field
      // without a numeric v2 marker. The header and saved queue must agree.
      final typedMarker = await out.project('shop-a', 'invoice-a', {
        ...first,
        'mileage_schema_version': '2',
      });
      expect(typedMarker['mileage_out'], 50015);
      final explicitDeparture = await out.project('shop-a', 'invoice-a', {
        ...first,
        'mileage_schema_version': null,
      });
      expect(explicitDeparture['mileage_out'], 50015);
      final missingMarker = await out.project('shop-a', 'invoice-a', {
        ...first,
      }..remove('mileage_schema_version'));
      expect(missingMarker['mileage_out'], 50015);
      final purelyLegacy = await out.project('shop-a', 'invoice-a', {
        'id': 'invoice-a',
        'kind': 'invoice',
        'business_id': 'shop-a',
        'job_id': 'job-a',
        'vehicle_id': 'car-a',
        'odometer_in': 50000,
      });
      expect(purelyLegacy.containsKey('mileage_out'), isFalse,
        reason: 'Never reinterpret a legacy Miles In value as departure');
      final second = await out.project('shop-a', 'invoice-b', {
        ...first,
        'id': 'invoice-b',
      });
      expect(second['mileage_out'], 50030);
      final pdf = InvoicePdfMileageProjection.reconcile(
        documentId: 'invoice-a',
        pdfDetail: projected,
        visibleDetail: projected,
      );
      expect(pdf['mileage_out'], 50015);
      final pdfTyped = InvoicePdfMileageProjection.reconcile(
        documentId: 'invoice-a',
        pdfDetail: {...first, 'mileage_schema_version': '2', 'mileage_out': null},
        visibleDetail: explicitDeparture,
      );
      expect(pdfTyped['mileage_out'], 50015);
      expect(pdf['total_amount'], 73.51);
      expect(pdf['paid_amount'], 0);
      expect(
        await out.project('shop-a', 'invoice-b', first),
        first,
        reason: 'Never put another invoice reading on a mismatched payload',
      );
      expect(
        await out.project('shop-b', 'invoice-a', first),
        first,
        reason: 'Explicit business identity cannot be borrowed',
      );
      expect(
        (await db
                .customSelect(
                  "SELECT COUNT(*) AS n FROM sync_outbox WHERE entity_type='invoice_mileage_out'",
                )
                .getSingle())
            .read<int>('n'),
        2,
      );
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
