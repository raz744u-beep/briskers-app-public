import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/invoice_party_vehicle_projection.dart';

void main() {
  const invoice={
    'id':'gloria-invoice',
    'kind':'invoice',
    'customer_id':'gloria-id',
    'customer_name':'Gloria Johnson',
    'vehicle_id':'audi-a8l-id',
    'vehicle':'2016 Audi A8L',
    'document_number':'6359',
    'total_amount':3903.96,
    'paid_amount':0,
    'mileage_out':null,
    'sync_state':'pending',
  };
  const saved={
    'customer':{
      'id':'gloria-id',
      'name':'Gloria Johnson',
      'phone':'5045550119',
      'email':'gloria@example.test',
      'billing_address':{
        'line1':'12 Test Street','city':'Gretna','state':'LA',
        'postal_code':'70053',
      },
    },
    'vehicles':[
      {'id':'different-car','vin':'WRONGVIN000000000','license_plate':'NO'},
      {'id':'audi-a8l-id','vin':'WAUZZZ4H1GN000001',
       'license_plate':'GLO123','license_state':'LA',
       'color':'Black','year':2016,'make':'Audi','model':'A8L'},
    ],
  };

  test('Gloria #6359 exact customer and Audi vehicle restore contact, VIN, plate, no money/mileage change', () {
    final original=Map<String,dynamic>.from(invoice);
    final result=InvoicePartyVehicleProjection.apply(
      invoice:original,savedCustomerDetail:saved);
    expect(result['customer_phone'],'5045550119');
    expect(result['customer_email'],'gloria@example.test');
    expect(result['customer_address'],(saved['customer'] as Map)['billing_address']);
    expect(result['vehicle_vin'],'WAUZZZ4H1GN000001');
    expect(result['vehicle_license_plate'],'GLO123');
    expect(result['vehicle_license_state'],'LA');
    expect(result['vehicle_color'],'Black');
    expect(result['total_amount'],3903.96);
    expect(result['mileage_out'],isNull);
    expect(result['sync_state'],'pending');
    expect(original.containsKey('vehicle_vin'),isFalse,
      reason:'Display fallback must not mutate invoice storage');
  });

  test('do not use an unrelated customer or another saved car', () {
    final wrongCustomer=InvoicePartyVehicleProjection.apply(
      invoice:invoice,savedCustomerDetail:{
        ...saved,
        'customer':{'id':'other','phone':'WRONG'},
      });
    expect(wrongCustomer.containsKey('customer_phone'),isFalse);
    expect(wrongCustomer.containsKey('vehicle_vin'),isFalse);

    final wrongVehicle=InvoicePartyVehicleProjection.apply(
      invoice:{...invoice,'vehicle_id':'vehicle-not-cached'},
      savedCustomerDetail:saved);
    expect(wrongVehicle['customer_phone'],'5045550119');
    expect(wrongVehicle.containsKey('vehicle_vin'),isFalse);
    expect(wrongVehicle.containsKey('vehicle_license_plate'),isFalse);
    expect(wrongVehicle['vehicle'],'2016 Audi A8L');
  });

  test('existing authenticated invoice snapshots win over later local contact data', () {
    final result=InvoicePartyVehicleProjection.apply(
      invoice:{
        ...invoice,
        'customer_phone':'EXISTING',
        'customer_email':'existing@example.test',
        'vehicle_vin':'EXISTINGVIN',
        'vehicle_license_plate':'EXISTINGPLATE',
      },
      savedCustomerDetail:saved,
    );
    expect(result['customer_phone'],'EXISTING');
    expect(result['customer_email'],'existing@example.test');
    expect(result['vehicle_vin'],'EXISTINGVIN');
    expect(result['vehicle_license_plate'],'EXISTINGPLATE');
  });

  test('empty or unrelated identity never fabricates invoice contact/vehicle details', () {
    for(final current in [
      {...invoice,'customer_id':''},
      {...invoice,'kind':'expense'},
    ]) {
      final result=InvoicePartyVehicleProjection.apply(
        invoice:current,savedCustomerDetail:saved);
      expect(result.containsKey('vehicle_vin'),isFalse);
      expect(result.containsKey('customer_phone'),isFalse);
    }
    expect(InvoicePartyVehicleProjection.readableAddress(
      ((saved['customer'] as Map)['billing_address'] as Map)),
      '12 Test Street\\nGretna, LA 70053');
  });
}
