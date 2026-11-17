import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';

class BriskersDialog extends StatelessWidget {
  const BriskersDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;

  static ButtonStyle get cancelStyle =>
      OutlinedButton.styleFrom(foregroundColor: const Color(0xFF475569));

  static ButtonStyle confirmStyle({bool destructive = false}) =>
      FilledButton.styleFrom(
        backgroundColor: destructive
            ? BriskersColors.destructive
            : BriskersColors.confirm,
        foregroundColor: Colors.white,
      );

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: BriskersColors.blueHeader,
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Color(0xFF202936)),
                child: content,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ),
        ],
      ),
    ),
  );
}
