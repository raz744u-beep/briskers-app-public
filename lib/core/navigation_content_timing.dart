import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

/// Content latency measured from a module tap to the frame with usable data.
/// Timeline events contain only the module/source label, never customer data.
/// These measure UI first content, not synchronization completion.
class NavigationContentTiming {
  NavigationContentTiming._();

  static String? _module;
  static Stopwatch? _watch;
  static Stopwatch? _scheduled;

  @visibleForTesting
  static void Function(String module, String source, Duration elapsed)?
  onSample;

  static void start(String module) {
    _module = module;
    _watch = Stopwatch()..start();
    _scheduled = null;
  }

  static void cancel() {
    _watch?.stop();
    _module = null;
    _watch = null;
    _scheduled = null;
  }

  static void contentVisible(
    String module, {
    BuildContext? context,
    required String source,
  }) {
    bool visible() =>
        context == null ||
        (context.mounted &&
            TickerMode.valuesOf(context).enabled &&
            ModalRoute.of(context)?.isCurrent != false);
    if (!visible()) return;
    final watch = _watch;
    if (_module != module || watch == null || _scheduled == watch) return;
    _scheduled = watch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_module != module || _watch != watch || !visible()) {
        if (_scheduled == watch) _scheduled = null;
        return;
      }
      watch.stop();
      final elapsed = watch.elapsed;
      _watch = null;
      _scheduled = null;
      developer.Timeline.instantSync(
        'Briskers.navigation.first_content',
        arguments: {
          'module': module,
          'source': source,
          'elapsed_us': elapsed.inMicroseconds,
        },
      );
      onSample?.call(module, source, elapsed);
    });
  }
}
