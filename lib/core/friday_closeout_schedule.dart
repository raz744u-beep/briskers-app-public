import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FridayCloseoutSchedule {
  const FridayCloseoutSchedule({
    this.enabled = false,
    this.startMinute = 15 * 60,
  }) : assert(startMinute >= 0 && startMinute < 24 * 60);

  final bool enabled;
  final int startMinute;

  static final _shopZone = _loadShopZone();

  static tz.Location _loadShopZone() {
    tzdata.initializeTimeZones();
    return tz.getLocation('America/Chicago');
  }

  /// Active Friday's local calendar date, and the next visibility change.
  ({String? friday, DateTime? nextChange}) window(DateTime now) {
    if (!enabled) return (friday: null, nextChange: null);
    final local = tz.TZDateTime.from(now, _shopZone);
    final daysToFriday = (DateTime.friday - local.weekday + 7) % 7;
    tz.TZDateTime start(int offset) => tz.TZDateTime(
      _shopZone,
      local.year,
      local.month,
      local.day + offset,
      startMinute ~/ 60,
      startMinute % 60,
    );
    final fridayStart = start(daysToFriday);
    if (now.isBefore(fridayStart))
      return (friday: null, nextChange: fridayStart);
    final saturday = tz.TZDateTime(
      _shopZone,
      local.year,
      local.month,
      local.day + 1,
    );
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    return (friday: date, nextChange: saturday);
  }
}
