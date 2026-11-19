import 'dart:convert';
import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';
import '../core/invoice_warranty_pdf_projection.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Signature pixels and their exact reviewed invoice content stay together in
/// SQLite. Editing signed content invalidates presentation, never deletes proof.
class LocalInvoiceSignatureStore {
  LocalInvoiceSignatureStore({BriskersLocalDatabase? database}):db=database??localDatabase;
  final BriskersLocalDatabase db;
  Future<void> _ensure() => db.customStatement('CREATE TABLE IF NOT EXISTS local_invoice_signatures_v1('
    'business_id TEXT NOT NULL,document_id TEXT NOT NULL,signer_name TEXT NOT NULL,'
    'signed_at TEXT NOT NULL,content_hash TEXT NOT NULL,image_bytes BLOB NOT NULL,'
    'PRIMARY KEY(business_id,document_id))');
  static Object? _canonical(Object? value) {
    if(value is Map) {
      final keys=value.keys.map((k)=>k.toString()).toList()..sort();
      return {for(final key in keys) key:_canonical(value[key])};
    }
    if(value is List)return value.map(_canonical).toList();
    return value;
  }
  static String fingerprint(Map<String,dynamic> invoice) {
    final detail=InvoiceWarrantyPdfProjection.apply(invoice);
    final fields=['id','kind','document_number','document_date','customer_id','customer_name',
      'customer_address','vehicle_id','vehicle','vehicle_vin','vehicle_license_plate',
      'odometer_in','mileage_out','odometer_out','memo','finding_notes','lines',
      'net_amount','tax_amount','total_amount','warranty_message',
      ...InvoiceWarrantyPdfProjection.fields];
    final content={for(final field in fields) field:detail[field]};
    return base64Encode(const DartSha256().hashSync(utf8.encode(jsonEncode(_canonical(content)))).bytes);
  }
  bool _matches(String business,String document,Map<String,dynamic> detail) =>
      business.isNotEmpty && document.isNotEmpty && detail['id']==document && detail['kind']=='invoice' &&
      (detail['business_id']==null || detail['business_id']==business);
  Future<void> save(String business,String document,Map<String,dynamic> invoice,{
    required String signerName,required Uint8List bytes,
  }) async {
    if(!_matches(business,document,invoice) || signerName.trim().isEmpty || bytes.length<8 ||
        base64Encode(bytes.sublist(0,8))!='iVBORw0KGgo=') {
      throw ArgumentError('A saved invoice, signer name and PNG signature are required.');
    }
    await _ensure();
    await db.customStatement('INSERT INTO local_invoice_signatures_v1 VALUES(?,?,?,?,?,?) '
      'ON CONFLICT(business_id,document_id) DO UPDATE SET signer_name=excluded.signer_name,'
      'signed_at=excluded.signed_at,content_hash=excluded.content_hash,image_bytes=excluded.image_bytes',
      [business,document,signerName.trim(),DateTime.now().toUtc().toIso8601String(),fingerprint(invoice),bytes]);
  }
  Future<bool> exists(String business,String document) async {
    await _ensure();
    return (await db.customSelect('SELECT 1 FROM local_invoice_signatures_v1 WHERE business_id=? AND document_id=?',
      variables:[Variable(business),Variable(document)]).get()).isNotEmpty;
  }
  Future<Map<String,dynamic>> project(String business,String document,Map<String,dynamic> invoice) async {
    if(!_matches(business,document,invoice))return invoice;
    await _ensure();
    final row=await db.customSelect('SELECT * FROM local_invoice_signatures_v1 WHERE business_id=? AND document_id=?',
      variables:[Variable(business),Variable(document)]).getSingleOrNull();
    if(row==null)return invoice;
    if(row.read<String>('content_hash')!=fingerprint(invoice)) { return {
      ...invoice,'signature_current':false,'signature_bytes':null,'signer_name':null,'signed_at':null,
    }; }
    return {...invoice,'signature_bytes':row.read<Uint8List>('image_bytes'),
      'signer_name':row.read<String>('signer_name'),'signed_at':row.read<String>('signed_at'),
      'signature_current':true,'signature_saved_locally':true};
  }
}
