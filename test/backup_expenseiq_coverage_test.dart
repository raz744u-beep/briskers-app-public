import 'dart:convert';

import 'package:briskers_app/services/backup/local_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unimported Expense IQ originals cannot be implied by a verified backup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(
        LocalBackupService.expenseIqCoverageMessage(prefs, 'shop-a'),
        contains('have not been imported or checked'),
      );
      expect(
        LocalBackupService.expenseIqImportBackupWarning(prefs, 'shop-a'),
        isNull,
      );

      const key = 'briskers_backup_expenseiq_import_status_v1';
      await prefs.setString(
        key,
        jsonEncode({'business_id': 'shop-b', 'complete': true}),
      );
      expect(
        LocalBackupService.expenseIqCoverageMessage(prefs, 'shop-a'),
        contains('have not been imported or checked'),
      );
      expect(
        LocalBackupService.expenseIqImportBackupWarning(prefs, 'shop-a'),
        isNull,
      );

      await prefs.setString(
        key,
        jsonEncode({
          'business_id': 'shop-a',
          'complete': false,
          'unreadable': 1,
          'outstanding': 2,
        }),
      );
      expect(
        LocalBackupService.expenseIqCoverageMessage(prefs, 'shop-a'),
        contains('incomplete'),
      );
      expect(
        LocalBackupService.expenseIqImportBackupWarning(prefs, 'shop-a'),
        contains('incomplete'),
      );

      await prefs.setString(
        key,
        jsonEncode({
          'business_id': 'shop-a',
          'complete': true,
          'unreadable': 0,
          'outstanding': 0,
        }),
      );
      final message = LocalBackupService.expenseIqCoverageMessage(
        prefs,
        'shop-a',
      );
      expect(message, contains('completed on this device'));
      expect(message, contains('Compare the original folder inventory'));
      expect(
        LocalBackupService.expenseIqImportBackupWarning(prefs, 'shop-a'),
        isNull,
      );

      await prefs.setString(key, '{invalid');
      expect(
        LocalBackupService.expenseIqCoverageMessage(prefs, 'shop-a'),
        contains('could not be checked'),
      );
      expect(
        LocalBackupService.expenseIqImportBackupWarning(prefs, 'shop-a'),
        contains('unreadable'),
      );
      await prefs.setString(key, '[]');
      expect(
        LocalBackupService.expenseIqImportBackupWarning(prefs, 'shop-a'),
        contains('unreadable'),
      );
    },
  );
}
