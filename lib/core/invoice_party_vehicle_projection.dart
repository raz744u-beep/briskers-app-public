/// Read-only presentation fallback for an invoice's exact saved customer and
/// vehicle identities. Never changes invoice, customer, vehicle, or sync data.
class InvoicePartyVehicleProjection {
  const InvoicePartyVehicleProjection._();

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static bool _populated(Object? value) {
    if(value==null)return false;
    if(value is String)return value.trim().isNotEmpty;
    if(value is Map)return value.values.any(_populated);
    return _text(value).isNotEmpty;
  }

  static Map<String, dynamic> apply({
    required Map<String, dynamic> invoice,
    required Map<String, dynamic>? savedCustomerDetail,
  }) {
    final result=Map<String, dynamic>.from(invoice);
    final kind=_text(invoice['kind']);
    if(kind!='invoice' && kind!='estimate')return result;
    final customerId=_text(invoice['customer_id']);
    final vehicleId=_text(invoice['vehicle_id']);
    if(customerId.isEmpty || savedCustomerDetail==null)return result;
    final customerRaw=savedCustomerDetail['customer'];
    if(customerRaw is! Map)return result;
    final customer=Map<String,dynamic>.from(customerRaw);
    if(_text(customer['id'])!=customerId)return result;

    void fill(String field,Object? value) {
      if(_populated(result[field]) || !_populated(value))return;
      result[field]=value;
    }

    fill('customer_name',customer['name']);
    fill('customer_phone',customer['phone']);
    fill('customer_email',customer['email']);
    fill('customer_address',customer['billing_address']);
    if(customer['problem_flag']==true && result['customer_problem_flag']==null) {
      result['customer_problem_flag']=true;
    }

    // Do not borrow the primary, most recent or similarly named vehicle.
    // Only the invoice's exact linked vehicle ID may supply VIN and plate.
    if(vehicleId.isEmpty)return result;
    final rawVehicles=savedCustomerDetail['vehicles'];
    if(rawVehicles is! List)return result;
    final matched=rawVehicles.whereType<Map>()
        .map((value)=>Map<String,dynamic>.from(value))
        .where((v)=>_text(v['id'])==vehicleId).toList();
    if(matched.length!=1)return result;
    final vehicle=matched.single;
    fill('vehicle_vin',vehicle['vin']);
    fill('vehicle_license_plate',vehicle['license_plate']);
    fill('vehicle_license_state',vehicle['license_state']);
    fill('vehicle_color',vehicle['color']);
    if(_text(result['vehicle']).isEmpty) {
      final label=[
        _text(vehicle['year']),
        _text(vehicle['make']),
        _text(vehicle['model']),
      ].where((value)=>value.isNotEmpty).join(' ');
      fill('vehicle',label);
    }
    return result;
  }

  /// Match the customer address formatting already used in invoice PDFs.
  static String readableAddress(Object? address) {
    if(address==null)return '';
    if(address is String)return address.trim();
    if(address is! Map)return '';
    final map=Map<String,dynamic>.from(address);
    final formatted=_text(map['formatted']);
    if(formatted.isNotEmpty)return formatted;
    final street=[_text(map['line1']),_text(map['line2'])]
      .where((item)=>item.isNotEmpty).join(' ');
    final region=[_text(map['state']),
      _text(map['postal_code']).isEmpty?_text(map['zip']):_text(map['postal_code'])]
      .where((item)=>item.isNotEmpty).join(' ');
    final locality=[_text(map['city']),region]
      .where((item)=>item.isNotEmpty).join(', ');
    return [street,locality].where((item)=>item.isNotEmpty).join('\n');
  }
}
