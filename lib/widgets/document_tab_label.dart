import 'package:flutter/material.dart';

/// An equal-width document tab with an edge-anchored or centered label.
///
/// Each TabBar slot owns one quarter (invoice) or half (estimate) of the
/// available width. Text shrinks only if translation or accessibility scale
/// would otherwise overflow, and is never cropped at the last tab.
class DocumentTabLabel extends StatelessWidget {
  const DocumentTabLabel({
    super.key,
    required this.label,
    this.alignment = Alignment.center,
  });

  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Tab(
    child: Padding(
      padding: EdgeInsets.only(
        left: alignment == Alignment.centerLeft ? 12 : 2,
        right: alignment == Alignment.centerRight ? 12 : 2,
      ),
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(label, maxLines: 1, softWrap: false),
        ),
      ),
    ),
  );
}
