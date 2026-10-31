import 'package:flutter/material.dart';

import 'stale_keyboard_inset_guard.dart';

/// A single horizontal dock, reserving its own height above system navigation.
/// It never writes app state; the shell owns selection and route changes.
class BriskersModuleDock extends StatefulWidget {
  const BriskersModuleDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.onLongPressed,
    required this.destinations,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  /// Optional test-lab shortcut. Existing Briskers uses ordinary taps only.
  final void Function(int index, Offset globalPosition)? onLongPressed;
  final List<BriskersDockDestination> destinations;

  @override
  State<BriskersModuleDock> createState() => _BriskersModuleDockState();
}

class BriskersDockDestination {
  const BriskersDockDestination({
    required this.label,
    required this.icon,
    required this.color,
    this.count = 0,
  });
  final String label;
  final IconData icon;
  final Color color;
  final int count;
}

class _BriskersModuleDockState extends State<BriskersModuleDock> {
  final ScrollController _controller = ScrollController();
  bool _left = false;
  bool _right = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    FocusManager.instance.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(covariant BriskersModuleDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _onFocusChanged() {
    // A stale Android IME inset must not leave the entire module dock hidden
    // when keyboard focus has already returned to the route.
    if (mounted) setState(() {});
  }

  bool get _editingText => StaleKeyboardInsetGuard.editableTextHasFocus;

  void _syncArrows() {
    if (!mounted || !_controller.hasClients) return;
    final left = _controller.offset > 2;
    final right = _controller.offset < _controller.position.maxScrollExtent - 2;
    if (left != _left || right != _right) {
      setState(() { _left = left; _right = right; });
    }
  }

  void _revealSelected() {
    if (!mounted || !_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final target = (widget.selectedIndex * 83.0 - (viewport - 83) / 2)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(target,
      duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    _syncArrows();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _controller.removeListener(_syncArrows);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Do not interpret a nonzero inset ALONE as a visible keyboard.
    // Samsung may retain its last reported IME height after the text field
    // loses focus; that used to hide all app navigation until a restart.
    if (MediaQuery.viewInsetsOf(context).bottom > 0 && _editingText) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        height: 66,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x25000000), blurRadius: 10, offset: Offset(0, -2)),
          ],
        ),
        child: Row(children: [
          if (_left) IconButton(
            tooltip: 'Previous sections', icon: const Icon(Icons.chevron_left),
            constraints: const BoxConstraints(minWidth: 25, minHeight: 42),
            padding: EdgeInsets.zero,
            onPressed: () => _controller.animateTo(
              (_controller.offset - 190).clamp(0, _controller.position.maxScrollExtent),
              duration: const Duration(milliseconds: 170), curve: Curves.easeOut),
          ),
          Expanded(
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              itemCount: widget.destinations.length,
              itemBuilder: (context, index) {
                final item = widget.destinations[index];
                final selected = index == widget.selectedIndex;
                return SizedBox(width: 83, child: GestureDetector(
                  onLongPressStart: widget.onLongPressed == null
                    ? null : (details) => widget.onLongPressed!(
                        index, details.globalPosition),
                  child: InkWell(
                  key: ValueKey('dock-${item.label}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onSelected(index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected ? item.color.withValues(alpha: .13) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Badge(
                        isLabelVisible: item.count > 0,
                        backgroundColor: const Color(0xFF465468),
                        label: Text(item.count > 99 ? '99+' : '${item.count}'),
                        child: Icon(item.icon, color: item.color, size: 25),
                      ),
                      const SizedBox(height: 2),
                      Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          color: item.color)),
                    ]),
                  ),
                  ),
                ));
              },
            ),
          ),
          if (_right) IconButton(
            tooltip: 'More sections', icon: const Icon(Icons.chevron_right),
            constraints: const BoxConstraints(minWidth: 25, minHeight: 42),
            padding: EdgeInsets.zero,
            onPressed: () => _controller.animateTo(
              (_controller.offset + 190).clamp(0, _controller.position.maxScrollExtent),
              duration: const Duration(milliseconds: 170), curve: Curves.easeOut),
          ),
        ]),
      ),
    );
  }
}
