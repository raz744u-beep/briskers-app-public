import 'package:flutter/material.dart';

/// Document identity keeps the full toolbar width. Status and editing actions
/// use their own second row, so neither can shrink the invoice number.
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
  final double statusRowHeight;
  final List<Widget> actions;
  final VoidCallback? onLongPress;
  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + statusRowHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: accent,
    foregroundColor: Colors.white,
    elevation: 1,
    titleSpacing: 0,
    title: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Semantics(
        label: number.isEmpty ? label : '$label #$number',
        child: Text(
          number.isEmpty ? label : '#$number',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
      ),
    ),
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(statusRowHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: status),
            ),
            ...actions,
          ],
        ),
      ),
    ),
  );
}
