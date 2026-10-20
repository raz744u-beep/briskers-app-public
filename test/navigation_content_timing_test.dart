import 'package:briskers_app/core/navigation_content_timing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    NavigationContentTiming.onSample = null;
    NavigationContentTiming.cancel();
  });

  testWidgets(
    'records first content after the frame, once for the active tap',
    (tester) async {
      final samples = <String>[];
      NavigationContentTiming.onSample = (module, source, elapsed) {
        expect(elapsed, greaterThanOrEqualTo(Duration.zero));
        samples.add('$module:$source');
      };
      NavigationContentTiming.start('invoices');
      NavigationContentTiming.contentVisible('estimates', source: 'retained');
      NavigationContentTiming.contentVisible('invoices', source: 'retained');
      NavigationContentTiming.contentVisible('invoices', source: 'retained');
      expect(samples, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(samples, ['invoices:retained']);
      NavigationContentTiming.contentVisible('invoices', source: 'refreshed');
      await tester.pump();
      expect(samples, hasLength(1));
    },
  );

  testWidgets('a newer navigation supersedes an unpainted measurement', (
    tester,
  ) async {
    final samples = <String>[];
    NavigationContentTiming.onSample = (module, source, elapsed) =>
        samples.add(module);
    NavigationContentTiming.start('invoices');
    NavigationContentTiming.contentVisible('invoices', source: 'local');
    NavigationContentTiming.start('appointments');
    NavigationContentTiming.contentVisible('appointments', source: 'local');
    await tester.pumpWidget(const SizedBox());
    expect(samples, ['appointments']);
  });

  testWidgets('leaving for another module cancels hidden-page measurements', (
    tester,
  ) async {
    final samples = <String>[];
    NavigationContentTiming.onSample = (module, source, elapsed) =>
        samples.add(module);
    NavigationContentTiming.start('invoices');
    NavigationContentTiming.contentVisible('invoices', source: 'local');
    NavigationContentTiming.cancel();
    await tester.pumpWidget(const SizedBox());
    expect(samples, isEmpty);
  });

  testWidgets(
    'offstage retained pages cannot satisfy a visible-content sample',
    (tester) async {
      final samples = <String>[];
      NavigationContentTiming.onSample = (module, source, elapsed) =>
          samples.add(module);
      NavigationContentTiming.start('invoices');
      await tester.pumpWidget(
        TickerMode(
          enabled: false,
          child: Builder(
            builder: (context) {
              NavigationContentTiming.contentVisible(
                'invoices',
                context: context,
                source: 'hidden',
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(samples, isEmpty);
      await tester.pumpWidget(
        TickerMode(
          enabled: true,
          child: Builder(
            builder: (context) {
              NavigationContentTiming.contentVisible(
                'invoices',
                context: context,
                source: 'visible',
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(samples, ['invoices']);
    },
  );
}
