import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Employee Details restores TEST sections with single-login Owner access',
      () {
    final source = File('lib/screens/settings/employee_edit_screen.dart')
        .readAsStringSync();
    expect(source, contains('authority.authorizeSession(widget.businessId)'));
    expect(source, isNot(contains('authority.authorizeLocal(widget.businessId)')));
    expect(source, isNot(contains('Unlock verified offline details')));
    expect(source, contains('unawaited(_unlockOffline())'));
    expect(source, contains("title: const Text('Payment type')"));
    expect(source, contains("? 'Weekly pay' : 'Hourly rate'"));
    expect(source, contains("label: const Text('Edit offline pay settings')"));
    expect(source, contains('repo.saveLocalPayBasis('));
    expect(source, contains("title: const Text('Phone, email and address')"));
    expect(source, contains("title: const Text('SSN and W-9')"));
    expect(source, contains("title: Text('Default payment method')"));
    expect(source, contains("title: const Text('Position icon')"));
    expect(source, contains('ExpansionTile('));
    expect(source, contains("Full SSN remains protected"));
    expect(source, contains("Not saved locally"));
  });
}
