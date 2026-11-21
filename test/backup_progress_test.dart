import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/backup/local_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native backup progress updates file and byte counters', () async {
    LocalBackupService.listenForTransferProgress();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final codec = const StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'com.briskers/backup',
      codec.encodeMethodCall(const MethodCall('backupProgress', {
        'operation': 'Photos',
        'copied': 250,
        'total': 5000,
        'bytes': 10485760,
        'verified': 5242880,
      })),
      (_) {},
    );
    expect(LocalBackupService.transferProgress.value?['copied'], 250);
    expect(LocalBackupService.transferProgress.value?['total'], 5000);
    expect(LocalBackupService.progress.value, contains('Copying 250 of 5000 files'));
    expect(LocalBackupService.progress.value, contains('10.0 MB transferred'));
    expect(LocalBackupService.progress.value, contains('5.0 MB verified'));
  });
}
