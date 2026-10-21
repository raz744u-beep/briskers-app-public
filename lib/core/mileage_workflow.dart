/// Explicit odometer semantics for the new Briskers mileage workflow.
///
/// Legacy invoice `odometer_in` is historically ambiguous. Never silently
/// relabel it "Mileage Out" without provenance. Missing readings stay missing.
class MileageWorkflow {
  const MileageWorkflow._();

  static num? parse(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim().replaceAll(',', '');
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final number = num.tryParse(text);
    if (number == null || !number.isFinite || number < 0 ||
        number > 9999999 || number != number.roundToDouble()) {
      return null;
    }
    return number;
  }

  static num? arrival(Map<String, dynamic> record) =>
      parse(record['mileage_in'] ?? record['odometer_in']);

  static num? departure(Map<String, dynamic> record) =>
      parse(record['mileage_out'] ?? record['odometer_out']);

  static bool getHasExplicitReadings(Map<String, dynamic> record) =>
      record.containsKey('mileage_in') ||
      record.containsKey('mileage_out') ||
      record.containsKey('odometer_out');

  /// Display rows used in vehicle information on the invoice and PDF.
  /// Legacy documents retain a neutral "Mileage" label until migrated.
  static List<(String, num)> printableReadings(
    Map<String, dynamic> document, {
    num? linkedJobMileageIn,
  }) {
    final explicit = getHasExplicitReadings(document);
    if (!explicit) {
      final legacy = parse(document['odometer_in']);
      return legacy == null ? const [] : [('Mileage', legacy)];
    }
    // Never reinterpret an ambiguous legacy invoice value as Mileage In.
    final incoming = parse(document['mileage_in']) ?? linkedJobMileageIn;
    final outgoing = departure(document);
    return [
      if (incoming != null) ('Mileage In', incoming),
      if (outgoing != null && document['kind']?.toString() == 'invoice')
        ('Mileage Out', outgoing),
    ];
  }

  /// Suggest the most recent vehicle odometer after confirmed shop checkout.
  /// Caller must independently confirm document completion, vehicle scope,
  /// chronology, authorization and durable server commit before applying.
  static num? currentVehicleMileageCandidate({
    required num? previous,
    required num? mileageOut,
    required bool verifiedCompletedInvoice,
    required bool isLatestService,
  }) {
    if (!verifiedCompletedInvoice || !isLatestService) return null;
    final value = parse(mileageOut);
    if (value == null) return null;
    final old = parse(previous);
    if (old != null && value < old) return null;
    return value;
  }
}
