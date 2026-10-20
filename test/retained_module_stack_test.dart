import 'package:briskers_app/widgets/retained_module_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestModule extends StatefulWidget {
  const _TestModule({required this.index, required this.onLoad});

  final int index;
  final ValueChanged<int> onLoad;

  @override
  State<_TestModule> createState() => _TestModuleState();
}

class _TestModuleState extends State<_TestModule> {
  final _scroll = ScrollController();
  String _filter = 'Open';

  @override
  void initState() {
    super.initState();
    widget.onLoad(widget.index);
  }

  @override
  void didUpdateWidget(covariant _TestModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      widget.onLoad(widget.index);
      _filter = 'Open';
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () => setState(() => _filter = 'Closed'),
        child: Text('${widget.index}:$_filter'),
      ),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          itemExtent: 50,
          itemCount: 100,
          itemBuilder: (_, index) => Text('row $index'),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('single-body baseline repeats loading on 31 module entries', (
    tester,
  ) async {
    var loads = 0;
    Future<void> show(int selected) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestModule(index: selected, onLoad: (_) => loads++),
          ),
        ),
      );
    }

    await show(3);
    for (var cycle = 0; cycle < 10; cycle++) {
      await show(4);
      await show(5);
      await show(3);
    }
    expect(loads, 31);
  });

  testWidgets(
    'visited lists preserve filters and scroll without reinitializing',
    (tester) async {
      final loads = <int, int>{};
      void load(int index) => loads[index] = (loads[index] ?? 0) + 1;
      Future<void> show(int selected, {String scope = 'shop-a'}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RetainedModuleStack(
                key: ValueKey(scope),
                index: selected,
                itemCount: 8,
                itemBuilder: (_, index) =>
                    _TestModule(index: index, onLoad: load),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await show(3);
      expect(loads, {3: 1}, reason: 'Unvisited modules must not load eagerly.');
      await tester.tap(find.text('3:Open'));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final state = tester.state<_TestModuleState>(find.byType(_TestModule));
      final position = state._scroll.offset;
      expect(position, greaterThan(0));

      for (var cycle = 0; cycle < 10; cycle++) {
        await show(4);
        await show(5);
        await show(3);
        expect(find.text('3:Closed'), findsOneWidget);
        expect(state._scroll.offset, position);
        expect(
          tester.state<_TestModuleState>(
            find.byType(_TestModule).hitTestable().first,
          ),
          same(state),
        );
      }
      // Deterministic work metric: 31 list entries, 3 initial loads, rather than
      // 31 mounts/loads when the Shell replaces its body on every navigation.
      expect(loads, {3: 1, 4: 1, 5: 1});

      await show(3, scope: 'shop-b');
      expect(loads[3], 2);
      expect(find.text('3:Open'), findsOneWidget);
      expect(
        find.text('3:Closed'),
        findsNothing,
        reason: 'A different business must not inherit another shop’s state.',
      );
    },
  );

  testWidgets('non-retained modules retain existing remount behavior', (
    tester,
  ) async {
    final loads = <int, int>{};
    Future<void> show(int selected) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainedModuleStack(
              index: selected,
              itemCount: 8,
              itemBuilder: (_, index) => _TestModule(
                index: index,
                onLoad: (index) => loads[index] = (loads[index] ?? 0) + 1,
              ),
            ),
          ),
        ),
      );
    }

    await show(0);
    await show(4);
    await show(0);
    expect(loads, {0: 2, 4: 1});
  });

  testWidgets('unrelated shell updates do not rebuild hidden module widgets', (
    tester,
  ) async {
    final builds = <int, int>{};
    Future<void> show(int selected) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainedModuleStack(
              index: selected,
              itemCount: 8,
              itemBuilder: (_, index) {
                builds[index] = (builds[index] ?? 0) + 1;
                return Text('module $index');
              },
            ),
          ),
        ),
      );
    }

    await show(3);
    for (var update = 0; update < 10; update++) {
      await show(4);
    }
    expect(builds, {3: 1, 4: 10});
    expect(find.text('module 3'), findsNothing);
    expect(find.text('module 4'), findsOneWidget);
    await show(3);
    expect(builds[3], 2);
  });

  testWidgets('hidden retained pages disable focus and animation tickers', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final tickers = <int, bool>{};
    Future<void> show(int selected) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainedModuleStack(
              index: selected,
              itemCount: 8,
              itemBuilder: (_, index) => Builder(
                builder: (context) {
                  tickers[index] = TickerMode.valuesOf(context).enabled;
                  return index == 3
                      ? Focus(
                          focusNode: focus,
                          autofocus: true,
                          child: const Text('estimate'),
                        )
                      : const Text('invoice');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(3);
    expect(focus.hasFocus, isTrue);
    expect(tickers[3], isTrue);
    await show(4);
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
    expect(tickers[3], isFalse);
    expect(tickers[4], isTrue);
    await show(3);
    expect(focus.canRequestFocus, isTrue);
    expect(tickers[3], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
