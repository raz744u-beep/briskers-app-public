import 'package:flutter/material.dart';

import '../../local/briskers_local_database.dart';
import '../../services/local_document_repository.dart';
import '../../services/local_document_detail_cache.dart';
import '../../services/local_invoice_task_store.dart';
import '../../services/invoice_labor_work_summary.dart';

/// Displays the original saved invoice labor without creating any payroll
/// task, allocation, credit, payment, expense, or status change.
class HistoricalInvoiceLaborReview extends StatefulWidget {
  const HistoricalInvoiceLaborReview({
    super.key,
    required this.businessId,
    required this.database,
    required this.weekStart,
    required this.canView,
  });
  final String businessId;
  final BriskersLocalDatabase database;
  final DateTime weekStart;
  final bool Function() canView;

  /// A line remains invoice history, never an inferred mechanic assignment.
  static List<Map<String,dynamic>> invoiceLaborLines(
      Map<String,dynamic> invoice, Map<String,dynamic> detail) {
    if(detail['kind']!='invoice')return const [];
    final raw=detail['lines']??detail['items'];
    if(raw is! List)return const [];
    return [
      for(final entry in raw)
        if(entry is Map && isInvoiceLaborLine(entry))
          <String,dynamic>{
            'invoice_id':invoice['id'],
            'invoice_number':invoice['document_number'],
            'job_number':invoice['job_number'],
            'document_date':invoice['document_date'],
            'description':(entry['description']??entry['name']??'Labor').toString(),
            'hours':LocalInvoiceTaskStore.invoiceLaborHours(
              Map<String,dynamic>.from(entry)),
          },
    ];
  }

  @override
  State<HistoricalInvoiceLaborReview> createState() =>
      _HistoricalInvoiceLaborReviewState();
}

class _HistoricalInvoiceLaborReviewState
    extends State<HistoricalInvoiceLaborReview> {
  late Future<List<Map<String,dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _history=_read();
  }

  Future<List<Map<String,dynamic>>> _read() async {
    if(!widget.canView())throw StateError('Owner access required.');
    final from=DateTime(widget.weekStart.year,widget.weekStart.month,widget.weekStart.day);
    final end=from.add(const Duration(days:7));
    final docs=await LocalDocumentRepository(database:widget.database)
        .listByKind(widget.businessId,kind:'invoice');
    final cache=LocalDocumentDetailCache(database:widget.database);
    final lines=<Map<String,dynamic>>[];
    for(final document in docs) {
      if(!widget.canView())throw StateError('Owner access changed.');
      final date=DateTime.tryParse(document['document_date']?.toString()??'');
      if(date==null || date.isBefore(from) || !date.isBefore(end))continue;
      final id=document['id']?.toString();
      if(id==null || id.isEmpty)continue;
      final detail=await cache.load(widget.businessId,id);
      if(detail==null)continue;
      lines.addAll(HistoricalInvoiceLaborReview.invoiceLaborLines(document,detail));
    }
    if(!widget.canView())throw StateError('Owner access changed.');
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final end=widget.weekStart.add(const Duration(days:6));
    return Scaffold(
      appBar:AppBar(title:const Text('Saved Invoice Labor · History')),
      body:!widget.canView()
        ? const Center(child:Text('Owner access required.'))
        : FutureBuilder<List<Map<String,dynamic>>>(
          future:_history,
          builder:(context,snapshot) {
            if(snapshot.hasError)return Center(child:Column(
              mainAxisSize:MainAxisSize.min,children:[
                const Text('Saved invoice labor could not be read.'),
                TextButton(onPressed:()=>setState(()=>_history=_read()),
                  child:const Text('Retry')),
              ]));
            if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
            final rows=snapshot.data!;
            return ListView(padding:const EdgeInsets.all(14),children:[
              Text('Week ${widget.weekStart.month}/${widget.weekStart.day}–${end.month}/${end.day}/${end.year}',
                style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:8),
              const Text('Original invoice lines only. These hours are NOT mechanic assignments or unpaid payroll credits. No records are changed.'),
              const SizedBox(height:8),
              Text('Labor lines: ${rows.length}',style:const TextStyle(fontWeight:FontWeight.w700)),
              if(rows.isEmpty)
                const Padding(padding:EdgeInsets.only(top:20),
                  child:Text('No saved invoice labor snapshots found for this week.')),
              for(final row in rows)
                Card(child:ListTile(
                  title:Text(row['description']?.toString()??'Labor'),
                  subtitle:Text('${row['job_number']??'Job'} · Invoice #${row['invoice_number']??'—'} · ${row['document_date']??''}'),
                  trailing:Text(row['hours'] is num
                      ? '${(row['hours'] as num).toStringAsFixed(2)} h' : '—'),
                )),
            ]);
          },
        ),
    );
  }
}
