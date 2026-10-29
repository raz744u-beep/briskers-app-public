/// A read-only search projection over the invoice details already cached
/// for a single customer. Do not infer repairs from Jobs or other vehicles.
class VehicleInvoiceRepairSearch {
  const VehicleInvoiceRepairSearch._();

  static List<String> repairDescriptions(Map<String, dynamic> invoice) {
    final result = <String>[];
    final seen = <String>{};
    final lines = invoice['lines'];
    if (lines is! List) return result;
    for (final raw in lines) {
      if (raw is! Map) continue;
      final description = [
        raw['description'],
        raw['service_description'],
        raw['notes'],
      ].map((v) => v?.toString().trim() ?? '').where((v) => v.isNotEmpty).join(' · ');
      final name = (raw['name'] ?? raw['item_name'] ?? raw['title'])
          ?.toString().trim() ?? '';
      final entry = [name, description].where((s) => s.isNotEmpty).join(' — ');
      if (entry.isEmpty || !seen.add(entry.toLowerCase())) continue;
      result.add(entry);
    }
    return result;
  }

  static String summary(Map<String, dynamic> invoice) {
    final descriptions = repairDescriptions(invoice);
    if (descriptions.isEmpty) return 'Description unavailable';
    if (descriptions.length == 1) return descriptions.single;
    return '${descriptions.first} (+${descriptions.length - 1} more)';
  }

  static bool matches(Map<String, dynamic> invoice, String query) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return true;
    final values = <String>[
      invoice['document_number']?.toString() ?? '',
      invoice['document_date']?.toString() ?? '',
      invoice['memo']?.toString() ?? '',
      ...repairDescriptions(invoice),
    ];
    return values.any((part) => part.toLowerCase().contains(text));
  }

  static List<Map<String, dynamic>> forVehicle(
      List<Map<String, dynamic>> invoices, {
      required String vehicleId,
      String query = '',
  }) {
    return invoices.where((invoice) =>
      invoice['kind']?.toString() == 'invoice' &&
      invoice['vehicle_id']?.toString() == vehicleId &&
      matches(invoice, query)).toList();
  }
}
