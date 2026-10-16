import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/briskers_module_dock.dart';

void main() {
  testWidgets('bottom dock keeps module colors even when unselected', (tester) async {
    const jobs = Color(0xFF008577);
    const invoices = Color(0xFF268634);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      bottomNavigationBar: BriskersModuleDock(
        selectedIndex: 0,
        onSelected: (_) {},
        destinations: const [
          BriskersDockDestination(label: 'Jobs', icon: Icons.build, color: jobs),
          BriskersDockDestination(label: 'Invoices', icon: Icons.receipt_long, color: invoices),
        ],
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byIcon(Icons.build)).color, jobs);
    expect(tester.widget<Icon>(find.byIcon(Icons.receipt_long)).color, invoices);
  });
}
