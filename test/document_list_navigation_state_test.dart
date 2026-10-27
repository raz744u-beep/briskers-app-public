import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/documents_screen.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/invoice_payment_feed.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_job_retirement.dart';

class _Documents extends LocalDocumentRepository {
  _Documents(BriskersLocalDatabase database) : super(database: database);
  List<Map<String, dynamic>> rows = [];
  int reads = 0;
  bool failRead = false;
  int saves = 0;
  List<Map<String, dynamic>> savedRows = [];
  Completer<void>? secondSave;

  @override
  Future<List<Map<String, dynamic>>> listByKind(
    String businessId, {
    required String kind,
  }) async {
    reads++;
    if (failRead) throw StateError('Synthetic local read failure');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<void> replaceFromServer(
    String businessId,
    List<Map<String, dynamic>> documents, {
    String? kind,
  }) async {
    saves++;
    if (saves == 2 && secondSave != null) await secondSave!.future;
    savedRows = documents.map((row) => Map<String, dynamic>.from(row)).toList();
  }
}

class _Payments extends InvoicePaymentFeed {
  _Payments(BriskersLocalDatabase database) : super(database: database);
  List<Map<String, dynamic>> rows = [];
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> load(String businessId) async {
    reads++;
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }
}

class _HeldDocuments extends _Documents {
  _HeldDocuments(super.database);
  final Completer<void> gate = Completer<void>();
  bool requested = false;

  @override
  Future<List<Map<String, dynamic>>> listByKind(
    String businessId, {
    required String kind,
  }) async {
    requested = true;
    await gate.future;
    return super.listByKind(businessId, kind: kind);
  }
}

class _HeldPayments extends _Payments {
  _HeldPayments(super.database);
  final Completer<void> gate = Completer<void>();
  bool requested = false;

  @override
  Future<List<Map<String, dynamic>>> load(String businessId) async {
    requested = true;
    await gate.future;
    return super.load(businessId);
  }
}

class _DelayedApi extends BriskersApi {
  final response = Completer<List<Map<String, dynamic>>>();
  int reads = 0;
  List<Map<String, dynamic>>? followingRows;

  @override
  Future<List<Map<String, dynamic>>> documents(
    String businessId, {
    required String kind,
  }) {
    reads++;
    final next = followingRows;
    if (next != null && reads > 1) {
      return Future.value(
        next.map((row) => Map<String, dynamic>.from(row)).toList(),
      );
    }
    return response.future;
  }

  @override
  Future<List<Map<String, dynamic>>> invoiceStatusStyles(
    String businessId,
  ) async => [];
}

class _ImmediateApi extends BriskersApi {
  List<Map<String, dynamic>> rows = [];
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> documents(
    String businessId, {
    required String kind,
  }) async {
    reads++;
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> invoiceStatusStyles(
    String businessId,
  ) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase database;
  late _Documents documents;
  late _Payments payments;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    database = BriskersLocalDatabase(NativeDatabase.memory());
    documents = _Documents(database);
    payments = _Payments(database);
  });
  tearDown(() => database.close());

  testWidgets(
    'first Auto invoice visit paints protected local row before reading '
    'receipt inventory or waiting on server',
    (tester) async {
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.auto,
      );
      final heldDocuments = _HeldDocuments(database)
        ..rows = [
          {
            'id': 'synthetic-first-invoice',
            'kind': 'invoice',
            'document_number': 'I-2467',
            'customer_name': 'Synthetic Invoice Customer',
            'status': 'issued',
            'display_status': 'Open',
            'total_amount': 125,
            '_local_snapshot': true,
          },
        ];
      final heldPayments = _HeldPayments(database);
      final api = _DelayedApi();

      await tester.pumpWidget(MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          roleCode: 'owner',
          isOwner: true,
          showAppBar: false,
          dockDefaultsToOpen: true,
          localDocuments: heldDocuments,
          paymentFeed: heldPayments,
          api: api,
          blockedDocumentIds: (_) async => <String>{},
        ),
      ));
      await tester.pump();
      expect(heldDocuments.requested, isTrue,
        reason: 'First protected local list read has priority');
      expect(heldPayments.requested, isFalse,
        reason: 'Receipt inventory may not queue a SQLite read first');

      heldDocuments.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('I-2467'), findsOneWidget);
      expect(heldPayments.requested, isTrue);
      expect(api.reads, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'Saved invoices paint with receipts and RPC still pending');

      heldPayments.gate.complete();
      api.response.complete(const []);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final estimate in [true, false]) {
    testWidgets(
      '${estimate ? 'Estimate status' : 'Invoice future-date'} filter and search '
      'survive repeated dock entry',
      (tester) async {
        Widget screen(int token) => MaterialApp(
          home: DocumentsScreen(
            key: const ValueKey('retained-documents'),
            businessId: 'synthetic-navigation-shop',
            kind: estimate ? 'estimate' : 'invoice',
            isOwner: false,
            roleCode: 'technician',
            showAppBar: false,
            dockDefaultsToOpen: true,
            dockResetToken: token,
            localDocuments: documents,
            paymentFeed: payments,
          ),
        );

        await tester.pumpWidget(screen(0));
        await tester.pump();
        final state = tester.state(find.byType(DocumentsScreen));
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        final filter = estimate ? 'Issued' : 'Future-dated';
        await tester.tap(find.text(filter).last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Synthetic repair');
        await tester.pump();

        for (var token = 1; token <= 3; token++) {
          await tester.pumpWidget(screen(token));
          await tester.pump();
          expect(tester.state(find.byType(DocumentsScreen)), same(state));
          expect(
            tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
            'Synthetic repair',
          );
          expect(find.text(filter), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'offline dock entry refreshes payments and status changed elsewhere',
    (tester) async {
      documents.rows = [
        {
          'id': 'synthetic-invoice',
          'kind': 'invoice',
          'document_number': 'I-200',
          'status': 'draft',
          'display_status': 'Open',
          'total_amount': 100,
          'paid_amount': 0,
          'pending_payment': 0,
          '_local_snapshot': true,
        },
      ];
      Widget screen(int token) => MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          dockResetToken: token,
          localDocuments: documents,
          paymentFeed: payments,
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(documents.reads, 1);
      expect(payments.reads, 1);

      // A payment written by Jobs/Expenses while this list is retained.
      payments.rows = [
        {'invoice_id': 'synthetic-invoice', 'amount': 100},
      ];
      await tester.pumpWidget(screen(1));
      await tester.pumpAndSettle();
      expect(find.text('Pending Close'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(documents.reads, 2);
      expect(payments.reads, 2);

      // A closure from another route must replace the retained index status.
      documents.rows.single['status'] = 'closed';
      documents.rows.single['display_status_code'] = 'closed';
      await tester.pumpWidget(screen(2));
      await tester.pumpAndSettle();
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Pending Close'), findsNothing);
      expect(documents.reads, 3);
      expect(payments.reads, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'large estimate list builds lazily and retains scroll on refresh',
    (tester) async {
      documents.rows = List.generate(
        500,
        (i) => {
          'id': 'synthetic-estimate-$i',
          'kind': 'estimate',
          'document_number': 'E-$i',
          'status': 'draft',
          'display_status': 'Draft',
          'estimate_description': 'Synthetic work summary $i',
          'customer_name': 'Synthetic Customer $i',
          'total_amount': 100,
        },
      );
      Widget screen(int token) => MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'estimate',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          dockResetToken: token,
          localDocuments: documents,
          paymentFeed: payments,
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      expect(find.text('E-499'), findsOneWidget);
      expect(find.text('E-0'), findsNothing);
      expect(find.byType(Card).evaluate().length, lessThan(30));
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = position.pixels;
      expect(before, greaterThan(500));
      await tester.pumpWidget(screen(1));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(before, 0.01));
      expect(documents.reads, 2);
      expect(find.byType(Card).evaluate().length, lessThan(30));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('retirement hides retained invoice even when refresh fails', (
    tester,
  ) async {
    documents.rows = [
      {
        'id': 'synthetic-invoice',
        'job_id': 'retired-job',
        'kind': 'invoice',
        'document_number': 'I-200',
        'status': 'draft',
        'display_status': 'Open',
        'total_amount': 100,
        '_local_snapshot': true,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          localDocuments: documents,
          paymentFeed: payments,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('I-200'), findsOneWidget);
    // No Supabase client is initialized: Auto exercises a failed online
    // refresh, without contacting any backend.
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
    await tester.pumpAndSettle();
    documents.failRead = true;
    LocalJobRetirement.notify(database, 'synthetic-shop', ['retired-job']);
    await tester.pumpAndSettle();
    expect(find.text('I-200'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed Auto refresh picks up externally changed local status', (
    tester,
  ) async {
    documents.rows = [
      {
        'id': 'synthetic-invoice',
        'kind': 'invoice',
        'document_number': 'I-200',
        'status': 'draft',
        'display_status': 'Open',
        'total_amount': 100,
        '_local_snapshot': true,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          localDocuments: documents,
          paymentFeed: payments,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    documents.rows.single['status'] = 'closed';
    documents.rows.single['display_status_code'] = 'closed';
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
    await tester.pumpAndSettle();
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(documents.reads, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Force Offline paints local rows before a stalled online read ends',
    (tester) async {
      final api = _DelayedApi();
      documents.rows = [
        {
          'id': 'synthetic-invoice',
          'kind': 'invoice',
          'document_number': 'I-200',
          'status': 'draft',
          'display_status': 'Open',
          'total_amount': 100,
          '_local_snapshot': true,
        },
      ];
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.online,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentsScreen(
            businessId: 'synthetic-shop',
            kind: 'invoice',
            isOwner: false,
            roleCode: 'technician',
            showAppBar: false,
            localDocuments: documents,
            paymentFeed: payments,
            api: api,
          ),
        ),
      );
      await tester.pump();
      expect(api.reads, 1);
      expect(documents.reads, 0);
      expect(find.text('I-200'), findsNothing);
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.offline,
      );
      await tester.pumpAndSettle();
      expect(api.response.isCompleted, isFalse);
      expect(find.text('I-200'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      api.response.complete([
        {
          'id': 'synthetic-invoice',
          'kind': 'invoice',
          'document_number': 'I-200',
          'status': 'closed',
          'display_status_code': 'closed',
          'total_amount': 100,
          'paid_amount': 100,
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Closed'), findsNothing);
      expect(api.reads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dock re-entry supersedes a read started before an external payment',
    (tester) async {
      final api = _DelayedApi()
        ..followingRows = [
          {
            'id': 'synthetic-invoice',
            'kind': 'invoice',
            'document_number': 'I-200',
            'status': 'draft',
            'display_status_code': 'pending_close',
            'total_amount': 100,
            'paid_amount': 0,
            'pending_payment': 100,
          },
        ];
      documents.rows = [
        {
          'id': 'synthetic-invoice',
          'kind': 'invoice',
          'document_number': 'I-200',
          'status': 'draft',
          'display_status': 'Open',
          'total_amount': 100,
          '_local_snapshot': true,
        },
      ];
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.auto,
      );
      Widget screen(int token) => MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          dockResetToken: token,
          localDocuments: documents,
          paymentFeed: payments,
          api: api,
          blockedDocumentIds: (_) async => {},
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      expect(api.reads, 1);
      expect(payments.reads, 1);
      expect(find.text('Open'), findsOneWidget);

      payments.rows = [
        {'invoice_id': 'synthetic-invoice', 'amount': 100},
      ];
      await tester.pumpWidget(screen(1));
      await tester.pump();
      // The old response completes after re-entry, but cannot become the final
      // payment/status state. The queued pass reads both sources again.
      api.response.complete([
        {
          'id': 'synthetic-invoice',
          'kind': 'invoice',
          'document_number': 'I-200',
          'status': 'draft',
          'display_status_code': 'open',
          'total_amount': 100,
          'paid_amount': 0,
          'pending_payment': 0,
        },
      ]);
      await tester.pumpAndSettle();
      expect(api.reads, 2);
      expect(payments.reads, 2);
      expect(documents.saves, 1);
      expect(find.text('Pending Close'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'successful remote refresh skips unchanged saves but paints money '
    'and status changes',
    (tester) async {
      final api = _ImmediateApi();
      final live = <String, dynamic>{
        'id': 'synthetic-live',
        'kind': 'invoice',
        'document_number': 'I-200',
        'status': 'draft',
        'display_status_code': 'open',
        'total_amount': 100,
        'paid_amount': 0,
        'pending_payment': 0,
      };
      api.rows = [
        live,
        {
          ...live,
          'id': 'synthetic-retired',
          'job_id': 'stale-reassigned-job',
          'document_number': 'I-999',
        },
      ];
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.online,
      );
      Widget screen(int token) => MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          dockResetToken: token,
          localDocuments: documents,
          paymentFeed: payments,
          api: api,
          blockedDocumentIds: (_) async => {'synthetic-retired'},
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      expect(find.text('I-200'), findsOneWidget);
      expect(find.text('I-999'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(api.reads, 1);
      expect(documents.reads, 0);
      expect(documents.saves, 1);
      expect(documents.savedRows.single['id'], 'synthetic-live');

      await tester.pumpWidget(screen(1));
      await tester.pumpAndSettle();
      expect(api.reads, 2);
      expect(
        documents.saves,
        1,
        reason: 'Identical response must not rewrite index',
      );
      expect(
        documents.reads,
        0,
        reason: 'Warm online read must not flash index',
      );

      live['pending_payment'] = 100;
      await tester.pumpWidget(screen(2));
      await tester.pumpAndSettle();
      expect(find.text('Pending Close'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(documents.saves, 2);
      expect(documents.savedRows.single['pending_payment'], 100);

      live['status'] = 'closed';
      live['display_status_code'] = 'closed';
      await tester.pumpWidget(screen(3));
      await tester.pumpAndSettle();
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Pending Close'), findsNothing);
      expect(documents.saves, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'superseded cache write cannot make a restored snapshot look saved',
    (tester) async {
      final api = _ImmediateApi()
        ..rows = [
          {
            'id': 'synthetic-live',
            'kind': 'invoice',
            'document_number': 'I-200',
            'status': 'draft',
            'total_amount': 100,
            'paid_amount': 0,
            'pending_payment': 0,
          },
        ];
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.online,
      );
      Widget screen(int token) => MaterialApp(
        home: DocumentsScreen(
          businessId: 'synthetic-shop',
          kind: 'invoice',
          isOwner: false,
          roleCode: 'technician',
          showAppBar: false,
          dockResetToken: token,
          localDocuments: documents,
          paymentFeed: payments,
          api: api,
          blockedDocumentIds: (_) async => {},
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      expect(documents.saves, 1);
      documents.secondSave = Completer<void>();
      api.rows.single['pending_payment'] = 100;
      await tester.pumpWidget(screen(1));
      await tester.pumpAndSettle();
      expect(documents.saves, 2);
      expect(documents.secondSave!.isCompleted, isFalse);

      api.rows.single['pending_payment'] = 0;
      await tester.pumpWidget(screen(2));
      await tester.pump();
      documents.secondSave!.complete();
      await tester.pumpAndSettle();
      expect(
        documents.saves,
        3,
        reason: 'The completed stale write must be replaced with current data',
      );
      expect(documents.savedRows.single['pending_payment'], 0);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Pending Close'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
