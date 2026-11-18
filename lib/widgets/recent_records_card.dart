import 'package:flutter/material.dart';
import '../core/briskers_colors.dart';
import '../services/local_recent_records.dart';
import 'briskers_section_card.dart';

/// Presentation only: the account-scoped local store owns ordering and clearing.
class RecentRecordsCard extends StatefulWidget {
  const RecentRecordsCard({super.key,required this.records,required this.onOpen,
    required this.onClear});
  final List<RecentRecord> records;
  final ValueChanged<RecentRecord> onOpen;
  final VoidCallback onClear;

  @override
  State<RecentRecordsCard> createState() => _RecentRecordsCardState();
}

class _RecentRecordsCardState extends State<RecentRecordsCard> {
  bool _expanded = false;

  static (String,IconData,Color) _style(RecentRecordKind kind) => switch(kind) {
    RecentRecordKind.invoice => ('Invoice',Icons.receipt_long_outlined,BriskersColors.invoices),
    RecentRecordKind.estimate => ('Estimate',Icons.description_outlined,BriskersColors.estimates),
    RecentRecordKind.customer => ('Customer',Icons.person_outline,BriskersColors.customers),
    RecentRecordKind.job => ('Job',Icons.build_outlined,BriskersColors.jobs),
  };

  static (String,String?) _caption(RecentRecord record,String type) {
    final label = record.label.trim();
    if (label.isEmpty) return (type,null);
    if (record.kind == RecentRecordKind.customer) return (label,type);
    final separator = label.indexOf(' · ');
    final first = (separator < 0 ? label : label.substring(0,separator)).trim();
    final customer = separator < 0 ? null : label.substring(separator+3).trim();
    final numbered = switch(record.kind) {
      RecentRecordKind.invoice => RegExp(r'^#\d+$').hasMatch(first),
      RecentRecordKind.estimate => RegExp(r'^#?E-\d+$').hasMatch(first),
      RecentRecordKind.job => RegExp(r'^J-\d+$').hasMatch(first),
      RecentRecordKind.customer => false,
    };
    if (!numbered) {
      // Old shortcuts can retain an internal draft identifier after repair.
      // Keep opening the exact record, without displaying that identifier.
      final old = first.toLowerCase();
      if (old.startsWith('#e-est-') || old.startsWith('#local-') ||
          old.startsWith('local-') || old.contains('pending sync')) {
        return (type,customer == null || customer.isEmpty ? null : customer);
      }
      return (label,type);
    }
    final number = record.kind == RecentRecordKind.estimate && first.startsWith('#')
      ? first.substring(1) : first;
    return ('$type $number',customer == null || customer.isEmpty ? null : customer);
  }

  Widget _row(RecentRecord record) {
    final (type,icon,color) = _style(record.kind);
    final (title,subtitle) = _caption(record,type);
    return InkWell(
      key: ValueKey('recent-${record.kind.name}-${record.id}'),
      onTap: () => widget.onOpen(record),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 76),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14,vertical: 12),
          child: Row(children: [
            Container(width: 4,height: 44,decoration: BoxDecoration(
              color: color,borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 12),
            Container(width: 42,height: 42,decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),borderRadius: BorderRadius.circular(11)),
              child: Icon(icon,color: color,size: 26)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
              Text(title,maxLines: 2,overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BriskersColors.text,fontSize: 16,fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle,maxLines: 2,overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BriskersColors.secondaryText,fontSize: 14)),
              ],
            ])),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,color: BriskersColors.secondaryText,size: 23),
          ]))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.records.take(10).toList();
    return BriskersSectionCard(
      margin: const EdgeInsets.fromLTRB(12,0,12,12),
      title: 'Recently Viewed',icon: Icons.history,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      action: shown.isEmpty ? null : TextButton(
        onPressed: widget.onClear,
        style: TextButton.styleFrom(foregroundColor: Colors.white,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 4),
          textStyle: const TextStyle(fontSize: 12,fontWeight: FontWeight.w600)),
        child: const Text('Clear History', maxLines: 1)),
      child: shown.isEmpty
        ? const Padding(padding: EdgeInsets.all(20),child: Text('No records viewed yet.',
            style: TextStyle(color: BriskersColors.secondaryText)))
        : Column(children: [for (var index=0;index<shown.length;index++) ...[
            if (index>0) const Divider(height: 1,thickness: 1,color: BriskersColors.divider),
            _row(shown[index]),
          ]]),
    );
  }
}
