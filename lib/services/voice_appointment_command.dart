/// Small, deterministic interpreter for a *draft* voice appointment.
/// It intentionally rejects commands without a reliable date and time.
/// No appointment is saved by this parser.
class VoiceAppointmentCommand {
  const VoiceAppointmentCommand({
    required this.startsAt,
    required this.service,
  });

  final DateTime startsAt;
  final String service;

  static const _weekdays = <String, int>{
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  static const _numbers = <String, int>{
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12,
  };

  static const _months = <String, int>{
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12,
  };

  static String normalized(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s:]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static VoiceAppointmentCommand? parse(
    String recognizedWords, {
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final text = normalized(recognizedWords);
    final date = _date(text, anchor);
    final time = _time(text);
    if (date == null || time == null) return null;
    final starts = DateTime(
      date.year, date.month, date.day, time.$1, time.$2,
    );
    if (!starts.isAfter(anchor) ||
        starts.isAfter(anchor.add(const Duration(days: 550)))) {
      return null;
    }
    return VoiceAppointmentCommand(
      startsAt: starts,
      service: _service(text),
    );
  }

  static DateTime? _date(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (RegExp(r'\btomorrow\b').hasMatch(text)) {
      return today.add(const Duration(days: 1));
    }
    if (RegExp(r'\btoday\b').hasMatch(text)) return today;

    // Explicit month/date takes precedence over weekday mentions.
    for (final month in _months.entries) {
      final match = RegExp(
        r'\b' + month.key + r'\s+([0-9]{1,2})(?:st|nd|rd|th)?\b',
      ).firstMatch(text);
      if (match == null) continue;
      final day = int.tryParse(match.group(1) ?? '');
      if (day == null) return null;
      final year = RegExp(r'\b20[0-9]{2}\b').firstMatch(text);
      var targetYear = year == null
          ? now.year
          : int.parse(year.group(0)!);
      var proposed = DateTime(targetYear, month.value, day);
      if (proposed.month != month.value || proposed.day != day) return null;
      if (year == null && proposed.isBefore(today)) {
        targetYear += 1;
        proposed = DateTime(targetYear, month.value, day);
      }
      return proposed;
    }

    for (final weekday in _weekdays.entries) {
      if (!RegExp(r'\b' + weekday.key + r'\b').hasMatch(text)) continue;
      var delta = (weekday.value - now.weekday + 7) % 7;
      if (delta == 0) delta = 7;
      // "next Wednesday" is interpreted as the next *upcoming* Wednesday.
      return today.add(Duration(days: delta));
    }
    return null;
  }

  static (int, int)? _time(String text) {
    // Examples: "at 10", "at 10 30", "10 o clock", "at ten".
    var match = RegExp(
      r'\bat\s+(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)'
      r'(?::(\d{2})|\s+(\d{2}))?\s*(am|pm|a m|p m|o clock)?\b',
    ).firstMatch(text);
    match ??= RegExp(
      r'\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)'
      r'(?::(\d{2}))?\s*(am|pm|a m|p m|o clock)\b',
    ).firstMatch(text);
    if (match == null) return null;
    final hourText = match.group(1)!;
    var hour = int.tryParse(hourText) ?? _numbers[hourText];
    final minutes = int.tryParse(match.group(2) ?? match.group(3) ?? '0');
    if (hour == null || minutes == null || minutes > 59 || hour > 23) {
      return null;
    }
    final suffix = (match.group(4) ?? '').replaceAll(' ', '');
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    if ((suffix == 'am' || suffix == 'pm') && hour > 23) return null;
    // Shop-hours default: unqualified 1-6 means PM; 7-11 means AM.
    // The interpreted time is always spoken back for confirmation.
    if (suffix != 'am' && suffix != 'pm' && hour >= 1 && hour <= 6) {
      hour += 12;
    }
    return (hour, minutes);
  }

  static String _service(String text) {
    final reasons = RegExp(
      r'\bfor\s+(?:an?\s+)?(.+?)(?=\s+(?:on|next|this|tomorrow|today|at)\b|$)',
    ).allMatches(text).toList();
    if (reasons.isEmpty) return 'Service appointment';
    final last = reasons.last.group(1)?.trim() ?? '';
    if (last.isEmpty || RegExp(r'^\d').hasMatch(last)) {
      return 'Service appointment';
    }
    if (last.split(' ').length > 8) return 'Service appointment';
    return last[0].toUpperCase() + last.substring(1);
  }
}
