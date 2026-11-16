// Run: dart run tools/benchmark_document_list.dart
// Synthetic CPU/allocation comparison only. This does not measure a phone,
// network, SQLite, first paint, or end-to-end module-opening latency.
import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/document_list_refresh.dart';

void main() {
  final before = List<Map<String, dynamic>>.generate(
    5000,
    (i) => {
      'id': 'synthetic-invoice-$i',
      'document_number': 'I-${5000 - i}',
      'kind': 'invoice',
      'status': 'draft',
      'display_status_code': i.isEven ? 'open' : 'pending_close',
      'paid_amount': i.isEven ? 0 : 100,
      'pending_payment': 0,
      'total_amount': 100,
      'row_version': i,
      'created_at': '2026-10-01T12:00:00Z',
      'customer_name': 'Synthetic Customer $i',
    },
  );
  // Separately materialized equal snapshots; no shared map/list identities.
  final after = (jsonDecode(jsonEncode(before)) as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  Map<String, Object> measure(String name, void Function() operation) {
    for (var i = 0; i < 5; i++) {
      operation();
    }
    final samples = <int>[];
    for (var i = 0; i < 15; i++) {
      final watch = Stopwatch()..start();
      operation();
      samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    return {
      'name': name,
      'median_us': samples[samples.length ~/ 2],
      'min_us': samples.first,
      'max_us': samples.last,
    };
  }

  final comparisons = [
    measure('previous_json_encode_equality', () {
      if (jsonEncode(before) != jsonEncode(after)) {
        throw StateError('Synthetic fixture must be equal');
      }
    }),
    measure('structural_equality', () {
      if (!documentListDataEquals(before, after)) {
        throw StateError('Synthetic fixture must be equal');
      }
    }),
  ];

  // Use unsorted input so number parsing is exercised inside the old comparator.
  final shuffled = List<Map<String, dynamic>>.from(before);
  for (var i = 0; i < shuffled.length; i++) {
    final j = (i * 7919 + 101) % shuffled.length;
    final row = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = row;
  }
  int? previousNumber(Map<String, dynamic> row) {
    final matches = RegExp(
      r'[0-9]+',
    ).allMatches(row['document_number']?.toString() ?? '').toList();
    return matches.isEmpty ? null : int.tryParse(matches.last.group(0)!);
  }

  int previousCompare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aNumber = previousNumber(a);
    final bNumber = previousNumber(b);
    if (aNumber != null && bNumber != null) {
      final order = bNumber.compareTo(aNumber);
      if (order != 0) return order;
    } else if (aNumber == null && bNumber != null) {
      return -1;
    } else if (aNumber != null && bNumber == null) {
      return 1;
    }
    return (b['created_at']?.toString() ?? '').compareTo(
      a['created_at']?.toString() ?? '',
    );
  }

  void checkOrder(List<Map<String, dynamic>> rows) {
    if (!documentListDataEquals(rows, before)) {
      throw StateError('Sorting changed the expected document sequence');
    }
  }

  final sorts = [
    measure('previous_number_parsing_in_comparator', () {
      checkOrder(
        List<Map<String, dynamic>>.from(shuffled)..sort(previousCompare),
      );
    }),
    measure('parse_once_snapshot_sort', () {
      checkOrder(orderDocumentListRows(shuffled, estimate: false));
    }),
  ];
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'scope': 'Synthetic host CPU timing, not device/end-to-end latency',
      'rows': before.length,
      'warmups_per_operation': 5,
      'samples_per_operation': 15,
      'equal_snapshots_separately_materialized': true,
      'measurements': [...comparisons, ...sorts],
      'warm_filter_rebuild_sort_count': 0,
    }),
  );
}
