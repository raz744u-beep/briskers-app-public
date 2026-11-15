import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:integration_test/integration_test.dart';
import '../test/nov14_seven_approved_screens_test.dart' as screens;

// Test-only entry point. Synthetic records and mocks are never in lib/main.dart.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {
    'platform': Platform.operatingSystem,
    'screens': <String, String>{},
  };
  screens.androidCapture = (tester, key, name) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    (binding.reportData!['screens'] as Map<String, String>)[name] =
        base64Encode(bytes!.buffer.asUint8List());
  };
  screens.main();
}
