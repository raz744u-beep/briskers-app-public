import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/screens/jobs/invoice_warranty_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
  });
  for (final config in [(393.0,1.0),(320.0,2.0),(800.0,1.0)]) {
    testWidgets('warranty label fits with mechanic control at width ${config.$1} scale ${config.$2}',(tester) async {
      tester.view.physicalSize=Size(config.$1,1100);
      tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saves=0;
      await tester.pumpWidget(MaterialApp(home:MediaQuery(
        data:MediaQueryData(size:Size(config.$1,1100),textScaler:TextScaler.linear(config.$2)),
        child:Scaffold(body:SingleChildScrollView(child:InvoiceWarrantyPanel(
          businessId:'fixture-shop',documentId:'fixture-invoice',expectedVersion:1,
          invoiceTotal:1067.39,detail:const {'extended_warranty':true,
            'warranty_company_name':'Assurant','approved_amount':329.62,
            'terminal_amount':320.02,'processor_fee':9.60,
            'customer_responsibility':737.77,'surcharge_rate':0.03},
          paymentProcessed:false,onChanged:() async {},
          onLocalWarrantyChanged:(_) async {saves++;},
          mainMechanic:Container(key:const Key('mechanic-control'),padding:const EdgeInsets.all(12),
            child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Main Mechanic'),Text('Unassigned'),
            ])),
        ))),
      )));
      await tester.pumpAndSettle();
      final title=find.text('Warranty Job');
      final paragraph=tester.renderObject<RenderParagraph>(title);
      final wordLines=paragraph.getBoxesForSelection(
        const TextSelection(baseOffset:0,extentOffset:8)).map((box)=>box.top).toSet();
      expect(wordLines,hasLength(1),reason:'Warranty must not break mid-word');
      if(config.$2==1) {
        final titleLines=paragraph.getBoxesForSelection(
          const TextSelection(baseOffset:0,extentOffset:12)).map((box)=>box.top).toSet();
        expect(titleLines,hasLength(1));
      }
      final mechanic=tester.getRect(find.byKey(const Key('mechanic-control')));
      if(config.$1<520) {
        expect(mechanic.top,greaterThanOrEqualTo(tester.getBottomLeft(find.text('Assurant')).dy));
      } else {
        expect(mechanic.left,greaterThan(tester.getTopRight(title).dx));
      }
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('warranty-job-checkbox'))).value,isTrue);
      expect(saves,0,reason:'A layout change cannot write warranty or payment data');
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
