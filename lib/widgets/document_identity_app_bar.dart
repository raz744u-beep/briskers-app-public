import 'package:flutter/material.dart';

/// Compact invoice/estimate header with number, status and actions in one row.
class DocumentIdentityAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const DocumentIdentityAppBar({
    super.key,
    required this.label,
    required this.number,
    required this.accent,
    required this.status,
    required this.statusRowHeight,
    required this.actions,
    this.onLongPress,
  });

  final String label;
  final String number;
  final Color accent;
  final Widget status;
  // Retained for backwards compatibility with existing call sites.
  final double statusRowHeight;
  final List<Widget> actions;
  final VoidCallback? onLongPress;

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight,
  );

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: accent,
    foregroundColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.white),
    actionsIconTheme: const IconThemeData(color: Colors.white),
    elevation: 1,
    titleSpacing: 0,
    title: Row(
      children: [
        IntrinsicWidth(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress,
            child: Semantics(
              label: number.isEmpty ? label : '$label #$number',
              child: Text(
                number.isEmpty ? label : '#$number',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: status,
            ),
          ),
        ),
        if (actions.isNotEmpty)
          IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
      ],
    ),
  );
}
