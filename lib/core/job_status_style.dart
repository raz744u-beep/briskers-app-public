import 'package:flutter/material.dart';

Color colorFromHex(String? value, {Color fallback = const Color(0xFF546E7A)}) {
  final raw = (value ?? '').replaceAll('#', '').trim();
  if (raw.length != 6) return fallback;
  final parsed = int.tryParse(raw, radix: 16);
  if (parsed == null) return fallback;
  return Color(0xFF000000 | parsed);
}

IconData jobStatusIcon(String? key) {
  switch ((key ?? '').trim()) {
    case 'work_outline':
      return Icons.work_outline;
    case 'build_circle':
      return Icons.build_circle_outlined;
    case 'approval':
      return Icons.approval_outlined;
    case 'local_shipping':
      return Icons.local_shipping_outlined;
    case 'troubleshoot':
      return Icons.troubleshoot_outlined;
    case 'task_alt':
      return Icons.task_alt;
    case 'cancel':
      return Icons.cancel_outlined;
    case 'schedule':
      return Icons.schedule_outlined;
    case 'hourglass':
      return Icons.hourglass_bottom_outlined;
    case 'pause':
      return Icons.pause_circle_outline;
    case 'check':
      return Icons.check_circle_outline;
    case 'warning':
      return Icons.warning_amber_outlined;
    default:
      return Icons.label_outline;
  }
}

const jobStatusIconChoices = <Map<String, Object>>[
  {'key': 'work_outline', 'label': 'Open', 'icon': Icons.work_outline},
  {'key': 'build_circle', 'label': 'Work', 'icon': Icons.build_circle_outlined},
  {'key': 'approval', 'label': 'Approval', 'icon': Icons.approval_outlined},
  {'key': 'local_shipping', 'label': 'Parts', 'icon': Icons.local_shipping_outlined},
  {'key': 'troubleshoot', 'label': 'Recheck', 'icon': Icons.troubleshoot_outlined},
  {'key': 'task_alt', 'label': 'Complete', 'icon': Icons.task_alt},
  {'key': 'cancel', 'label': 'Cancel', 'icon': Icons.cancel_outlined},
  {'key': 'schedule', 'label': 'Schedule', 'icon': Icons.schedule_outlined},
  {'key': 'hourglass', 'label': 'Waiting', 'icon': Icons.hourglass_bottom_outlined},
  {'key': 'pause', 'label': 'Paused', 'icon': Icons.pause_circle_outline},
  {'key': 'check', 'label': 'Check', 'icon': Icons.check_circle_outline},
  {'key': 'warning', 'label': 'Attention', 'icon': Icons.warning_amber_outlined},
];

const jobStatusColorChoices = <String>[
  '#546E7A',
  '#1976D2',
  '#00897B',
  '#7E57C2',
  '#EF6C00',
  '#D32F2F',
  '#2E7D32',
  '#757575',
  '#C2185B',
  '#3949AB',
];
