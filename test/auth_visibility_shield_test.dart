import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/auth_visibility_shield.dart';

void main() {
  testWidgets('actor change hides pushed content without disposing draft', (tester) async {
    var actor = 'owner';
    var closes = 0;
    final changes = StreamController<String?>.broadcast();
    final draft = TextEditingController(text: 'private draft');
    await tester.pumpWidget(MaterialApp(home: AuthVisibilityShield(
      actorId: () => actor, actorChanges: changes.stream,
      closePreviousScreens: () { closes++; },
      child: Scaffold(body: TextField(controller: draft)),
    )));
    expect(find.text('private draft'), findsOneWidget);
    actor = 'customer'; changes.add(actor); await tester.pump();
    expect(find.text('private draft'), findsNothing);
    expect(find.text('Close previous screens'), findsOneWidget);
    expect(closes, 0);
    expect(draft.text, 'private draft');
    actor = 'owner'; changes.add(actor); await tester.pump();
    expect(find.text('private draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    draft.dispose(); await changes.close();
  });
  testWidgets('signout hides previous actor until explicit screen close', (tester) async {
    String? actor = 'owner';
    var closes = 0;
    final changes = StreamController<String?>.broadcast();
    await tester.pumpWidget(MaterialApp(home: AuthVisibilityShield(
      actorId: () => actor, actorChanges: changes.stream,
      closePreviousScreens: () { closes++; },
      child: const Scaffold(body: Text('old shop')),
    )));
    actor = null; changes.add(null); await tester.pump();
    expect(find.text('old shop'), findsNothing);
    await tester.tap(find.text('Close previous screens')); await tester.pump();
    expect(closes, 1);
    await tester.pumpWidget(const SizedBox.shrink()); await changes.close();
  });
  testWidgets('initial sign-in does not block login flow', (tester) async {
    String? actor;
    final changes = StreamController<String?>.broadcast();
    await tester.pumpWidget(MaterialApp(home: AuthVisibilityShield(
      actorId: () => actor, actorChanges: changes.stream,
      closePreviousScreens: () {}, child: const Text('login'),
    )));
    actor = 'owner'; changes.add(actor); await tester.pump();
    expect(find.text('login'), findsOneWidget);
    expect(find.text('Close previous screens'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); await changes.close();
  });
  testWidgets('known role change locks unchanged actor until explicit close', (tester) async {
    const actor = 'owner';
    var closes = 0;
    final changes = StreamController<String?>.broadcast();
    await tester.pumpWidget(MaterialApp(home: AuthVisibilityShield(
      actorId: () => actor, actorChanges: changes.stream,
      closePreviousScreens: () { closes++; },
      child: const Scaffold(body: Text('previous financial details')),
    )));
    authVisibilityEpoch.value++;
    await tester.pump();
    expect(find.text('previous financial details'), findsNothing);
    changes.add(actor);
    await tester.pump();
    expect(find.text('previous financial details'), findsNothing);
    expect(closes, 0);
    await tester.tap(find.text('Close previous screens'));
    await tester.pump();
    expect(closes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });

  testWidgets('explicit close replaces real Navigator before old route can animate', (tester) async {
    var actor = 'owner';
    final changes = StreamController<String?>.broadcast();
    var navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(StatefulBuilder(builder: (context, rebuild) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('current account home')),
        builder: (context, child) => AuthVisibilityShield(
          actorId: () => actor,
          actorChanges: changes.stream,
          closePreviousScreens: () {
            rebuild(() { navigatorKey = GlobalKey<NavigatorState>(); });
          },
          child: child!,
        ),
      );
    }));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('old actor private invoice')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('old actor private invoice'), findsOneWidget);
    actor = 'customer';
    changes.add(actor);
    await tester.pump();
    expect(find.text('old actor private invoice'), findsNothing);
    await tester.tap(find.text('Close previous screens'));
    // One frame only: a pop/reverse transition would still retain the old route.
    await tester.pump();
    expect(find.text('old actor private invoice', skipOffstage: false), findsNothing);
    expect(find.text('current account home'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('old actor private invoice', skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });

}
