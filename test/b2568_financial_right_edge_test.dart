import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/financial_summary_row.dart';
void main(){
  for(final width in [320.0,390.0,430.0]){
    for(final scale in [1.0,1.5]){
      testWidgets('approved amounts share right edge, width=$width scale=$scale',(tester)async{
        tester.view.resetPhysicalSize();
        await tester.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(size:Size(width,900),textScaler:TextScaler.linear(scale)),
          child:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:width,child:const Column(mainAxisSize:MainAxisSize.min,children:[
            FinancialSummaryRow(label:'Subtotal',value:r'$12,345.67',tone:FinancialSummaryTone.subtotal),
            FinancialSummaryRow(label:'Total',value:r'$8.90',tone:FinancialSummaryTone.total),
            FinancialSummaryRow(label:'Balance Due',value:r'$100.01',tone:FinancialSummaryTone.balanceDue),
          ])))))));
        final a=tester.getRect(find.text(r'$12,345.67')).right;
        expect(tester.getRect(find.text(r'$8.90')).right,closeTo(a,0.1));
        expect(tester.getRect(find.text(r'$100.01')).right,closeTo(a,0.1));
        expect(tester.takeException(),isNull);
      });
    }
  }
}
