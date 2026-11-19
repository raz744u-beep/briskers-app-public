/// Read-only PDF projection. Warranty is saved as a nested invoice snapshot
/// offline; all renderer paths must see the same saved allocation and references.
class InvoiceWarrantyPdfProjection {
  static const fields = [
    'extended_warranty','warranty_company_id','warranty_company_name',
    'claim_number','authorization_number','claims_phone','submission_email',
    'approved_amount','terminal_amount','net_applied','processor_fee',
    'customer_responsibility','surcharge_rate','signature_required','disclaimers',
  ];
  static Map<String,dynamic> apply(Map<String,dynamic> invoice) {
    final nested=invoice['offline_warranty_detail'];
    if(nested is! Map || invoice['kind']=='estimate') return {...invoice};
    if ((nested['business_id']!=null && invoice['business_id']!=null && nested['business_id']!=invoice['business_id']) ||
        (nested['document_id']!=null && nested['document_id']!=invoice['id'])) return {...invoice};
    return {...invoice,for(final field in fields)
      if(nested.containsKey(field)) field:nested[field]};
  }
}
