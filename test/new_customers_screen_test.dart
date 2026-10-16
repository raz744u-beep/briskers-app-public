import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/customers/new_customers_screen.dart';
import 'package:briskers_app/services/customer_notification_service.dart';
import 'package:briskers_app/services/local_customer_repository.dart';

class _Inbox extends CustomerNotificationService {
  _Inbox(BriskersLocalDatabase db)
    : super(businessId: 'shop', userId: 'owner', database: db);
  final unread = <String>{'arrival-a', 'arrival-b'};
  bool failSave = false;

  @override
  Future<List<String>> unreadCustomerIds() async => unread.toList();
  @override
  Future<void> markReviewed(Iterable<String> ids) async {
    if (failSave) throw StateError('Storage not available');
    unread.removeAll(ids);
  }
}

class _Customers extends LocalCustomerRepository {
  _Customers(BriskersLocalDatabase db) : super(database: db);
  bool failLoad = false;
  final rows = <Map<String, dynamic>>[
    {'id': 'old', 'display_name': 'Existing customer'},
    {'id': 'arrival-a', 'display_name': 'Alice New', 'phone': '5045550123'},
    {'id': 'arrival-b', 'display_name': 'Bob New'},
  ];
  @override
  Future<List<Map<String, dynamic>>> customersByIds(
    String businessId,
    Iterable<String> customerIds,
  ) async {
    if (failLoad) throw StateError('Unavailable');
    return rows.where((row) => customerIds.contains(row['id'])).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late _Inbox inbox;
  late _Customers customers;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
    db = BriskersLocalDatabase(NativeDatabase.memory());
    inbox = _Inbox(db);
    customers = _Customers(db);
  });
  tearDown(() => db.close());

  Future<void> show(
    WidgetTester tester, {
    String role = 'owner',
    bool profileWorks = true,
  }) async {
    var focused = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: focused
                ? NewCustomersScreen(
                    businessId: 'shop',
                    roleCode: role,
                    customerIds: const ['arrival-a', 'arrival-b'],
                    notifications: inbox,
                    repository: customers,
                    onViewAll: () => setState(() => focused = false),
                    profileBuilder: (id, reviewed) => Scaffold(
                      appBar: AppBar(title: Text('$role profile $id')),
                      body: profileWorks
                          ? TextButton(
                              onPressed: reviewed,
                              child: const Text('Profile reviewed'),
                            )
                          : const Text('Profile unavailable'),
                    ),
                  )
                : Column(
                    children: customers.rows
                        .map((row) => Text(row['display_name'].toString()))
                        .toList(),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'focus contains only requested arrivals; view all restores ordinary list without consuming',
    (tester) async {
      await show(tester);
      expect(find.text('New customers'), findsOneWidget);
      expect(find.text('Alice New'), findsOneWidget);
      expect(find.text('Bob New'), findsOneWidget);
      expect(find.text('Existing customer'), findsNothing);
      expect(find.byType(SearchBar), findsNothing);
      expect(inbox.unread.length, 2);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(find.text('Existing customer'), findsOneWidget);
      expect(inbox.unread.length, 2);
    },
  );

  testWidgets(
    'profile review consumes only that arrival and preserves later arrivals',
    (tester) async {
      await show(tester, role: 'office');
      inbox.unread.add('arrived-later');
      await tester.tap(find.text('Alice New'));
      await tester.pumpAndSettle();
      expect(find.text('office profile arrival-a'), findsOneWidget);
      expect(inbox.unread.length, 3);
      await tester.tap(find.text('Profile reviewed'));
      await tester.pumpAndSettle();
      expect(inbox.unread, {'arrival-b', 'arrived-later'});
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Bob New'), findsOneWidget);
      await tester.tap(find.text('Mark shown customers reviewed'));
      await tester.pumpAndSettle();
      expect(inbox.unread, {'arrived-later'});
    },
  );

  testWidgets('failed profile or Back without review preserves badge', (
    tester,
  ) async {
    await show(tester, profileWorks: false);
    await tester.tap(find.text('Alice New'));
    await tester.pumpAndSettle();
    expect(find.text('Profile unavailable'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(inbox.unread.length, 2);
  });

  testWidgets(
    'storage failure does not show reviewed check or discard events',
    (tester) async {
      inbox.failSave = true;
      await show(tester);
      await tester.tap(find.text('Mark shown customers reviewed'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save review. These customers remain unread.'),
        findsOneWidget,
      );
      expect(inbox.unread.length, 2);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    },
  );

  testWidgets('Spanish focused list and explicit review use localized copy', (
    tester,
  ) async {
    await BriskersLanguageController.instance.setLanguage('es');
    await show(tester, role: 'office');
    expect(find.text('Clientes nuevos'), findsOneWidget);
    await tester.tap(find.text('Marcar clientes mostrados como revisados'));
    await tester.pumpAndSettle();
    expect(inbox.unread, isEmpty);
    await tester.tap(find.text('Ver todos'));
    await tester.pumpAndSettle();
    expect(find.text('Existing customer'), findsOneWidget);
  });

  testWidgets('load failure can retry and never consumes the notification', (
    tester,
  ) async {
    customers.failLoad = true;
    await show(tester);
    expect(
      find.text('Could not load saved new customers. Try again.'),
      findsOneWidget,
    );
    expect(inbox.unread.length, 2);
    customers.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Alice New'), findsOneWidget);
    expect(inbox.unread.length, 2);
  });
}
