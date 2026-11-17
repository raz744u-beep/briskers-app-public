import 'package:briskers_app/screens/settings/navigation_settings_screen.dart';
import 'package:briskers_app/services/local_recent_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'history keeps ten latest records and clears only the selected account',
    () async {
      const history = LocalRecentRecords('shop', 'owner');
      const other = LocalRecentRecords('shop', 'another');
      const customer = (
        kind: RecentRecordKind.customer,
        id: 'saved',
        label: 'Customer',
      );
      await other.record(customer);
      await Future.wait([
        for (var index = 0; index < 12; index++)
          history.record((
            kind: RecentRecordKind.job,
            id: 'job-$index',
            label: 'Job $index',
          )),
      ]);
      await history.record(customer);
      await history.record((
        kind: RecentRecordKind.job,
        id: 'job-5',
        label: 'Job 5',
      ));
      final rows = await const LocalRecentRecords('shop', 'owner').load();
      expect(rows.length, 10);
      expect(rows.take(2).map((row) => row.id), ['job-5', 'saved']);
      expect(rows.where((row) => row.id == 'job-5'), hasLength(1));
      await history.clear();
      expect(await history.load(), isEmpty);
      expect(await other.load(), [customer]);
    },
  );

  test(
    'navigation persists order and visibility with access to Settings',
    () async {
      const preferences = ShopNavigationPreferences('shop');
      final initial = await preferences.load();
      await preferences.save([
        (section: ShopNavigationSection.settings, visible: false),
        (section: ShopNavigationSection.home, visible: false),
        ...initial.where(
          (item) => ![
            ShopNavigationSection.settings,
            ShopNavigationSection.home,
          ].contains(item.section),
        ),
      ]);
      final saved = await const ShopNavigationPreferences('shop').load();
      expect(saved.first, (
        section: ShopNavigationSection.settings,
        visible: true,
      ));
      expect(saved[1], (section: ShopNavigationSection.home, visible: false));
      expect(
        saved.map((item) => item.section).toSet(),
        ShopNavigationSection.values.toSet(),
      );
      expect(
        (await const ShopNavigationPreferences('other').load()).first.visible,
        true,
      );
    },
  );
}
