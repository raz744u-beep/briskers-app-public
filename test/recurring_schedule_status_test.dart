import 'package:briskers_app/core/recurring_schedule_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached due and missed dates require verification before posting', () {
    String status(String date, {bool cached = true}) => recurringScheduleStatus(
          {'next_date': date, 'is_repeating': true},
          today: DateTime(2026, 11, 4, 10, 27),
          cached: cached,
        );

    expect(status('2026-11-04'), startsWith('Due today'));
    expect(status('2026-11-04'), contains('may already be posted'));
    expect(status('2026-10-28'), startsWith('Overdue'));
    expect(status('2026-11-11'), 'Last saved next 2026-11-11');
    expect(status('2026-11-04', cached: false), contains('not confirmed'));
    expect(status('2026-02-30'), 'Schedule date unavailable');
  });

  test('a paused schedule never shows as due', () {
    expect(
      recurringScheduleStatus(
        {'next_date': '2026-11-04', 'paused_reason': 'Inactive account'},
        today: DateTime(2026, 11, 4),
        cached: true,
      ),
      'Paused: Inactive account',
    );
  });
}
