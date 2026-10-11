import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PERF-001 records actual invoice first paint, RPC and PDF stages', () async {
    final screen=await File('lib/screens/jobs/job_document_screen.dart').readAsString();
    final diagnostics=await File('lib/services/diagnostics_service.dart').readAsString();
    for (final stage in [
      "'cached_first_paint'", "'detail_rpc'",
      "'detail_with_metadata'", "'pdf_data'", "'pdf_render'",
    ]) {
      expect(screen,contains(stage),reason:'Missing invoice measurement $stage');
    }
    expect(diagnostics,contains("id: 'PERF-001'"));
    expect(diagnostics,contains("record['ms']"));
    expect(diagnostics,contains('1500'));
    expect(diagnostics,contains('4000'));
  });
}
