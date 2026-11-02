import 'dart:io';

import 'package:briskers_app/widgets/document_tab_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required double width,
    required List<Widget> tabs,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: TabBar(
              isScrollable: false,
              labelPadding: EdgeInsets.zero,
              tabs: tabs,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Invoice tabs reach both edges on a 320dp phone', (tester) async {
    await show(tester, width: 320, tabs: const [
      DocumentTabLabel(label: 'Items', alignment: Alignment.centerLeft),
      DocumentTabLabel(label: 'Payment'),
      DocumentTabLabel(label: 'Notes'),
      DocumentTabLabel(label: 'Expenses', alignment: Alignment.centerRight),
    ]);
    expect(tester.takeException(), isNull);
    final items = tester.getRect(find.text('Items'));
    final payment = tester.getRect(find.text('Payment'));
    final notes = tester.getRect(find.text('Notes'));
    final expenses = tester.getRect(find.text('Expenses'));
    expect(items.left, greaterThanOrEqualTo(0));
    expect(items.left, lessThan(25));
    expect(expenses.right, lessThanOrEqualTo(320));
    expect(expenses.right, greaterThan(295));
    expect(items.right, lessThan(payment.left));
    expect(payment.right, lessThan(notes.left));
    expect(notes.right, lessThan(expenses.left));
    expect(payment.center.dx, closeTo(120, 12));
    expect(notes.center.dx, closeTo(200, 12));
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Estimate two tabs are centered in equal-width targets',
      (tester) async {
    await show(tester, width: 320, tabs: const [
      DocumentTabLabel(label: 'Items', alignment: Alignment.center),
      DocumentTabLabel(label: 'Notes', alignment: Alignment.center),
    ]);
    final left = tester.getRect(find.text('Items'));
    final right = tester.getRect(find.text('Notes'));
    expect(left.center.dx, closeTo(80, 12));
    expect(right.center.dx, closeTo(240, 12));
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('Invoice tab header keeps four equal-width labels in correct order', () {
    final src = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final start = src.indexOf('class _DocumentTabsHeaderDelegate');
    final header = src.substring(start);
    expect(header, contains('isScrollable: false'));
    expect(header, contains('labelPadding: EdgeInsets.zero'));
    expect(header, contains('alignment: isEstimate ? Alignment.center : Alignment.centerLeft'));
    expect(header, contains("label: tr('paymentTab')"));
    expect(header, contains("label: tr('notesTab')"));
    expect(header, contains("label: 'Expenses', alignment: Alignment.centerRight"));
    expect(header, isNot(contains('Tab(text:')));
  });
}
