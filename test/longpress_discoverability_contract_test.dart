import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs show a long-press hint only when card actions are available', () {
    final jobs = File('lib/widgets/job_compact_card.dart').readAsStringSync();
    expect(jobs, contains('onLongPress: canOpen ? onLongPress : null'));
    expect(jobs, contains('if (canOpen && onLongPress != null)'));
    expect(jobs, contains("tr('longPressForOptions')"));
    expect(jobs, contains('onTap: canOpen ? onOpen : null'));
  });

  test('Estimates and invoices share one discoverable long-press hint', () {
    final documents = File('lib/screens/documents_screen.dart')
        .readAsStringSync();
    expect(documents, contains('onTap: () => _open(row)'));
    expect(documents, contains('onLongPress: () => _showDocumentActions(row)'));
    expect(documents, contains("tr('longPressForOptions')"));
    expect(documents, contains("bool get _estimate => widget.kind == 'estimate'"));
  });

  test('Long-press hint is translated in both supported languages', () {
    final translations = File('lib/core/briskers_i18n.dart').readAsStringSync();
    expect(translations, contains("'longPressForOptions': 'Long press for options'"));
    expect(translations, contains("'longPressForOptions': 'Mantén pulsado: opciones'"));
  });
}
