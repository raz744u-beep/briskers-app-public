import '../../widgets/task_schedule_indicator.dart';
import 'package:flutter/material.dart';
import '../../core/work_status_colors.dart';

/// One gesture target keeps long press distinct from opening task details.
class CompactTaskCard extends StatefulWidget {
  const CompactTaskCard({
    super.key,
    this.task,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.details,
    required this.onLongPress,
  });
  final String title, subtitle, status;
  final Map<String,dynamic>? task;
  final Widget details;
  final VoidCallback onLongPress;
  @override
  State<CompactTaskCard> createState() => _CompactTaskCardState();
}

class _CompactTaskCardState extends State<CompactTaskCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.status == 'Done'
        ? WorkStatusColors.done
        : widget.status == 'In Progress'
        ? WorkStatusColors.progress
        : WorkStatusColors.open;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              onLongPress: widget.onLongPress,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF52616A),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if(widget.task!=null) TaskScheduleIndicator({...widget.task!,'status':widget.status}),
                      const SizedBox(width: 8),
                        Text(
                          widget.status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Icon(
                          _open ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: color,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 12),
                    Text(widget.title),
                    widget.details,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
