import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    if (data?['platform'] != 'android') {
      throw StateError('Android render required');
    }
    final directory = Directory('build/android-approved-screens');
    await directory.create(recursive: true);
    for (final entry in (data!['screens'] as Map).entries) {
      await File(
        '${directory.path}/${entry.key}.png',
      ).writeAsBytes(base64Decode(entry.value as String));
    }
    await File('${directory.path}/source.txt').writeAsString(
      'Android emulator; production Flutter widgets; synthetic offline fixture data.\ncommit=${Platform.environment['GITHUB_SHA']}\n',
    );
  },
);
