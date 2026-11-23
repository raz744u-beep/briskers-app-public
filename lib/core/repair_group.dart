/// A view over existing line identities. Other Items is never a group row.
class RepairGroup {
  const RepairGroup({required this.id, required this.name,
    this.description = '', this.lines = const []});
  static const otherId = '__other_items__';
  final String id, name, description;
  final List<Map<String, dynamic>> lines;
  bool get isOther => id == otherId;

  static bool isGeneralCharge(Map<String, dynamic> line) =>
    const {'supply', 'supplies', 'shop_supplies', 'discount'}.contains(line['line_kind']) ||
    (line['line_kind'] != 'labor' && const {'shop supplies', 'supplies'}
      .contains(line['name']?.toString().trim().toLowerCase()));
}
