/// Local chronological keys, independent of invoice/job number spelling and
/// import/query iteration order. Unknown dates have a deterministic ID fallback.
class ServiceTaskOrder {
  static int timestamp(Object? raw) {
    if(raw is DateTime) return raw.millisecondsSinceEpoch;
    if(raw is num) return raw.abs()<100000000000 ? (raw*1000).round() : raw.round();
    return DateTime.tryParse(raw?.toString()??'')?.millisecondsSinceEpoch??0;
  }
  static int job(Map<String,dynamic> row) => timestamp(row['job_created_at']??row['job_document_date']);
  static int compareJobs(Map<String,dynamic> a,Map<String,dynamic> b,{required bool newest}) {
    var d=job(a).compareTo(job(b));
    if(d==0) d=(a['job_id']?.toString()??'').compareTo(b['job_id']?.toString()??'');
    return newest ? -d : d;
  }
  static int compareLines(Map<String,dynamic> a,Map<String,dynamic> b,{required bool newest}) {
    var d=timestamp(a['invoice_date']??a['invoice_created_at']).compareTo(timestamp(b['invoice_date']??b['invoice_created_at']));
    if(d!=0) return newest ? -d : d;
    d=(a['invoice_id']??a['document_id']??'').toString().compareTo((b['invoice_id']??b['document_id']??'').toString());
    if(d!=0) return d;
    d=((a['line_position'] as int?)??0x7fffffff).compareTo((b['line_position'] as int?)??0x7fffffff);
    if(d!=0) return d;
    return (a['line_id']??a['id']??'').toString().compareTo((b['line_id']??b['id']??'').toString());
  }
}
