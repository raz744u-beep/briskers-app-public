import 'dart:convert';
import 'dart:typed_data';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/screens/expenses/expense_detail_screen.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/warranty_receipt_reporting.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetwork extends BriskersApi {
  int calls = 0;
  @override
  Future<String> signedAttachmentUrl(String bucket, String key) async {
    calls++;
    throw StateError('No network allowed');
  }
}

class _Cache extends LocalFinancialCache {
  _Cache(BriskersLocalDatabase db, this.detail) : super(database: db);
  final Map<String, dynamic> detail;
  @override
  Future<Map<String, dynamic>?> loadTransactionDetail(
    String businessId,
    String transactionId,
  ) async => detail;
}

class _Original extends ExpenseIqLocalPhotoSync {
  _Original(BriskersLocalDatabase db) : super(database: db);
  @override
  Future<Map<String, dynamic>?> localForExpense(
    String businessId,
    String transactionId,
  ) async {
    expect(businessId, 'shop-a');
    expect(transactionId, 'expense-a');
    return {
      'filename': 'original.jpg',
      'source_uri': 'content://synthetic/original',
      'state': 'uploaded',
    };
  }
}

class _Reporting extends WarrantyReceiptReporting {
  @override
  Future<List<Map<String, dynamic>>> enrich(
    String businessId,
    List<Map<String, dynamic>> rows, {
    bool refresh = true,
  }) async => rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
  });
  tearDown(() async {
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });
  testWidgets(
    'uploaded receipt keeps exact expense original thumbnail and zoom offline',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = _NoNetwork();
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      );
      var reads = 0;
      final detail = <String, dynamic>{
        'id': 'expense-a',
        'direction': 'expense',
        'amount': 73.51,
        'attachments': [
          {
            'attachment_id': 'attachment-a',
            'filename': 'original.jpg',
            'key': 'shop-a/expense-a/original.jpg',
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseDetailScreen(
            businessId: 'shop-a',
            transactionId: 'expense-a',
            cachedDetail: detail,
            api: api,
            financialCache: _Cache(db, detail),
            localPhotoSync: _Original(db),
            receiptReporting: _Reporting(),
            localPhotoReader: (uri) async {
              expect(uri, 'content://synthetic/original');
              reads++;
              return Uint8List.fromList(photo);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = find.byKey(
        const ValueKey(
          'original-receipt-shop-a-expense-a-content://synthetic/original',
        ),
      );
      await tester.ensureVisible(original);
      expect(original, findsOneWidget);
      expect(
        find.byType(Image),
        findsOneWidget,
        reason: 'One receipt row, not a duplicate source card',
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
      await tester.tap(find.byTooltip('View receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        reads,
        1,
        reason: 'Thumbnail and zoom reuse the same original bytes',
      );
      expect(api.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
