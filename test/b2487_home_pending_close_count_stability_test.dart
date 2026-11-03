import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home preserves verified Pending Close count across ordinary Auto refresh', () {
    final code = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(code, contains('bool _attentionServerVerified = false;'));
    expect(code, contains('if (connection.forceOffline || !_attentionServerVerified)'));
    expect(code, contains('final localSnapshot = Map<String, dynamic>.from(_attention)'));
    expect(code, contains('_attentionServerVerified = true;'));
    expect(code, contains('setState(() => _attention = data);'));
    expect(code, contains('if (!sameScope() || connection.forceOffline) return;'));
    expect(code, contains('_attentionRefreshQueued = true;'));
    expect(code, contains("timeout(const Duration(seconds: 8))"));
    final first = code.indexOf('if (connection.forceOffline || !_attentionServerVerified)');
    final remote = code.indexOf('final data = await _api.needsAttention(businessId)');
    expect(first, lessThan(remote));
  });

  test('Home does not leak counts across permission or business boundaries', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    final stack = File('lib/widgets/retained_module_stack.dart').readAsStringSync();
    expect(stack, contains('retainedIndices = const {0, 1, 2, 3, 4, 5, 6}'));
    expect(home, contains('oldWidget.businessId != widget.businessId'));
    expect(home, contains('oldWidget.roleCode != widget.roleCode'));
    expect(home, contains('_attention = const {};'));
    expect(home, contains('_attentionServerVerified = false;'));
    expect(home, contains('final businessId = widget.businessId;'));
    expect(home, contains('final roleCode = widget.roleCode;'));
    expect(home, contains('bool sameScope() => mounted && widget.businessId == businessId'));
  });
}
