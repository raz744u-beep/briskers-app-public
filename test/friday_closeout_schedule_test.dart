import 'package:briskers_app/core/friday_closeout_schedule.dart';
import 'package:briskers_app/services/friday_closeout_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the default Friday window begins at 3 PM and ends at midnight Gretna time',
    () {
      const schedule = FridayCloseoutSchedule(enabled: true);
      final start = DateTime.utc(2026, 12, 4, 21);
      final end = DateTime.utc(2026, 12, 5, 6);
      final before = schedule.window(
        start.subtract(const Duration(seconds: 1)),
      );
      expect(before.friday, isNull);
      expect(
        before.nextChange?.millisecondsSinceEpoch,
        start.millisecondsSinceEpoch,
      );
      final active = schedule.window(start);
      expect(active.friday, '2026-12-04');
      expect(
        active.nextChange?.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      );
      expect(
        schedule.window(end.subtract(const Duration(seconds: 1))).friday,
        '2026-12-04',
      );
      final next = schedule.window(end);
      expect(next.friday, isNull);
      expect(
        next.nextChange?.millisecondsSinceEpoch,
        DateTime.utc(2026, 12, 11, 21).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'supports midnight and noon, using shop daylight time where applicable',
    () {
      const allDay = FridayCloseoutSchedule(enabled: true, startMinute: 0);
      final midnight = DateTime.utc(2026, 7, 3, 5);
      expect(
        allDay.window(midnight.subtract(const Duration(seconds: 1))).friday,
        isNull,
      );
      expect(allDay.window(midnight).friday, '2026-07-03');

      const noon = FridayCloseoutSchedule(enabled: true, startMinute: 12 * 60);
      final starts = DateTime.utc(2026, 7, 3, 17);
      expect(
        noon.window(starts.subtract(const Duration(seconds: 1))).friday,
        isNull,
      );
      expect(noon.window(starts).friday, '2026-07-03');
      expect(noon.window(DateTime.utc(2026, 7, 4, 5)).friday, isNull);
      expect(const FridayCloseoutSchedule().window(starts), (
        friday: null,
        nextChange: null,
      ));
    },
  );

  test('the opt-in and Friday view selection are local to each shop', () async {
    SharedPreferences.setMockInitialValues({});
    const owner = FridayCloseoutPreferences('shop');
    const other = FridayCloseoutPreferences('other');
    expect((await owner.load()).enabled, isFalse);
    await owner.save(
      const FridayCloseoutSchedule(enabled: true, startMinute: 0),
    );
    await owner.showRegularFor('2026-12-04');
    expect((await owner.load()).enabled, isTrue);
    expect((await owner.load()).startMinute, 0);
    expect(await owner.regularFriday(), '2026-12-04');
    expect((await other.load()).enabled, isFalse);
    expect(await other.regularFriday(), isNull);

    await owner.save(const FridayCloseoutSchedule(startMinute: 720));
    final disabled = await owner.load();
    expect(disabled.enabled, isFalse);
    expect(disabled.startMinute, 720);
    await owner.showRegularFor(null);
    expect(await owner.regularFriday(), isNull);
  });
}
