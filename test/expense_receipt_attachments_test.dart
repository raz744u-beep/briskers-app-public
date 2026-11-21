import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/screens/expenses/expense_receipt_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _opaqueName =
    'scaled_7e2f7381-51b8-4248-994a-720ca682b14b_'
    'image_picker_1602403122_2740404730189653088.jpg';

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.initialPhotos, this.textScale = 1});

  final List<XFile> initialPhotos;
  final double textScale;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<XFile> photos = List<XFile>.of(widget.initialPhotos);
  bool enabled = true;
  int changeCount = 0;

  void setEnabled(bool value) => setState(() => enabled = value);
  void replacePhotos(List<XFile> value) => setState(() => photos = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: BriskersLanguageController.instance.locale,
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(widget.textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ExpenseReceiptAttachments(
              receipts: photos,
              enabled: enabled,
              onChanged: (value) => setState(() {
                changeCount++;
                photos = value;
              }),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File localPhoto;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
    directory = await Directory.systemTemp.createTemp('receipt-widget-test-');
    localPhoto = File('${directory.path}/synthetic.png');
    await localPhoto.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      ),
    );
  });

  tearDown(() async {
    await BriskersLanguageController.instance.setLanguage('en');
    await directory.delete(recursive: true);
  });

  List<XFile> photos() => [
    XFile(localPhoto.path, name: _opaqueName),
    XFile(localPhoto.path, name: _opaqueName),
    XFile(localPhoto.path, name: 'third-synthetic-photo.png'),
  ];

  Future<GlobalKey<_HarnessState>> open(
    WidgetTester tester, {
    List<XFile>? initialPhotos,
    double width = 360,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        initialPhotos: initialPhotos ?? photos(),
        textScale: textScale,
      ),
    );
    // Drain the real local file reads before checking their previews. These are
    // synthetic fixtures only; no API, account, or real attachment access.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      final ready = find.byWidgetPredicate(
        (widget) => widget is Text &&
            ((widget.data ?? '').contains('KB') ||
                widget.data == tr('receiptPhotoPreviewUnavailable')),
      );
      if (ready.evaluate().length == key.currentState!.photos.length) break;
    }
    return key;
  }

  Finder removeButton(int number) => find.descendant(
    of: find.byKey(ValueKey('expense-receipt-$number')),
    matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
  );

  testWidgets('friendly labels and readable Remove fit a narrow screen', (
    tester,
  ) async {
    await open(tester, width: 320, textScale: 2);
    expect(find.text('Receipt photo 1'), findsOneWidget);
    expect(find.text('Receipt photo 2'), findsOneWidget);
    expect(find.text(_opaqueName), findsNothing);
    expect(find.textContaining('scaled_'), findsNothing);
    expect(find.text('Remove'), findsNWidgets(3));
    expect(tester.getSize(removeButton(1)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(removeButton(1)).width, greaterThanOrEqualTo(104));
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal phone width keeps Remove beside the photo details', (
    tester,
  ) async {
    await open(tester, width: 412, initialPhotos: [photos().first]);
    final labelRect = tester.getRect(find.text('Receipt photo 1'));
    final removeRect = tester.getRect(removeButton(1));
    expect(removeRect.left, greaterThan(labelRect.right));
    expect(find.textContaining('File date:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel and Back leave every selected photo unchanged', (
    tester,
  ) async {
    final key = await open(tester);
    final original = List<XFile>.of(key.currentState!.photos);
    await tester.tap(removeButton(2));
    await tester.pumpAndSettle();
    expect(find.text('Remove receipt photo?'), findsOneWidget);
    expect(find.textContaining('Remove Receipt photo 2'), findsOneWidget);
    expect(key.currentState!.changeCount, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, orderedEquals(original));

    await tester.tap(removeButton(2));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, orderedEquals(original));
    expect(key.currentState!.changeCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm removes only selected copy, leaving local file intact', (
    tester,
  ) async {
    final selected = photos();
    final key = await open(tester, initialPhotos: selected);
    expect(selected[0].path, selected[1].path);
    await tester.tap(removeButton(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-receipt-removal')));
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, orderedEquals([selected[0], selected[2]]));
    expect(key.currentState!.changeCount, 1);
    expect(localPhoto.existsSync(), isTrue);
    expect(find.text('Receipt photo 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tapping Remove opens only one confirmation', (
    tester,
  ) async {
    final key = await open(tester);
    final callback = tester.widget<OutlinedButton>(removeButton(1)).onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.text('Remove receipt photo?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-receipt-removal')));
    await tester.pumpAndSettle();
    expect(key.currentState!.changeCount, 1);
    expect(key.currentState!.photos, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving or scanning disables removal and pending confirmations', (
    tester,
  ) async {
    final key = await open(tester);
    final original = List<XFile>.of(key.currentState!.photos);
    key.currentState!.setEnabled(false);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(removeButton(1)).onPressed, isNull);
    final thumbnail = find.descendant(
      of: find.byTooltip('View Receipt photo 1'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(thumbnail).onTap, isNull);
    key.currentState!.setEnabled(true);
    await tester.pump();
    await tester.tap(removeButton(1));
    await tester.pumpAndSettle();
    key.currentState!.setEnabled(false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-receipt-removal')));
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, orderedEquals(original));
    expect(key.currentState!.changeCount, 0);
  });

  testWidgets('a changed list cannot remove a different photo after confirmation', (
    tester,
  ) async {
    final selected = photos();
    final key = await open(tester, initialPhotos: selected);
    await tester.tap(removeButton(2));
    await tester.pumpAndSettle();
    key.currentState!.replacePhotos([selected[0], selected[2]]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-receipt-removal')));
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, orderedEquals([selected[0], selected[2]]));
    expect(key.currentState!.changeCount, 0);
  });

  testWidgets('Spanish labels and confirmation fit at large text scale', (
    tester,
  ) async {
    await BriskersLanguageController.instance.setLanguage('es');
    final key = await open(tester, width: 320, textScale: 2);
    expect(find.text('Foto del recibo 1'), findsOneWidget);
    expect(find.text('Eliminar'), findsNWidgets(3));
    await tester.tap(removeButton(1));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar foto del recibo?'), findsOneWidget);
    expect(find.textContaining('Foto del recibo 1'), findsWidgets);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail opens a closeable local preview without mutating photos', (
    tester,
  ) async {
    final key = await open(tester, initialPhotos: [photos().first]);
    final thumbnail = find.descendant(
      of: find.byTooltip('View Receipt photo 1'),
      matching: find.byType(InkWell),
    );
    final openPreview = tester.widget<InkWell>(thumbnail).onTap!;
    openPreview();
    openPreview();
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(find.byTooltip('View Receipt photo 1'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(key.currentState!.photos, hasLength(1));
    expect(key.currentState!.changeCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing local file still has a safe Remove action', (
    tester,
  ) async {
    final missing = XFile('${directory.path}/missing-synthetic.png');
    final key = await open(tester, initialPhotos: [missing]);
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.text('Receipt photo 1'), findsOneWidget);
    await tester.tap(removeButton(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-receipt-removal')));
    await tester.pumpAndSettle();
    expect(key.currentState!.photos, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
