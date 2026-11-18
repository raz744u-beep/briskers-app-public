import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';

/// Shared Briskers section surface with a compact official blue header.
class BriskersSectionCard extends StatelessWidget {
  const BriskersSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
    this.onToggle,
    this.expanded = true,
    this.margin = EdgeInsets.zero,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
  final VoidCallback? onToggle;
  final bool expanded;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Card(
    margin: margin,
    color: BriskersColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 1,
    shadowColor: BriskersColors.secondaryText.withValues(alpha: 0.18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: onToggle == null ? null : expanded,
          child: InkWell(
            onTap: onToggle,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: Ink(
              decoration: const BoxDecoration(
                gradient: BriskersColors.blueHeader,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth / 2,
                            ),
                            child: action!,
                          ),
                        ],
                        if (onToggle != null)
                          IconButton(
                            onPressed: onToggle,
                            tooltip:
                                '${expanded ? 'Collapse' : 'Expand'} $title',
                            color: Colors.white,
                            icon: Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (expanded) child,
      ],
    ),
  );
}
