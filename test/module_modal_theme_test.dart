import 'dart:io';

import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/core/module_modal_theme.dart';
import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  const _Harness(this.accent, {this.sheet = false});
  final Color accent;
  final bool sheet;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with ModuleModalState<_Harness> {
  @override
  Color get modalAccent => widget.accent;
  Widget _content(BuildContext context) => AlertDialog(
    title: const Text('Agregar presupuesto a factura'),
    content: const Text('La factura conserva sus controles de autorización.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Agregar a factura'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => widget.sheet
          ? showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: _content,
            )
          : showDialog<void>(context: context, builder: _content),
      child: const Text('Open'),
    ),
  );
}

void main() {
  for (final accent in [
    BriskersColors.estimates,
    BriskersColors.invoices,
    BriskersColors.expenses,
    BriskersColors.jobs,
  ]) {
    for (final sheet in [false, true]) {
      testWidgets(
        'semantic modal $accent sheet=$sheet remains neutral at narrow width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                colorSchemeSeed: Colors.blue,
                platform: TargetPlatform.iOS,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: _Harness(accent, sheet: sheet),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final context = tester.element(find.text('Agregar a factura'));
          final theme = Theme.of(context);
          expect(
            theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
            accent,
          );
          expect(theme.dialogTheme.backgroundColor, Colors.white);
          expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
          expect(
            theme.textButtonTheme.style!.foregroundColor!.resolve({}),
            isNot(Colors.blue),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect(find.text('Agregar a factura'), findsNothing);
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('Agregar a factura'), findsNothing);
        },
      );
    }
  }
  test('invoice identity uses its own responsive app bar', () {
    final source = File(
      'lib/screens/jobs/job_document_screen.dart',
    ).readAsStringSync();
    final header = source.substring(
      source.indexOf('    final tabCount ='),
      source.indexOf('        body: NestedScrollView('),
    );
    expect(header, contains('appBar: DocumentIdentityAppBar('));
    expect(header, isNot(contains('FittedBox')));
    expect(header, contains('Icons.edit_outlined'));
    expect(header, contains('Icons.add_card_outlined'));
  });
}
