import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/module_modal_theme.dart';
import 'package:briskers_app/widgets/estimate_merge_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final language in ['en', 'es']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'estimate confirmation $language/$platform stays purple at 320px',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          await BriskersLanguageController.instance.setLanguage(language);
          addTearDown(
            () => BriskersLanguageController.instance.setLanguage('en'),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          bool? result;
          await tester.pumpWidget(
            MaterialApp(
              theme: moduleModalTheme(
                ThemeData(platform: platform),
                BriskersColors.estimates,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showDialog<bool>(
                        context: context,
                        builder: (_) => const EstimateMergeConfirmationDialog(
                          estimateTotal: r'$123.45',
                          invoiceTotal: r'$1,234.56',
                          combinedTotal: r'$1,358.01',
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final filled = find.byType(FilledButton);
          final style = Theme.of(tester.element(filled))
              .filledButtonTheme
              .style!;
          expect(style.backgroundColor!.resolve({}), BriskersColors.estimates);
          expect(tester.takeException(), isNull);
          expect(find.text(r'$1,358.01'), findsOneWidget);
          await tester.tap(find.text(language == 'es' ? 'Cancelar' : 'Cancel'));
          await tester.pumpAndSettle();
          expect(result, false);
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(
              language == 'es' ? 'Agregar a factura' : 'Add to Invoice',
            ),
          );
          await tester.pumpAndSettle();
          expect(result, true);
        },
      );
    }
  }
}
