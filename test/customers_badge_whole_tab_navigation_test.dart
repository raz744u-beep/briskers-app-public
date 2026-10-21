import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/briskers_module_dock.dart';

void main() {
  testWidgets(
    'Customers icon remains a full-size tap even with one unread badge',
    (tester) async {
      var selected = -1;
      var tinyBadgeTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BriskersModuleDock(
            selectedIndex: 0,
            destinations: const [
              BriskersDockDestination(
                label: 'Home',
                icon: Icons.home_outlined,
                color: Colors.blue,
              ),
              BriskersDockDestination(
                label: 'Customers',
                icon: Icons.people_outline,
                color: Colors.blue,
                count: 1,
              ),
            ],
            onSelected: (index) => selected = index,
            onBadgeSelected: (_) => tinyBadgeTapped = true,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.people_outline));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tinyBadgeTapped, isFalse);
    },
  );

  test('shell sends Customers dock tap with unread count to focused review', () {
    final source = File('lib/screens/shell_screen.dart').readAsStringSync();
    final begin = source.indexOf('void _selectCustomersFromDock() {');
    final end = source.indexOf('void _goTo(int index)', begin);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    final router = source.substring(begin, end);
    expect(router, contains('_homeCustomersNewCount > 0'));
    expect(router, contains('_customerNotifications != null'));
    expect(router, contains('unawaited(_openCustomers(request));'));
    expect(router, contains('_goTo(1);'));
    expect(router, isNot(contains('markReviewed(')));

    final navStart = source.indexOf('Widget _shellNavigationBar(');
    final navEnd = source.indexOf('Widget build(BuildContext context)', navStart);
    final nav = source.substring(navStart, navEnd);
    expect(nav, contains('if (index == 1) {'));
    expect(nav, contains('_selectCustomersFromDock();'));
    expect(nav, contains('onBadgeSelected: (index)'));
    expect(nav, contains('unawaited(_openCustomers(request));'));

    // The unread list retains its View all action for opening the normal
    // directory. Reviewing an individual record is the only read action.
    final review = File('lib/screens/customers/new_customers_screen.dart')
        .readAsStringSync();
    expect(review, contains('onViewAll:'));
    expect(review, contains('widget.notifications.markReviewed(reviewed)'));
  });
}
