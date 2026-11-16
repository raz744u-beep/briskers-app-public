import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/payroll/task_selection_dialog.dart';
import 'bugs35_shared_design_test.dart' show capture;

void main() {
  testWidgets('compact service selection scrolls and returns the selected saved item', (tester) async {
    await tester.runAsync(() async {
    for(final entry in {'Roboto':'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'MaterialIcons':'${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries) {
      final file=File(entry.value);
      if(await file.exists()) { await (FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load(); }
    }
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final options = List.generate(20, (i) => {'id':'service-$i', 'name':i == 0 ? 'Oil Change' : 'Saved service $i',
      'description':'Existing invoice service description with additional details that should remain readable and truncate within the compact list.'});
    Map<String,String>? selected;
    await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(theme:ThemeData(fontFamily:'Roboto'),home:Scaffold(body:Builder(builder:(context)=>TextButton(
      onPressed:() async { selected=await showTaskSelection<Map<String,String>>(context,title:'Choose existing service',options:options,
        label:(r)=>r['name']!,description:(r)=>r['description']!); },child:const Text('Choose')))))));
    await tester.tap(find.text('Choose'));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Continue')).onPressed,isNull);
    await tester.tap(find.text('Oil Change'));await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle),findsOneWidget);
    await capture(tester,key,'quick-service-picker');
    await tester.tap(find.text('Continue'));await tester.pumpAndSettle();
    expect(identical(selected,options.first),isTrue);
    expect(tester.takeException(),isNull);
  });
}
