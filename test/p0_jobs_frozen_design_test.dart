import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/job_compact_card.dart';
import 'package:briskers_app/services/job_task_summary.dart';

void main() {
  testWidgets('frozen Jobs cards keep exact invoice navigation and narrow phone layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT'];
      for (final pair in <String, String>{
        if (root != null) 'MaterialIcons': '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      }.entries) {
        final file = File(pair.value);
        if (await file.exists()) await (FontLoader(pair.key)..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load();
      }
    });
    final boundary = GlobalKey();
    var invoiceOpens = 0, jobOpens = 0, menus = 0;
    final rows = [
      ['J-49', 'Rick Francis', '6368', '2016 Mercedes E350', 'Battery programming + oil change', 'in_progress', 'In Progress', 'Chris'],
      ['J-52', 'Norman Louis', '6372', '2023 Audi Q3', 'Front wheel liner repair', 'awaiting_parts', 'Awaiting Parts', 'Kam'],
      ['J-48', 'Mick Mitchell', '6367', '2020 BMW X3', 'Brake pads & rotors replacement', 'completed', 'Completed', 'Chris'],
      ['J-53', 'Dana Peters', '6375', '2019 Audi A4', 'Diagnostic + steering inspection', 'awaiting_payment', 'Awaiting Payment', 'Luis'],
    ];
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Roboto'), home: Scaffold(body: RepaintBoundary(key: boundary,
      child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
        for (var i=0; i<rows.length; i++) JobCompactCard(
          approvedListDesign: true,
          job: {'job_number':rows[i][0], 'customer_name':rows[i][1], 'invoice_number':rows[i][2], 'vehicle':rows[i][3], 'title':rows[i][4], 'status':rows[i][5], 'assigned_employee':rows[i][7], 'open_findings':5, 'pending_requests':4},
          statusControl: Container(padding: const EdgeInsets.symmetric(horizontal:8,vertical:3), decoration: BoxDecoration(color: approvedJobListStatusColor({'status':rows[i][5]}).withValues(alpha:0.13),borderRadius:BorderRadius.circular(20)),child:Text(rows[i][6], style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:approvedJobListStatusColor({'status':rows[i][5]})))),
          taskProgress: JobTaskProgress(i==0?1:i==1?0:2,2),
          mechanicMinutes: {rows[i][7]: i==0?120:i==1?60:i==2?402:90},
          onOpen:()=>jobOpens++,onOpenInvoice:()=>invoiceOpens++,onLongPress:()=>menus++,
        ),
      ])),
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    expect(find.text('Chris · 2.0 hrs'),findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded),findsNothing);
    expect(find.byIcon(Icons.notifications_active_outlined),findsNothing);
    expect(find.text('Long press for options'),findsNothing);
    final invoice = tester.widget<Text>(find.text('Invoice #6368'));
    expect(invoice.style!.color,const Color(0xFF526171));
    expect(invoice.style!.decoration,TextDecoration.underline);
    expect(tester.getTopLeft(find.text('Invoice #6368')).dy,
      closeTo(tester.getTopLeft(find.text('J-49  Rick Francis')).dy,3));
    expect(tester.getBottomRight(find.byType(JobCompactCard).last).dy,lessThan(720));
    await tester.tap(find.text('Invoice #6368'));
    expect(invoiceOpens,1);expect(jobOpens,0);
    await tester.tap(find.text('Battery programming + oil change'));
    expect(jobOpens,1);
    await tester.longPress(find.text('Battery programming + oil change'));
    expect(menus,1);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image=await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      final file=File('build/payroll-qa/frozen-jobs-list.png');
      await file.parent.create(recursive:true);await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
