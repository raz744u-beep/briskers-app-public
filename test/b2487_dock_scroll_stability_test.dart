import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/briskers_module_dock.dart';

const destinations = <BriskersDockDestination>[
  BriskersDockDestination(label: 'Home', icon: Icons.home_outlined, color: Colors.teal),
  BriskersDockDestination(label: 'Customers', icon: Icons.people_outline, color: Colors.blue),
  BriskersDockDestination(label: 'Jobs', icon: Icons.build_outlined, color: Colors.teal),
  BriskersDockDestination(label: 'Estimates', icon: Icons.description_outlined, color: Colors.purple),
  BriskersDockDestination(label: 'Invoices', icon: Icons.receipt_long_outlined, color: Colors.green),
  BriskersDockDestination(label: 'Schedule', icon: Icons.calendar_month_outlined, color: Colors.blue),
  BriskersDockDestination(label: 'Expenses', icon: Icons.account_balance_wallet_outlined, color: Colors.red),
  BriskersDockDestination(label: 'More', icon: Icons.more_horiz, color: Colors.grey),
];

void main() {
  testWidgets('horizontal dock viewport never changes width when arrows appear',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 880));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BriskersModuleDock(
          selectedIndex: 0,
          onSelected: _noSelection,
          destinations: destinations,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final list = find.byType(ListView);
    final initialWidth = tester.getSize(list).width;
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(scroll.maxScrollExtent, greaterThan(200));
    expect(find.byTooltip('Previous sections'), findsNothing);
    expect(find.byTooltip('More sections'), findsOneWidget);

    scroll.jumpTo(130);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Previous sections'), findsOneWidget);
    expect(find.byTooltip('More sections'), findsOneWidget);
    expect(tester.getSize(list).width, closeTo(initialWidth, 0.01));

    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Previous sections'), findsOneWidget);
    expect(find.byTooltip('More sections'), findsNothing);
    expect(tester.getSize(list).width, closeTo(initialWidth, 0.01));
  });

  testWidgets('already-visible selections do not trigger unnecessary scroll animation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 880));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 0;
    late StateSetter changeSelection;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (_, setState) {
        changeSelection = setState;
        return Scaffold(bottomNavigationBar: BriskersModuleDock(
          selectedIndex: selected,
          destinations: destinations,
          onSelected: (index) => setState(() => selected = index),
        ));
      }),
    ));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, closeTo(0, 0.01));

    changeSelection(() => selected = 1);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(0, 0.01));

    changeSelection(() => selected = 7);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(find.byKey(const ValueKey('dock-More')), findsOneWidget);
  });
}

void _noSelection(int _) {}
