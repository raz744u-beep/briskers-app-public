import 'package:flutter/material.dart';

Color invoiceStatusColorFromHex(
  String? value, {
  Color fallback = const Color(0xFF2E7D32),
}) {
  final raw = (value ?? '').replaceAll('#', '').trim();
  if (raw.length != 6) return fallback;
  final parsed = int.tryParse(raw, radix: 16);
  if (parsed == null) return fallback;
  return Color(0xFF000000 | parsed);
}

String _normalizedInvoiceStatus(String? value) =>
    (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

Color invoiceStatusDefaultColor(String? statusOrCode) {
  switch (_normalizedInvoiceStatus(statusOrCode)) {
    case 'paid':
      return const Color(0xFF169B62);
    case 'partial':
      return const Color(0xFF1976D2);
    case 'pending_close':
    case 'pending':
      return const Color(0xFFE58A00);
    case 'closed':
      return const Color(0xFF00897B);
    case 'void':
      return const Color(0xFFC62828);
    case 'draft':
      return const Color(0xFF667085);
    case 'open':
      return const Color(0xFF757575);
    default:
      return const Color(0xFF546E7A);
  }
}

IconData invoiceStatusDefaultIcon(String? statusOrCode) {
  switch (_normalizedInvoiceStatus(statusOrCode)) {
    case 'paid':
      return Icons.check_circle;
    case 'partial':
      return Icons.timelapse;
    case 'pending_close':
    case 'pending':
      return Icons.schedule_outlined;
    case 'closed':
      return Icons.check_circle_outline;
    case 'void':
      return Icons.cancel_outlined;
    case 'open':
      return Icons.receipt_long_outlined;
    default:
      return Icons.label_outline;
  }
}

IconData invoiceStatusIcon(String? key) {
  switch ((key ?? '').trim()) {
    case 'receipt':
      return Icons.receipt_long_outlined;
    case 'timelapse':
      return Icons.timelapse;
    case 'schedule':
      return Icons.schedule_outlined;
    case 'paid':
      return Icons.check_circle;
    case 'cancel':
      return Icons.cancel_outlined;
    case 'hourglass':
      return Icons.hourglass_bottom_outlined;
    case 'warning':
      return Icons.warning_amber_outlined;
    case 'payments':
      return Icons.payments_outlined;
    case 'check':
      return Icons.check_circle_outline;
    default:
      return Icons.label_outline;
  }
}

const invoiceStatusIconChoices = <Map<String, Object>>[
  {'key': 'receipt', 'label': 'Invoice', 'icon': Icons.receipt_long_outlined},
  {'key': 'timelapse', 'label': 'Partial', 'icon': Icons.timelapse},
  {'key': 'schedule', 'label': 'Waiting', 'icon': Icons.schedule_outlined},
  {'key': 'paid', 'label': 'Paid', 'icon': Icons.check_circle},
  {'key': 'cancel', 'label': 'Void', 'icon': Icons.cancel_outlined},
  {'key': 'hourglass', 'label': 'Pending', 'icon': Icons.hourglass_bottom_outlined},
  {'key': 'warning', 'label': 'Attention', 'icon': Icons.warning_amber_outlined},
  {'key': 'payments', 'label': 'Payment', 'icon': Icons.payments_outlined},
  {'key': 'check', 'label': 'Check', 'icon': Icons.check_circle_outline},
];

const invoiceStatusColorChoices = <String>[
  '#2E7D32',
  '#169B62',
  '#1976D2',
  '#00897B',
  '#7E57C2',
  '#E58A00',
  '#EF6C00',
  '#C62828',
  '#D32F2F',
  '#546E7A',
  '#757575',
  '#C2185B',
  '#3949AB',
];
