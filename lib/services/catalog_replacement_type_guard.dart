/// Source-of-truth catalog classification for replacing an invoice line.
///
/// Names are never evidence of a catalog item's type. Legacy invoice lines may
/// still have name-based labor detection; keep their task/payroll identity.
const _nonLaborCatalogTypes = <String>{
  'part',
  'non_inventory',
  'service',
  'fee',
  'other',
};

String normalizedCatalogItemType(Object? value) =>
    value?.toString().trim().toLowerCase() ?? '';

bool catalogItemIsLabor(Object? itemType) {
  final type = normalizedCatalogItemType(itemType);
  return type == 'labor' || type == 'labour';
}

/// Returns a user-facing rejection reason, or null for a safe same-kind change.
String? catalogReplacementTypeError({
  required bool existingLineIsLabor,
  required Object? itemType,
  required Object? itemName,
}) {
  final type = normalizedCatalogItemType(itemType);
  final selectedIsLabor = catalogItemIsLabor(type);
  if (!selectedIsLabor && !_nonLaborCatalogTypes.contains(type)) {
    return 'This catalog item has no verified type. Review its type in Catalog first.';
  }
  if (existingLineIsLabor != selectedIsLabor) {
    return existingLineIsLabor
        ? 'Choose a labor item for this labor line. Manage mechanic assignments separately.'
        : 'A part or item cannot be turned into labor here. Add labor through the job workflow.';
  }
  // Older invoice code recognizes the literal names Labor/Labour as labor;
  // prevent an innocently named part from acquiring that legacy identity.
  final name = itemName?.toString().trim().toLowerCase() ?? '';
  if (!selectedIsLabor && (name == 'labor' || name == 'labour')) {
    return 'A non-labor catalog item cannot be named Labor on an invoice line.';
  }
  return null;
}
