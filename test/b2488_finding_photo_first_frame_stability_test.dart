import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/local_first_attachment_image.dart';

void main() {
  testWidgets('Saved finding photo stays visible during repeated Job rebuilds',
      (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'briskers-finding-photo-test-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    // Tiny valid PNG, stored only in the synthetic temporary test directory.
    final imageFile = File('${directory.path}/synthetic.png');
    await imageFile.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/7Z0AAAAASUVORK5CYII='));
    final attachment = <String, dynamic>{
      'bucket': 'synthetic-bucket',
      'key': 'synthetic/key.png',
      'local_file_path': imageFile.path,
    };
    late StateSetter refresh;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        refresh = setState;
        return Scaffold(body: LocalFirstAttachmentImage(
          key: const ValueKey('same-photo'),
          attachment: attachment,
          width: 82,
          height: 82,
        ));
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    for (var index = 0; index < 8; index++) {
      refresh(() {});
      await tester.pump();
      // Rebuilding Job status/notes must not restart this photo's async read.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  });

  test('Job finding thumbnails reuse stateful local-first image Future', () {
    final source =
        File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final start = source.indexOf('Widget _findingPhotoThumbnail(');
    final end = source.indexOf('Widget _findingsDrawer()', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final thumbnail = source.substring(start, end);
    expect(thumbnail, contains('LocalFirstAttachmentImage('));
    expect(thumbnail, contains("key: ValueKey("));
    expect(thumbnail, contains('onLongPress: attachment'));
    expect(thumbnail, contains('if (waiting)'));
    expect(thumbnail, isNot(contains('FutureBuilder<File?>(')));
    expect(thumbnail, isNot(contains('future: _attachmentCache.getOrDownload(')));

    final image = File('lib/widgets/local_first_attachment_image.dart')
        .readAsStringSync();
    expect(image, contains('_imageFile = _resolve();'));
    expect(image, contains('if (_identity(oldWidget.attachment) !='));
    expect(image, contains('if (BriskersConnectionModeController.instance.forceOffline) return null;'));
  });

  test('Missing remote photo cannot spin forever or delete a saved original', () {
    final source =
        File('lib/services/local_attachment_cache.dart').readAsStringSync();
    expect(source, contains('connectionTimeout = const Duration(seconds: 15)'));
    expect(source, contains('.timeout(const Duration(seconds: 15))'));
    expect(source, contains('response.pipe(sink).timeout(const Duration(seconds: 60))'));
    expect(source, contains('if (await _isUsable(file)) return file;'));
    expect(source, contains('final temp = File('));
    expect(source, contains('return null;'));
  });
}
