import 'package:briskers_app/core/briskers_colors.dart';
import 'package:briskers_app/services/local_recent_records.dart';
import 'package:briskers_app/widgets/briskers_section_card.dart';
import 'package:briskers_app/widgets/recent_records_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const entries=<RecentRecord>[
  (kind:RecentRecordKind.invoice,id:'invoice-6360',label:'#6360 · Tyra Legard'),
  (kind:RecentRecordKind.invoice,id:'invoice-6379',label:'#6379 · Glenda Allen'),
  (kind:RecentRecordKind.invoice,id:'invoice-6380',label:'#6380 · Glenn Smith'),
  (kind:RecentRecordKind.estimate,id:'estimate-1995',label:'#E-1995 · Tyra Legard'),
  (kind:RecentRecordKind.customer,id:'customer-tyra',label:'Tyra Legard'),
  (kind:RecentRecordKind.invoice,id:'invoice-6359',label:'#6359 · Gloria Johnson'),
  (kind:RecentRecordKind.job,id:'job-40',label:'J-40 · Gloria Johnson'),
  (kind:RecentRecordKind.customer,id:'customer-glenn',label:'Glenn Smith'),
];

void main() {
  for(final config in [(393.0,1.0),(320.0,1.8)]) {
    testWidgets('branded recent records preserve identity, order and clear action at ${config.$1} scale ${config.$2}',(tester) async {
      tester.view.physicalSize=Size(config.$1,2400);
      tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opened=<RecentRecord>[];
      var cleared=0;
      await tester.pumpWidget(MaterialApp(theme:ThemeData(colorSchemeSeed:Colors.purple),
        home:MediaQuery(data:MediaQueryData(size:Size(config.$1,2400),textScaler:TextScaler.linear(config.$2)),
          child:Scaffold(body:SingleChildScrollView(child:RecentRecordsCard(
            records:entries,onOpen:opened.add,onClear:(){cleared++;},
          ))))));
      expect(find.text('Recently Viewed'),findsOneWidget);
      expect(find.byType(BriskersSectionCard),findsOneWidget);
      expect(tester.widget<Card>(find.byType(Card)).color,BriskersColors.surface);
      expect(find.text('Invoice #6360'),findsNothing);
      expect(find.byIcon(Icons.expand_more),findsOneWidget);
      final title=find.text('Recently Viewed');
      final clear=find.text('Clear History');
      expect(tester.getCenter(title).dy,closeTo(tester.getCenter(clear).dy,2));
      expect(tester.getSize(find.byType(BriskersSectionCard)).height,lessThan(80));
      await tester.tap(clear);
      await tester.pump();
      expect(cleared,1);
      expect(find.text('Invoice #6360'),findsNothing,
        reason:'Clear History must not also expand the header');
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.text('Invoice #6360'),findsOneWidget);
      expect(find.text('Estimate E-1995'),findsOneWidget);
      expect(find.text('Job J-40'),findsOneWidget);
      final receipts=tester.widgetList<Icon>(find.byIcon(Icons.receipt_long_outlined));
      expect(receipts.every((icon)=>icon.color==BriskersColors.invoices),isTrue);
      expect(tester.widget<Icon>(find.byIcon(Icons.description_outlined)).color,BriskersColors.estimates);
      expect(tester.widget<Icon>(find.byIcon(Icons.build_outlined)).color,BriskersColors.jobs);
      double prior=-1;
      for(final entry in entries) {
        final row=find.byKey(ValueKey('recent-${entry.kind.name}-${entry.id}'));
        final top=tester.getTopLeft(row).dy;
        expect(top,greaterThan(prior)); prior=top;
        await tester.tap(row);
      }
      expect(opened,entries);
      await tester.tap(find.text('Clear History'));
      expect(cleared,2);
      expect(find.byIcon(Icons.expand_less),findsOneWidget);
      await tester.tap(find.text('Recently Viewed'));
      await tester.pump();
      expect(find.text('Invoice #6360'),findsNothing);
      expect(find.byIcon(Icons.expand_more),findsOneWidget);
      expect(entries.length,8,reason:'The view must not modify business records or history itself');
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('empty history has branded empty state; malformed old labels never expose internal IDs',(tester) async {
    Widget page(List<RecentRecord> records)=>MaterialApp(home:Scaffold(body:RecentRecordsCard(
      records:records,onOpen:(_){},onClear:(){fail('Empty history cannot be cleared');},
    )));
    await tester.pumpWidget(page(const []));
    expect(find.text('No records viewed yet.'),findsNothing);
    await tester.tap(find.text('Recently Viewed'));
    await tester.pump();
    expect(find.text('No records viewed yet.'),findsOneWidget);
    expect(find.text('Clear History'),findsNothing);
    await tester.pumpWidget(page(const [
      (kind:RecentRecordKind.estimate,id:'same-record',label:'#E-EST-internal-id · Tyra Legard'),
    ]));
    expect(find.text('Estimate'),findsOneWidget);
    expect(find.textContaining('E-EST'),findsNothing);
    expect(find.text('Tyra Legard'),findsOneWidget);
    await tester.pumpWidget(page(const [
      (kind:RecentRecordKind.invoice,id:'historical',label:'#INV-2019-A · Saved Customer'),
    ]));
    expect(find.text('#INV-2019-A · Saved Customer'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
