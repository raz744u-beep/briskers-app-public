import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BriskersConnectionMode {
  auto,
  online,
  offline,
}

class BriskersConnectionModeController extends ChangeNotifier {
  BriskersConnectionModeController._();

  static final BriskersConnectionModeController instance =
      BriskersConnectionModeController._();

  static const _preferenceKey = 'briskers_connection_mode';

  BriskersConnectionMode _mode = BriskersConnectionMode.auto;

  BriskersConnectionMode get mode => _mode;

  bool get forceOffline => _mode == BriskersConnectionMode.offline;
  bool get forceOnline => _mode == BriskersConnectionMode.online;

  String get label {
    switch (_mode) {
      case BriskersConnectionMode.auto:
        return 'Auto';
      case BriskersConnectionMode.online:
        return 'Force Online';
      case BriskersConnectionMode.offline:
        return 'Force Offline';
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_preferenceKey);
    _mode = BriskersConnectionMode.values.firstWhere(
      (value) => value.name == saved,
      orElse: () => BriskersConnectionMode.auto,
    );
  }

  Future<void> setMode(BriskersConnectionMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, value.name);
  }

  void ensureNetworkAllowed() {
    if (forceOffline) {
      throw StateError(
        'Network access is disabled by Settings > Connection Mode > Force Offline.',
      );
    }
  }
}
