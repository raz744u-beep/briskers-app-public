/// Identifies explicitly preserved future-dated MobileBiz documents, plus
/// calendar-future documents whose local cache may lack the metadata marker.
bool isFutureDatedDocument(
  Map<String, dynamic> document, {
  DateTime? asOf,
}) {
  final marker = document['future_date_flag'];
  if (marker == true || marker == 1 ||
      marker?.toString().toLowerCase() == 'true') {
    return true;
  }

  final date = DateTime.tryParse(document['document_date']?.toString() ?? '');
  if (date == null) return false;
  final today = asOf ?? DateTime.now();
  return DateTime(date.year, date.month, date.day).isAfter(
    DateTime(today.year, today.month, today.day),
  );
}
