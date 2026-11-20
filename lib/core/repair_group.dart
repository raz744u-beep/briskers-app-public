import 'dart:convert';
import 'package:cryptography/dart.dart';

enum RepairDecision { awaitingDecision, approved, declined }
enum RepairAuthorizationMethod { kioskSignature, deviceSignature, telephone, inPerson }

/// A view over existing line identities. Other Items is never a group row.
class RepairGroup {
  const RepairGroup({required this.id, required this.name,
    this.description = '', this.position = 0, this.evidence = const [],
    this.lines = const [], this.decision = RepairDecision.awaitingDecision});
  static const otherId = '__other_items__';
  final String id, name, description;
  final int position;
  final List<Map<String, dynamic>> evidence;
  final List<Map<String, dynamic>> lines;
  final RepairDecision decision;
  bool get isOther => id == otherId;

  /// Uses the document's saved per-line amounts; no parallel pricing engine.
  int get quotedCents => lines.fold(0, (sum, line) => sum + lineCents(line));
  static int lineCents(Map<String, dynamic> line) {
    final total = num.tryParse('${line['total_amount']}');
    final net = num.tryParse('${line['net_amount']}');
    final tax = num.tryParse('${line['tax_amount']}');
    final amount = total ?? (net != null && tax != null ? net + tax : null);
    if (amount == null || !amount.isFinite) {
      throw StateError('Save complete item amounts before authorizing repairs.');
    }
    return (amount * 100).round();
  }

  static Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) { return value.map(canonical).toList(); }
    return value;
  }
  static String hash(Object? value) => base64UrlEncode(const DartSha256()
    .hashSync(utf8.encode(jsonEncode(canonical(value)))).bytes);

  /// Status, sync versions and mechanic assignments are not customer scope.
  /// Prices, quantities, descriptions, taxes and linked evidence are scope.
  String fingerprint(Map<String, dynamic> document) => hash({
    'group': id, 'name': name, 'description': description, 'evidence': evidence,
    'customer': document['customer_id'], 'vehicle': document['vehicle_id'],
    'job': document['job_id'],
    'terms': {for (final key in ['memo', 'discount_amount', 'supplies_amount',
      'tax_rate']) key: document[key]},
    'general_charges': [for (final line in _lines(document))
      if (isGeneralCharge(line)) _scopeLine(line)],
    'lines': [for (final line in lines) _scopeLine(line)],
  });
  static Map<String, dynamic> _scopeLine(Map<String, dynamic> line) => {
    for (final key in ['id', 'name', 'description', 'item_id', 'line_kind',
      'quantity', 'unit_price', 'tax_rate', 'tax_mode', 'net_amount',
      'tax_amount', 'total_amount', 'discount_method', 'discount_value',
      'discount_timing']) key: line[key],
  };
  static bool isGeneralCharge(Map<String, dynamic> line) =>
    const {'supplies', 'shop_supplies', 'discount'}.contains(line['line_kind']) ||
    (line['line_kind'] != 'labor' && const {'shop supplies', 'supplies'}
      .contains(line['name']?.toString().trim().toLowerCase()));
  static List<Map<String, dynamic>> _lines(Map<String, dynamic> document) =>
    (document['lines'] as List? ?? const []).whereType<Map>()
      .map((line) => Map<String, dynamic>.from(line)).toList();
}
