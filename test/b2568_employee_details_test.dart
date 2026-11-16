import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:briskers_app/screens/settings/employee_edit_screen.dart';

// A controlled, unresolved nickname read tests the screen without relying on
// SQLite executor startup or fake-clock scheduling of a LazyDatabase.
class _SlowNicknameStore extends EmployeeNicknameStore {
  _SlowNicknameStore(this.nicknameRead);
  final Future<String?> nicknameRead;

  @override
  Future<String?> get(String businessId, String employeeId) => nicknameRead;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'known Details paint before slow nickname database without inventing private fields',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await BriskersConnectionModeController.instance
          .setMode(BriskersConnectionMode.offline);

      final nicknameGate = Completer<String?>();
      addTearDown(() async {
        if (!nicknameGate.isCompleted) nicknameGate.complete();
        await BriskersConnectionModeController.instance
            .setMode(BriskersConnectionMode.auto);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeEditScreen(
            businessId: 'shop',
            employeeId: 'a',
            isOwner: true,
            rosterName: 'Known Legal Name',
            rosterPosition: 'Mechanic',
            nicknameStore: _SlowNicknameStore(nicknameGate.future),
            currentOwner: () => null,
          ),
        ),
      );
      await tester.pump();

      // The unresolved nickname lookup must not hide saved roster data,
      // fabricate protected employee values or block the Details paint.
      expect(find.text('Known Legal Name'), findsOneWidget);
      expect(find.text('Mechanic'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Not saved locally'), findsWidgets);

      // Let the nickname lookup exceed its own timeout while preserving the
      // same safe offline Details contents.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.text('Known Legal Name'), findsOneWidget);
      expect(find.text('Mechanic'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Not saved locally'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      if (!nicknameGate.isCompleted) nicknameGate.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
