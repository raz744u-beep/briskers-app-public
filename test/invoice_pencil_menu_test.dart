import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice pencil invokes existing action menu with owner-only Delete', () async {
    final source = await File('lib/screens/jobs/job_document_screen.dart')
        .readAsString();
    expect(source, contains(
      'onPressed: _busy ? null : _showDocumentHeaderActions,'
    ));
    expect(source, contains("if (widget.isOwner && (!_estimate || !_converted))"));
    expect(source, contains("await _deleteOrVoidInvoice();"));
  });
}
