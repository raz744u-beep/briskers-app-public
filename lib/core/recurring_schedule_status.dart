/// A cached schedule cannot establish whether the server posted an occurrence.
String recurringScheduleStatus(
  Map<String, dynamic> rule, {
  required DateTime today,
  required bool cached,
}) {
  final paused = rule['paused_reason']?.toString().trim() ?? '';
  if (paused.isNotEmpty) return 'Paused: $paused';
  if (rule['is_repeating'] == false) return 'Stopped';

  final raw = rule['next_date']?.toString() ?? '';
  final due = DateTime.tryParse(raw);
  if (due == null || due.toIso8601String().substring(0, 10) != raw) {
    return 'Schedule date unavailable';
  }
  final day = DateTime(today.year, today.month, today.day);
  if (due.isAfter(day)) return '${cached ? 'Last saved next' : 'Next'} $raw';

  final status = due.isBefore(day) ? 'Overdue' : 'Due today';
  return cached
      ? '$status ($raw) · pending verification · may already be posted'
      : '$status ($raw) · posting not confirmed by the schedule';
}
