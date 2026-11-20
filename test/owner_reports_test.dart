import 'dart:convert';
import 'package:briskers_app/core/owner_report_models.dart';
import 'package:briskers_app/services/local_owner_reports.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_invoice_closure.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:briskers_app/services/owner_report_preferences.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReportRow invoice({String id = 'invoice', String job = 'job', num total = 1080, num? tax = 80,
  String date = '2026-11-19', List<ReportRow>? lines}) => {
  'id':id, 'kind':'invoice', 'business_id':'shop', 'job_id':job, 'customer_id':'customer',
  'customer_name':'Jennifer', 'document_date':date, 'status':'open', 'closed_at':0,
  'total_amount':total, 'tax_amount':?tax,
  'lines':lines ?? [{'id':'line','name':'Labor','line_kind':'labor','quantity':18,'unit_price':50,'net_amount':900}],
};
ReportRow credit({String id = 'allocation', int assigned = 1200, int actual = 0,
  int rate = 4000, int paid = 0, int paidMinutes = 0, bool done = false}) => {
  'allocation_id':id, 'business_id':'shop', 'job_id':'job', 'task_id':'task',
  'source_line_id':'line', 'invoice_id':'invoice', 'source_active':1,
  'actual_minutes':actual, 'estimated_minutes':assigned, 'rate_cents':rate,
  'paid_cents':paid, 'paid_minutes':paidMinutes, 'completed':done ? 1 : 0,
};
ReportRow expense(String id, num amount, {String? allocation}) => {
  'id':id, 'allocation_id':allocation ?? id, 'business_id':'shop', 'job_id':'job',
  'document_id':'invoice','direction':'expense','amount':amount,'transaction_date':'2026-11-19',
};
OwnerReportData data({List<ReportRow>? docs, List<ReportRow>? credits,
  List<ReportRow>? spend, List<ReportRow>? transactions, List<ReportRow>? jobs,
  List<String> issues = const []}) => OwnerReportData(business:'shop', invoices:docs ?? [invoice()],
    labor:credits ?? [credit()], expenses:spend ?? [], transactions:transactions ?? [],
    jobs:jobs ?? [{'id':'job','business_id':'shop','status':'in_progress'}], readIssues:issues);
final period = ReportPeriod(DateTime(2026,11,1), DateTime(2026,11,30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('projection uses all assigned hours, not billed hours or cash collected', () {
    final report = data(transactions:[{'id':'receipt','direction':'income','amount':50,'transaction_date':'2026-11-19'}],
      spend:[expense('part',100)]);
    final summary = report.summary(period);
    // $1,000 sales - $100 parts - 20 hours at $40 = $100.
    expect(summary.values[OwnerReportMetric.projected], 10000);
    expect(summary.values[OwnerReportMetric.income],5000);
    expect(summary.values[OwnerReportMetric.net],5000);
    expect(summary.values[OwnerReportMetric.sales],100000);
    expect(summary.values[OwnerReportMetric.salesTax],8000);
    expect(summary.values[OwnerReportMetric.openJobs],1);
  });
  test('projection always includes current jobs even outside the selected historical period', () {
    expect(data().summary(ReportPeriod(DateTime(2020),DateTime(2020,12,31))).values[OwnerReportMetric.projected],20000);
    expect(data().summary(ReportPeriod(DateTime(2020),DateTime(2020,12,31))).values[OwnerReportMetric.sales],0);
  });
  test('closed and completed jobs are excluded; zero closed timestamp is open', () {
    expect(data().openJobs,hasLength(1));
    for (final status in ['closed','completed','done','cancelled']) {
      expect(data(jobs:[{'id':'job','status':status}]).summary(period).values[OwnerReportMetric.projected],0);
    }
    expect(data(docs:[{...invoice(),'closed_at':'2026-11-19'}]).openJobs,isEmpty);
  });
  test('refresh recalculates changed invoice, assigned hours, job status and expenses', () {
    expect(data().summary(period).values[OwnerReportMetric.projected],20000);
    expect(data(docs:[invoice(total:1180)], credits:[credit(assigned:600)],spend:[expense('part',50)])
      .summary(period).values[OwnerReportMetric.projected],65000);
    expect(data(jobs:[{'id':'job','status':'closed'}]).summary(period).values[OwnerReportMetric.openJobs],0);
  });
  test('partially paid wages retain original paid cost and add only remaining assigned minutes', () {
    final report=data(credits:[credit(assigned:180, actual:60, rate:4000, paid:3500, paidMinutes:60)],
      spend:[{...expense('payroll',900),'payroll_operation_id':'week'}]);
    expect(report.jobFigure(report.openJobs.single,projected:true).labor,11500);
    expect(report.jobFigure(report.openJobs.single,projected:true).expenses,0);
    expect(report.jobFigure(report.openJobs.single,projected:false).labor,3500);
  });
  test('missing hours/rate or original payment coverage never creates fabricated profit', () {
    for (final credits in [<ReportRow>[], [credit(rate:0)], [{...credit(),'paid_operation_id':'paid'}],
      [credit(assigned:60, actual:60, paidMinutes:120, paid:8000)]]) {
      expect(data(credits:credits).summary(period).values[OwnerReportMetric.projected],isNull);
    }
    expect(data(docs:[invoice(tax:null)]).summary(period).values[OwnerReportMetric.sales],isNull);
  });
  test('duplicate credit IDs, explicit aliases and inactive unpaid allocations cannot multiply labor', () {
    final report=data(credits:[credit(), credit(), {...credit(id:'alias'),'duplicate_of_task_id':'task'},
      {...credit(id:'retired'),'source_active':0}]);
    expect(report.summary(period).values[OwnerReportMetric.projected],20000);
    final ambiguous=data(credits:[credit(), {...credit(id:'alias',paid:100,paidMinutes:60),'duplicate_of_task_id':'task'}]);
    expect(ambiguous.summary(period).values[OwnerReportMetric.projected],isNull);
  });
  test('business scope, split allocations, voids and reversed entries are respected', () {
    final report=data(docs:[invoice(),invoice(),{...invoice(id:'foreign'),'business_id':'foreign'}],
      spend:[expense('split',25,allocation:'a'),expense('split',25,allocation:'a'),expense('split',15,allocation:'b'),
        {...expense('foreign',1000),'business_id':'foreign'}, {...expense('void',1000),'status':'void'},
        {...expense('reversed',1000),'sync_state':'reversed'}]);
    expect(report.summary(period).values[OwnerReportMetric.sales],100000);
    expect(report.summary(period).values[OwnerReportMetric.projected],16000);
  });
  test('cash report distinguishes verified reporting amounts, refunds and expenses', () {
    final report=data(transactions:[
      {'id':'a','direction':'income','amount':100,'reporting_status':'verified','reporting_amount':97,'transaction_date':'2026-11-01'},
      {'id':'refund','direction':'income','amount':-10,'transaction_date':'2026-11-30T23:59:59'},
      {'id':'expense','direction':'expense','amount':120,'transaction_date':'2026-11-19'},
      {'id':'prior','direction':'income','amount':999,'transaction_date':'2026-10-31'},
    ]);
    expect(report.summary(period).values[OwnerReportMetric.income],8700);
    expect(report.summary(period).values[OwnerReportMetric.net],-3300);
  });
  test('unreadable saved financial data cannot become reassuring zero totals', () {
    expect(data(issues:['Saved financial records could not be read.']).summary(period).values[OwnerReportMetric.income],isNull);
    expect(data(issues:['Job expenses could not be read.']).summary(period).values[OwnerReportMetric.projected],isNull);
  });
  test('customers use stable IDs and historical visits, not equal names', () {
    final report=data(docs:[invoice(), invoice(id:'prior',date:'2026-10-01'),
      {...invoice(id:'new'),'customer_id':'other'}]);
    final rows=report.customers(period);
    expect(rows,hasLength(2));
    expect(rows.singleWhere((r)=>r.id=='customer').newCustomer,isFalse);
    expect(rows.singleWhere((r)=>r.id=='other').newCustomer,isTrue);
    // Job costs cannot all be charged to an incomplete period/customer selection.
    expect(rows.every((r)=>r.profit==null),isTrue);
  });
  test('item quantities and labor hours remain separate; absent purchase costs remain unknown', () {
    final report=data(docs:[invoice(lines:[
      {'id':'part','item_id':'part','name':'Pump','quantity':2,'unit_price':100,'unit_cost':60},
      {'id':'other','name':'Coolant','quantity':1,'unit_price':25},
      {'id':'line','name':'Labor','quantity':18,'unit_price':50},
      {'id':'discount','name':'Discount','line_kind':'discount','quantity':1,'net_amount':-20},
    ])]);
    final rows=report.items(period);
    expect(rows.where((r)=>!r.labor&&!r.discount).fold<double>(0,(n,r)=>n+r.quantity),3);
    expect(rows.singleWhere((r)=>r.id=='part').profit,8000);
    expect(rows.singleWhere((r)=>r.name=='Coolant').cost,isNull);
    expect(rows.singleWhere((r)=>r.labor).quantity,18);
    expect(rows.singleWhere((r)=>r.discount).revenue,-2000);
  });
  test('item labor aliases and duplicate IDs do not add paid or completed cost twice', () {
    final report=data(credits:[credit(actual:60,done:true), credit(actual:60,done:true),
      {...credit(id:'alias',actual:60,done:true),'duplicate_of_task_id':'task'},
      {...credit(id:'inactive',actual:0,done:false),'source_active':0}]);
    expect(report.items(period).single.cost,4000);
  });
  test('a second labor line without cost coverage cannot disappear from the forecast', () {
    final doc=invoice();
    doc['lines']=[...(doc['lines'] as List), {'id':'second','name':'Labor','quantity':2,'unit_price':150}];
    expect(data(docs:[doc]).summary(period).values[OwnerReportMetric.projected],isNull);
    final inactive=data(credits:[credit(), {...credit(id:'inactive',actual:60,done:true),'source_active':0}]);
    expect(inactive.summary(period).values[OwnerReportMetric.projected],isNull);
    expect(inactive.items(period).single.cost,isNull);
  });
  test('date presets are inclusive and preserve calendar days across leap months', () {
    final feb=ReportPeriod.preset('lastMonth',DateTime(2024,3,20));
    expect(feb.end,DateTime(2024,2,29));
    expect(feb.contains('2024-02-29T23:59:59-06:00'),isTrue);
    expect(feb.contains('2024-03-01'),isFalse);
    expect(ReportPeriod.preset('30days',DateTime(2026,11,20)).start,DateTime(2026,10,22));
    expect(feb.shift(1).end,DateTime(2024,3,31));
  });
  test('four identical Overview tiles and custom dates survive a new preference instance', () async {
    const prefs=OwnerReportPreferences('tiles-shop');
    final custom=ReportPeriod(DateTime(2026,1,2),DateTime(2026,2,3));
    await Future.wait([prefs.saveTiles(List.filled(4,OwnerReportMetric.projected)),prefs.savePeriod(custom)]);
    const reopened=OwnerReportPreferences('tiles-shop');
    expect(await reopened.tiles(),List.filled(4,OwnerReportMetric.projected));
    expect((await reopened.period(DateTime(2027))).end,DateTime(2026,2,3));
    expect(await const OwnerReportPreferences('other-shop').tiles(),OwnerReportMetric.defaults);
    expect(data().customers(period).single.name,'Jennifer');
  });
  test('bad saved metric only falls back in its own slot; invalid tile counts fail', () async {
    SharedPreferences.setMockInitialValues({'owner_reports_overview_v1:bad':jsonEncode({
      'tiles':['projected','unknown','projected','income']})});
    const prefs=OwnerReportPreferences('bad');
    expect(await prefs.tiles(),[OwnerReportMetric.projected,OwnerReportMetric.expenses,OwnerReportMetric.projected,OwnerReportMetric.income]);
    expect(()=>prefs.saveTiles([]),throwsArgumentError);
  });
  test('local repository denies unauthorized access before database reads', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(LocalOwnerReports(database:db).load('shop',isOwner:false),throwsStateError);
  });
  test('saved SQLite records load offline, remain scoped and do not mutate accounting rows', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES('job','shop','owner','Repair','in_progress')");
    await db.customStatement("INSERT INTO local_customers(id,business_id,display_name) VALUES('customer','shop','Jennifer')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,job_id,customer_id,total,document_date,status) VALUES('invoice','shop','invoice','job','customer',1080,'2026-11-19','open')");
    await db.customStatement('INSERT INTO local_document_details VALUES(?,?)',
      ['briskers_document_detail_shop_invoice',jsonEncode(invoice(lines:[]))]);
    final cache=LocalFinancialCache(database:db);
    await cache.saveTransactions('shop',[expense('parts',100),
      {'id':'income','direction':'income','amount':50,'transaction_date':'2026-11-19'},
      {'id':'foreign','business_id':'other','direction':'income','amount':9999,'transaction_date':'2026-11-19'}]);
    final before=(await db.customSelect('SELECT * FROM local_documents').get()).map((r)=>r.data).toList();
    final repository=LocalOwnerReports(database:db);
    final report=await repository.load('shop',isOwner:true);
    expect(report.summary(period).values[OwnerReportMetric.income],5000);
    expect(report.summary(period).values[OwnerReportMetric.expenses],10000);
    expect(report.summary(period).values[OwnerReportMetric.projected],90000);
    expect((await db.customSelect('SELECT * FROM local_documents').get()).map((r)=>r.data).toList(),before);
    expect((await repository.load('other',isOwner:true)).invoices,isEmpty);
  });
  test('upgrade-era invoice details remain available locally without migrating accounting records', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({'briskers_document_detail_shop_invoice':jsonEncode(invoice(lines:[]))});
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,total,document_date) VALUES('invoice','shop','invoice',1080,'2026-11-19')");
    final report=await LocalOwnerReports(database:db).load('shop',isOwner:true);
    expect(report.summary(period).values[OwnerReportMetric.sales],100000);
    expect(await db.customSelect('SELECT * FROM local_document_details').get(),isEmpty);
  });
  test('SQLite forecast reads assigned hours and frozen paid costs, excluding reversed coverage', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalPayrollRepository(db,business:'shop',owner:true).prepare();
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES('job','shop','owner','Repair','in_progress')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,job_id,total,document_date) VALUES('invoice','shop','invoice','job',1080,'2026-11-19')");
    await db.customStatement('INSERT INTO local_document_details VALUES(?,?)',
      ['briskers_document_detail_shop_invoice',jsonEncode(invoice())]);
    await db.customStatement("INSERT INTO regular_payroll_task_sources(business_id,task_id,invoice_id,line_id,source_kind) VALUES('shop','task','invoice','line','invoice')");
    await db.customStatement("INSERT INTO regular_payroll_estimates VALUES('shop','task','chris',180)");
    await db.customStatement("INSERT INTO local_mechanic_work_credits_v1(business_id,allocation_id,job_id,labor_line_id,task_id,employee_id,actual_minutes,rate_cents) VALUES('shop','allocation','job','line','task','chris',0,4000)");
    await db.customStatement("INSERT INTO regular_payroll_work_coverage VALUES('shop','allocation','paid',60,3500,'{}')");
    await db.customStatement("INSERT INTO regular_payroll_work_coverage VALUES('shop','allocation','reversed',60,9900,'{}')");
    await db.customStatement("INSERT INTO regular_payroll_reversals_v1 VALUES('shop','reversed','owner','Correction','2026-11-19')");
    final repository=LocalOwnerReports(database:db);
    var report=await repository.load('shop',isOwner:true);
    expect(report.jobFigure(report.openJobs.single,projected:true).labor,11500);
    expect(report.summary(period).values[OwnerReportMetric.projected],88500);
    // The raw coverage fallback must also honor the reversal fence.
    await db.customStatement('DROP VIEW regular_payroll_active_coverage_v1');
    report=await repository.load('shop',isOwner:true);
    expect(report.jobFigure(report.openJobs.single,projected:true).labor,11500);
    expect((await db.customSelect('SELECT * FROM regular_payroll_work_coverage').get()),hasLength(2));
  });
  test('a locally finalized receipt represented in both journal and feed is received once', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final receipt=<String,dynamic>{'invoice_id':'invoice','receipt_id':'receipt','operation_id':'receipt',
      'amount':100,'transaction_date':'2026-11-19','receipt_state':'local_finalized'};
    await LocalInvoiceClosureStore(db).prepareIncome();
    await db.customStatement('INSERT INTO local_finalized_invoice_income VALUES(?,?,?,?)',
      ['shop','invoice','receipt',jsonEncode(receipt)]);
    await LocalFinancialTotalsJournal(database:db).record('shop','invoice-payment:receipt',after:{
      ...receipt,'id':'invoice-payment:receipt','direction':'income','document_id':'invoice','locally_finalized_invoice_receipt':true});
    final report=await LocalOwnerReports(database:db).load('shop',isOwner:true);
    expect(report.summary(period).values[OwnerReportMetric.income],10000);
  });
  test('corrupt saved financial snapshot surfaces unknown rather than empty cash', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement("INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES('shop','transactions_snapshot','broken')");
    final report=await LocalOwnerReports(database:db).load('shop',isOwner:true);
    expect(report.summary(period).values[OwnerReportMetric.net],isNull);
  });
}
