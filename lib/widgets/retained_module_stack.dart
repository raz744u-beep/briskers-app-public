import 'package:flutter/material.dart';

/// Mount a module on its first visit and retain expensive list modules,
/// including Customers and Expenses. Reopening Customers should not
/// remount its list and repeat a full bootstrap before the first frame.
/// Expenses holds verified server receipt identities in its
/// state; disposing it on a tab switch made green clouds falsely turn gray.
/// Hidden modules keep their filters, controllers and scroll position, without
/// running tickers or receiving focus. Unvisited modules do no work.
class RetainedModuleStack extends StatefulWidget {
  const RetainedModuleStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
    // Jobs (index 2) must also survive dock switches. Re-mounting it discarded
    // already visible rows and brought back the full-page startup spinner.
    this.retainedIndices = const {1, 2, 3, 4, 5, 6},
  });

  final int index;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Set<int> retainedIndices;

  @override
  State<RetainedModuleStack> createState() => _RetainedModuleStackState();
}

class _RetainedModuleStackState extends State<RetainedModuleStack> {
  final Map<int, Widget> _pages = {};

  @override
  Widget build(BuildContext context) {
    _pages.removeWhere(
      (index, _) =>
          index >= widget.itemCount ||
          (index != widget.index && !widget.retainedIndices.contains(index)),
    );
    // Only the visible page needs new Shell callbacks/navigation tokens.
    // Reusing the identical hidden Widget avoids rebuilding/sorting its list
    // on unrelated Shell badge updates. Its own data listeners still work.
    _pages[widget.index] = widget.itemBuilder(context, widget.index);
    return Stack(
      fit: StackFit.expand,
      children: List.generate(widget.itemCount, (index) {
        final active = index == widget.index;
        return Offstage(
          key: ValueKey(index),
          offstage: !active,
          child: TickerMode(
            enabled: active,
            child: ExcludeFocus(
              excluding: !active,
              child: _pages[index] ?? const SizedBox.shrink(),
            ),
          ),
        );
      }),
    );
  }
}
