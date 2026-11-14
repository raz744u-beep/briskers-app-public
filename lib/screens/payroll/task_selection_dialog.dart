import 'package:flutter/material.dart';

const _teal = Color(0xFF00897E);

/// Shared presentation for the existing service and mechanic selection flow.
/// Selection only returns the original object; it does not create billed work.
Future<T?> showTaskSelection<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  required String Function(T) description,
}) {
  T? selected;
  return showDialog<T>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(color: _teal, fontWeight: FontWeight.w700),
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        content: SizedBox(
          width: 420,
          height: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, index) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final option = options[index];
              final chosen = identical(selected, option);
              final name = label(option).trim();
              final detail = description(option).trim();
              return Material(
                color: chosen
                    ? const Color(0xFFE0F2EF)
                    : const Color(0xFFF7F9FA),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: chosen ? _teal : const Color(0xFFE0E5E7),
                    ),
                  ),
                  title: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: detail.isEmpty || detail == name
                      ? null
                      : Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                  trailing: Icon(
                    chosen ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: chosen ? _teal : const Color(0xFF94A3B8),
                  ),
                  selectedColor: _teal,
              selected: chosen,
                  onTap: () => update(() => selected = option),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            style: TextButton.styleFrom(foregroundColor: _teal),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selected == null
                ? null
                : () => Navigator.pop(dialog, selected),
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> showTaskHours(BuildContext context) async {
  final input = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) {
          final hours = double.tryParse(input.text.trim());
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              'Assign labor',
              style: TextStyle(color: _teal, fontWeight: FontWeight.w700),
            ),
            content: TextField(
              controller: input,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => update(() {}),
              decoration: const InputDecoration(
                labelText: 'Mechanic hours',
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: _teal, width: 2),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                style: TextButton.styleFrom(foregroundColor: _teal),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    hours == null ||
                        !hours.isFinite ||
                        hours < 0 ||
                        hours > 10000
                    ? null
                    : () => Navigator.pop(dialog, input.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    Future<void>.delayed(const Duration(milliseconds: 400), input.dispose);
  }
}

Future<String?> showJobTaskSelection(BuildContext context,List<Map<String,dynamic>> jobs,{bool allowNew=true}) async {
  var query='';
  return showDialog<String>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update){
    final rows=jobs.where((j)=>['job_number','invoice_number','customer_name','vehicle_label','requested_work','title'].map((k)=>j[k]??'').join(' ').toLowerCase().contains(query.toLowerCase())).toList();
    return AlertDialog(scrollable:true,title:const Text('Choose Job · active or historical'),content:SizedBox(width:520,height:(MediaQuery.sizeOf(context).height-MediaQuery.viewInsetsOf(context).bottom-240).clamp(120.0,480.0),child:Column(children:[
      TextField(decoration:const InputDecoration(labelText:'Search job, invoice, customer or vehicle',prefixIcon:Icon(Icons.search)),onChanged:(v)=>update(()=>query=v)),
      Expanded(child:ListView(children:[for(final j in rows)ListTile(
        title:Text('${j['job_number']??'Job'} · ${j['customer_name']??''}',style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text('${j['vehicle_label']??''}\nInvoice #${j['invoice_number']??'—'} · ${j['status_name']??j['status']}\n${j['requested_work']??j['title']??''}',maxLines:4,overflow:TextOverflow.ellipsis),
        onTap:()=>Navigator.pop(dialog,j['id'] as String))])),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel')),if(allowNew)TextButton(onPressed:()=>Navigator.pop(dialog,'new'),child:const Text('Create new Job'))]);
  }));
}
