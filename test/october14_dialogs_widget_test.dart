import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/screens/jobs/invoice_warranty_panel.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';
import 'package:briskers_app/screens/settings/expense_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accounts = <Map<String, dynamic>>[
  {'id': 'cash', 'name': 'Cash', 'active': true},
];
const _categories = <Map<String, dynamic>>[
  {'id': 'parts', 'name': 'Parts', 'active': true},
];
const _payees = <Map<String, dynamic>>[
  {'id': 'worldpac', 'name': 'Worldpac', 'active': true},
  {'id': 'fedex', 'name': 'FedEx', 'active': true},
  {'id': 'old', 'name': 'Worldpac retired', 'active': false},
];

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Widget _quickDialog({
  Map<String, dynamic>? template,
  List<Map<String, dynamic>> categories = _categories,
}) => QuickTransactionsSettingsScreen.dialogForTesting(
  businessId: 'synthetic-dialog-shop',
  accounts: _accounts,
  categories: categories,
  counterparties: _payees,
  template: template,
);

Future<void> _open<T>(
  WidgetTester tester,
  WidgetBuilder builder, {
  ValueChanged<T?>? onClosed,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              final result = await showDialog<T>(
                context: context,
                builder: builder,
              );
              onClosed?.call(result);
            },
            child: const Text('Open dialog'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open dialog'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _smallScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
  });

  testWidgets('quick payee search filters active names and supports clear/back', (
    tester,
  ) async {
    await _open<bool>(tester, (_) => _quickDialog());
    await tester.tap(find.text('Search vendor / payee'));
    await tester.pumpAndSettle();
    expect(find.text('Worldpac retired'), findsNothing);
    expect(find.text('FedEx'), findsOneWidget);

    await tester.enterText(_field('Vendor / payee name'), '  WORLD  ');
    await tester.pumpAndSettle();
    expect(find.text('Worldpac'), findsOneWidget);
    expect(find.text('FedEx'), findsNothing);
    expect(find.text('Worldpac retired'), findsNothing);
    await tester.tap(find.text('Worldpac'));
    await tester.pumpAndSettle();
    expect(find.text('Search payees and payers'), findsNothing);
    expect(find.text('Worldpac'), findsOneWidget);

    // Back dismisses only the search sheet and preserves the current payee.
    await tester.tap(find.text('Worldpac'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Vendor / payee name'), 'no-match');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Worldpac'), findsNothing);
    expect(find.widgetWithText(ListTile, 'None'), findsOneWidget);
    Navigator.of(tester.element(_field('Vendor / payee name'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Worldpac'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Worldpac'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(find.text('Search vendor / payee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final missing in ['name', 'account', 'category']) {
    testWidgets('quick transaction does not save without $missing', (
      tester,
    ) async {
      var closed = false;
      await _open<bool>(
        tester,
        (_) => _quickDialog(
          template: {
            'id': 'synthetic-template',
            'name': missing == 'name' ? '   ' : 'Parts purchase',
            if (missing != 'account') 'account_id': 'cash',
          },
          categories: missing == 'category' ? const [] : _categories,
        ),
        onClosed: (_) => closed = true,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Name, account and category are required.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(closed, isFalse);
      expect(tester.takeException(), isNull);
      // No Supabase client is initialized: an accidental save would also fail.
    });
  }

  testWidgets('quick payee picker stays usable above a small-screen keyboard', (
    tester,
  ) async {
    _smallScreen(tester);
    await _open<bool>(tester, (_) => _quickDialog(), textScale: 1.2);
    await tester.tap(find.text('Search vendor / payee'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.enterText(_field('Vendor / payee name'), 'fed');
    await tester.pumpAndSettle();
    final payee = find.widgetWithText(ListTile, 'FedEx');
    await tester.ensureVisible(payee);
    expect(tester.getBottomRight(payee).dy, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(payee);
    // A real keyboard can change insets before the sheet's reverse animation
    // finishes. Its search controller must remain alive through these frames.
    await tester.pump(const Duration(milliseconds: 50));
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Search payees and payers'), findsNothing);
    expect(find.text('FedEx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick dropdowns fit long names with enlarged text', (tester) async {
    _smallScreen(tester);
    await _open<bool>(
      tester,
      (_) => QuickTransactionsSettingsScreen.dialogForTesting(
        businessId: 'synthetic-dialog-shop',
        accounts: const [
          {'id': 'long-account', 'name': 'Main business operating account'},
        ],
        categories: const [
          {'id': 'long-category', 'name': 'Replacement parts and outside services'},
        ],
        counterparties: _payees,
        template: const {
          'name': 'Parts purchase',
          'account_id': 'long-account',
          'category_id': 'long-category',
        },
      ),
      textScale: 1.3,
    );
    final dropdowns = tester.widgetList<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdowns, hasLength(2));
    expect(dropdowns.every((dropdown) => dropdown.isExpanded), isTrue);
    expect(find.text('Main business operating account'), findsOneWidget);
    expect(find.text('Replacement parts and outside services'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick dialog keeps actions visible with a keyboard and cancels', (
    tester,
  ) async {
    _smallScreen(tester);
    bool? result;
    await _open<bool>(
      tester,
      (_) => _quickDialog(),
      onClosed: (value) => result = value,
    );
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.surface);
    expect((dialog.content! as SizedBox).width, closeTo(360 * 0.92, 0.01));
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).style!.backgroundColor!.resolve({}),
        Colors.red.shade700);
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).style!.backgroundColor!.resolve({}),
        Colors.green.shade700);
    await tester.enterText(_field('Shortcut name'), 'Keyboard draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(360));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('Shortcut name')).controller!.text, isEmpty);
  });

  testWidgets('historical reopen trims reason and requires ten characters', (
    tester,
  ) async {
    final reason = TextEditingController();
    addTearDown(reason.dispose);
    String? result;
    await _open<String>(
      tester,
      (context) => JobDocumentScreen.historicalReopenDialogForTesting(context, reason),
      onClosed: (value) => result = value,
    );
    final confirm = find.widgetWithText(FilledButton, 'Reopen and edit');
    for (final text in ['', '     ', ' 123456789 ']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(result, isNull);
    }
    await tester.enterText(find.byType(TextField), ' 1234567890 ');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, '1234567890');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('historical reopen scrolls with keyboard and cancellation is null', (
    tester,
  ) async {
    _smallScreen(tester);
    final reason = TextEditingController(text: 'A valid reason to reopen');
    addTearDown(reason.dispose);
    var closed = false;
    String? result;
    await _open<String>(
      tester,
      (context) => JobDocumentScreen.historicalReopenDialogForTesting(context, reason),
      textScale: 1.3,
      onClosed: (value) {
        closed = true;
        result = value;
      },
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    expect(dialog.backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.surface);
    expect(tester.widget<TextField>(find.byType(TextField)).minLines, 4);
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    expect(tester.getBottomRight(cancel).dy, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('payment confirmation is readable, scrollable, and explicit', (
    tester,
  ) async {
    _smallScreen(tester);
    bool? result;
    await _open<bool>(
      tester,
      (context) => JobDocumentScreen.finalizePaymentDialogForTesting(context, '\$123.45'),
      textScale: 1.3,
      onClosed: (value) => result = value,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    expect(dialog.backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.surface);
    expect(find.textContaining('\$123.45 was actually received'), findsOneWidget);
    expect(find.textContaining('Do not finalize an authorization or unpaid promise.'),
        findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Finalize Payment');
    expect(tester.widget<FilledButton>(confirm).style!.backgroundColor!.resolve({}),
        Colors.green.shade700);
    expect(tester.getBottomRight(confirm).dy, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('invoice Add Company keeps the form open until name is valid', (
    tester,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    addTearDown(email.dispose);
    bool? result;
    await _open<bool>(
      tester,
      (context) => InvoiceWarrantyPanel.createCompanyDialogForTesting(
        context, name: name, phone: phone, email: email,
      ),
      onClosed: (value) => result = value,
    );
    final add = find.widgetWithText(FilledButton, 'Add');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    await tester.enterText(_field('Company name'), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(_field('Company name'), 'Synthetic warranty');
    await tester.enterText(_field('Claims phone'), '8005311925');
    await tester.enterText(_field('Invoice submission email'), 'claims@example.com');
    await tester.pump();
    expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
    expect(phone.text, '800-531-1925');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(name.text, 'Synthetic warranty');
    expect(email.text, 'claims@example.com');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('invoice Add Company is spacious and keyboard-safe on small screens', (
    tester,
  ) async {
    _smallScreen(tester);
    final name = TextEditingController(text: 'Prefilled warranty');
    final phone = TextEditingController();
    final email = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(phone.dispose);
    addTearDown(email.dispose);
    bool? result;
    await _open<bool>(
      tester,
      (context) => InvoiceWarrantyPanel.createCompanyDialogForTesting(
        context, name: name, phone: phone, email: email,
      ),
      textScale: 1.3,
      onClosed: (value) => result = value,
    );
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    expect(dialog.backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.surface);
    expect(dialog.surfaceTintColor, Colors.transparent);
    expect((dialog.content! as SizedBox).width, closeTo(360 * 0.92, 0.01));
    final add = find.widgetWithText(FilledButton, 'Add');
    expect(tester.widget<FilledButton>(add).style!.backgroundColor!.resolve({}),
        BriskersColors.invoices);
    expect(tester.widget<TextField>(_field('Company name')).autofocus, isFalse);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.decoration!.border, isA<OutlineInputBorder>());
      expect(field.decoration!.contentPadding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18));
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_field('Invoice submission email'));
    await tester.enterText(_field('Invoice submission email'), 'claims@example.com');
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(add).dy, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
