import 'package:flutter/material.dart';
import '../core/briskers_colors.dart';

/// Shared Briskers section surface with a responsive official blue header.
class BriskersSectionCard extends StatelessWidget {
  const BriskersSectionCard({super.key,required this.title,required this.icon,
    required this.child,this.action,this.margin=EdgeInsets.zero});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
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
    child: Column(mainAxisSize: MainAxisSize.min,crossAxisAlignment: CrossAxisAlignment.stretch,children: [
      Container(decoration: const BoxDecoration(gradient: BriskersColors.blueHeader),
        padding: const EdgeInsets.symmetric(horizontal: 16,vertical: 14),
        child: LayoutBuilder(builder: (context, constraints) {
          final heading = Row(children: [
            Icon(icon,color: Colors.white,size: 25),
            const SizedBox(width: 10),
            Expanded(child: Text(title,style: const TextStyle(
              color: Colors.white,fontSize: 18,fontWeight: FontWeight.w700))),
          ]);
          final largeText = MediaQuery.textScalerOf(context).scale(18) > 22.5;
          if (action == null) return heading;
          if (constraints.maxWidth < 330 || largeText) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
              heading,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight,child: action),
            ]);
          }
          return Row(children: [Expanded(child: heading),
            const SizedBox(width: 12),action!]);
        })),
      child,
    ]),
  );
}
