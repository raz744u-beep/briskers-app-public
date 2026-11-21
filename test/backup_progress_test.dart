import 'package:briskers_app/services/backup/local_backup_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native progress reports file counts and actual streamed byte work',
    () async {
      LocalBackupService.listenForTransferProgress();
      addTearDown(() => LocalBackupService.channel.setMethodCallHandler(null));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      Future<BackupTransferProgress> event({
        required int copied,
        required int transferred,
        required int checked,
        required int verified,
        String operation = 'Photos',
      }) async {
        await messenger.handlePlatformMessage(
          'com.briskers/backup',
          codec.encodeMethodCall(
            MethodCall('backupProgress', {
              'operation': operation,
              'copied': copied,
              'total': 5000,
              'bytes': transferred,
              'checked': checked,
              'verified': verified,
              'totalBytes': 20971520,
            }),
          ),
          (_) {},
        );
        return LocalBackupService.transferProgress.value!;
      }

      final copying = await event(
        copied: 250,
        transferred: 10485760,
        checked: 5242880,
        verified: 5242880,
      );
      expect(
        copying.description,
        contains('Photos · Copying 250 of 5,000 files'),
      );
      expect(copying.description, contains('10,485,760 bytes) transferred'));
      expect(copying.description, contains('5,242,880 bytes) verified'));
      expect(copying.fraction, closeTo(0.375, 0.0001));

      final checking = await event(
        copied: 250,
        transferred: 10485760,
        checked: 7340032,
        verified: 5242880,
        operation: 'Verification',
      );
      expect(checking.fraction, greaterThan(copying.fraction!));
      expect(checking.verified, copying.verified);
      expect(checking.description, startsWith('Verification'));
    },
  );
}
