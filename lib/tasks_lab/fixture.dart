/// Minimal, sanitized snapshot copied read-only from Briskers on 2026-10-20.
/// No source customer/vehicle/line UUIDs, VIN, contact or payment details.
/// These are LAB identities, never valid production identifiers.
class BriskersLabFixture {
  static const customerName = 'Richard Goff';
  static const vehicles = [
    {'id': 'lab-equus', 'year': '2012', 'make': 'Hyundai',
      'model': 'Equus', 'job': 'J-24'},
    {'id': 'lab-sonata', 'year': '2004', 'make': 'Hyundai',
      'model': 'Sonata', 'job': ''},
  ];
  // Sanitized test roster. Roles are used to prevent non-mechanics from
  // appearing in labor assignment and mechanic payroll previews.
  static const employees = [
    {'id':'lab-kam','name':'Kamerron Smith','nickname':'Kam','role':'mechanic'},
    {'id':'lab-chris','name':'Chris Rideaux','nickname':'Chris','role':'mechanic'},
    {'id':'lab-adam','name':'Adam Bourgeois','nickname':'Adam','role':'mechanic'},
    {'id':'lab-raz','name':'Raz','nickname':'Raz','role':'owner'},
    {'id':'lab-secretary','name':'Secretary (TEST)',
      'nickname':'Secretary','role':'secretary'},
  ];
  static const jobId = 'lab-job-richard-j24';
  static const invoiceId = 'lab-invoice-6342';
  static const businessId = 'briskers-tasks-test-only';
  static const jobDescription = 'Oil leaks, maintenance';
  static const invoiceNumber = '6342';
  static const invoice = <String,dynamic>{
    'kind': 'invoice',
    'job_id': jobId,
    'id': invoiceId,
    'document_number': invoiceNumber,
    'lines': [
      {'id':'lab-valve-covers','line_kind':'item','name':'Labor',
        'description':'Replace valve covers left and right.',
        'quantity':4.0},
      {'id':'lab-spark-plugs','line_kind':'item','name':'Labor',
        'description':'Replace spark plugs (after removing valve covers)',
        'quantity':0.5},
      {'id':'lab-transmission','line_kind':'item','name':'Labor',
        'description':'Replace transmission pan. Refill to factory specs.',
        'quantity':1.5},
      {'id':'lab-differential','line_kind':'item','name':'Labor',
        'description':'Replace rear differential fluid',
        'quantity':0.8},
    ]
  };
}
