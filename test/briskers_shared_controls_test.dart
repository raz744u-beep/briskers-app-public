import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/widgets/briskers_curved_tabs.dart';
import 'package:briskers_app/widgets/owner_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 820.0]) {
    testWidgets('shared tabs and dialog fit a $width pixel layout', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  BriskersControlledTabs(
                    entries: const [
                      (
                        label: 'Today',
                        icon: Icons.today,
                        color: BriskersColors.appointments,
                      ),
                      (
                        label: 'Upcoming',
                        icon: Icons.calendar_month,
                        color: BriskersColors.customers,
                      ),
                    ],
                    selected: selected,
                    onSelected: (index) => update(() => selected = index),
                  ),
                  TextButton(
                    onPressed: () async {
                      confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => const OwnerConfirmationDialog(
                          title: 'Mark All Done?',
                          confirm: 'Mark All Done',
                          sections: [
                            Text(
                              'Complete the saved service tasks for this job.',
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Show'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      final stripe = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('profile-tabs-stripe')),
      );
      expect(stripe.color, BriskersColors.customers);

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).gradient ==
                  BriskersColors.blueHeader,
        ),
        findsOneWidget,
      );
      final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Mark All Done'),
      );
      expect(
        action.style!.backgroundColor!.resolve({}),
        BriskersColors.confirm,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmed, false);

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark All Done'));
      await tester.pumpAndSettle();
      expect(confirmed, true);
      expect(tester.takeException(), isNull);
    });
  }
}
