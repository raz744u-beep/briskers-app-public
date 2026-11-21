import 'package:briskers_app/widgets/document_identity_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('invoice6345 stays readable at 320px scale$scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      int edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            appBar: DocumentIdentityAppBar(
              label: 'Factura',
              number: '6345',
              accent: Colors.green,
              statusRowHeight: 30 * scale + 28,
              status: const Text(
                'Pagada · Pendiente de cierre',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    edits++;
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.add_card_outlined),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.lock_open_outlined),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text('#6345'));
      expect(text.style!.fontSize, 23);
      final render = tester.renderObject<RenderParagraph>(find.text('#6345'));
      expect(render.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edits, 1);
    });
  }
}
