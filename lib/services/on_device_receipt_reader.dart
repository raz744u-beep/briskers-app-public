import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'local_receipt_parser.dart';

/// Latin receipt OCR runs entirely on the Android device. No API or Supabase.
class OnDeviceReceiptReader {
  const OnDeviceReceiptReader();

  Future<Map<String, dynamic>> recognize(
    XFile photo, {
    List<Map<String, dynamic>> vendors = const [],
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      // ML Kit orders text blocks and text lines for typical receipt layouts.
      // Save its text for review; do not claim text recognition is semantic AI.
      return LocalReceiptParser.parse(
        recognized.text,
        vendors: vendors,
        positionedLines: [
          for (final block in recognized.blocks)
            for (final line in block.lines)
              ReceiptOcrFragment(
                text: line.text,
                left: line.boundingBox.left,
                top: line.boundingBox.top,
                height: line.boundingBox.height,
              ),
        ],
      );
    } finally {
      await recognizer.close();
    }
  }
}
