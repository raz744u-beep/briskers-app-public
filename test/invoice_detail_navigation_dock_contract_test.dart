import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice document details inherit module dock without double dock on list', () {
    final shell = File('lib/screens/shell_screen.dart').readAsStringSync();
    final documents = File('lib/screens/documents_screen.dart').readAsStringSync();
    final dock = File('lib/widgets/briskers_module_dock.dart').readAsStringSync();
    final start = shell.indexOf('if (index == 3 || index == 4)');
    final end = shell.indexOf('if (index == 5)', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final scope = shell.substring(start, end);
    expect(scope, contains('detailBottomNavigationBar: _shellNavigationBar(nested: true)'));
    expect(scope, contains('index == 3 ? _shellNavigationBar(nested: true) : null'));
    expect(documents, contains('final Widget? detailBottomNavigationBar'));
    expect(documents, contains('widget.detailBottomNavigationBar ??'));
    expect('widget.detailBottomNavigationBar ??'.allMatches(documents).length, 3);
    expect(dock, contains('FocusManager.instance.addListener(_onFocusChanged)'));
    expect(dock, contains('FocusManager.instance.removeListener(_onFocusChanged)'));
    expect(dock, contains('MediaQuery.viewInsetsOf(context).bottom > 0 && _editingText'));
  });
}
