import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/friday_closeout_schedule.dart';

class FridayCloseoutPreferences {
  const FridayCloseoutPreferences(this.businessId);
  final String businessId;

  static final _changes = StreamController<String>.broadcast();
  static Stream<String> get changes => _changes.stream;

  String get _key => 'briskers_friday_closeout_v1_$businessId';
  String get _regularKey => '${_key}_regular_friday';

  Future<FridayCloseoutSchedule> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_key);
    if (saved == null || saved == 0 || saved.abs() > 24 * 60) {
      return const FridayCloseoutSchedule();
    }
    return FridayCloseoutSchedule(
      enabled: saved > 0,
      startMinute: saved.abs() - 1,
    );
  }

  Future<void> save(FridayCloseoutSchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    // Store the switch and time together. A disabled schedule retains its time.
    final value = (schedule.startMinute + 1) * (schedule.enabled ? 1 : -1);
    if (!await prefs.setInt(_key, value)) {
      throw StateError('Friday Closeout preference could not be saved.');
    }
    _changes.add(businessId);
  }

  Future<String?> regularFriday() async =>
      (await SharedPreferences.getInstance()).getString(_regularKey);

  Future<void> showRegularFor(String? friday) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = friday == null
        ? await prefs.remove(_regularKey)
        : await prefs.setString(_regularKey, friday);
    if (!saved) throw StateError('Dashboard view could not be saved.');
  }
}
