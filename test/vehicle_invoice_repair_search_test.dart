import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/vehicle_invoice_repair_search.dart';

void main() {
  final all = <Map<String,dynamic>>[
    {
      'id':'a-1','kind':'invoice','vehicle_id':'raymond-car-a',
      'document_number':'6000','document_date':'2020-03-10',
      'lines':[
        {'name':'Labor','description':'Replace rear wheel speed sensor'},
        {'name':'Wheel Speed Sensor','description':'ABS diagnostic'}
      ]
    },
    {
      'id':'b-1','kind':'invoice','vehicle_id':'raymond-car-b',
      'document_number':'6500','document_date':'2021-04-01',
      'lines':[{'name':'Water Pump','description':'Cooling system repair'}]
    },
    {
      'id':'a-2','kind':'invoice','vehicle_id':'raymond-car-a',
      'document_number':'6100','document_date':'2022-04-01',
      'lines':[{'name':'Labor','description':'Replace water pump'}]
    },
    {'id':'c-1','kind':'invoice','vehicle_id':'raymond-car-c',
      'document_number':'6700','lines': []},
    {'id':'e-1','kind':'estimate','vehicle_id':'raymond-car-a',
      'document_number':'E-1900','lines':[{'name':'Wheel speed sensor'}]}
  ];
  test('search speed finds original invoice and never a different vehicle', () {
    final hits = VehicleInvoiceRepairSearch.forVehicle(all,
      vehicleId:'raymond-car-a',query:'speed');
    expect(hits.map((x)=>x['id']), ['a-1']);
    expect(VehicleInvoiceRepairSearch.matches(hits.single,'SENSOR'),isTrue);
    expect(VehicleInvoiceRepairSearch.matches(hits.single,'6000'),isTrue);
  });
  test('water pump finds both vehicles only when scoped individually', () {
    expect(VehicleInvoiceRepairSearch.forVehicle(all,
      vehicleId:'raymond-car-a',query:'pump').single['id'],'a-2');
    expect(VehicleInvoiceRepairSearch.forVehicle(all,
      vehicleId:'raymond-car-b',query:'pump').single['id'],'b-1');
  });
  test('invoice line search includes every description, not only first line', () {
    expect(VehicleInvoiceRepairSearch.matches(all.first,'ABS diagnostic'),isTrue);
    expect(VehicleInvoiceRepairSearch.summary(all.first),
      contains('Replace rear wheel speed sensor'));
  });
  test('estimates and unlinked invoices are not mislabeled as completed work', () {
    final matches = VehicleInvoiceRepairSearch.forVehicle(all,
      vehicleId:'raymond-car-a',query:'speed');
    expect(matches.length,1);
    expect(VehicleInvoiceRepairSearch.summary(all[3]), 'Description unavailable');
  });
}
