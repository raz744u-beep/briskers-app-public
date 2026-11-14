import 'dart:io';
import 'package:flutter/services.dart';

Future<void> loadHandoffFonts() async {
  for (final entry in {
    'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    'MaterialIcons':
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final file = File(entry.value);
    if (await file.exists()) {
      await (FontLoader(entry.key)..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          ))
          .load();
    }
  }
}
