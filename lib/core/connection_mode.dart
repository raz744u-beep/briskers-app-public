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
  // Isolated APK only; a normal release does not define this flag.
  static const bool receiptTestBuild = bool.fromEnvironment('BRISKERS_RECEIPT_TEST');

  BriskersConnectionMode _mode = BriskersConnectionMode.auto;

  int _revision = 0;
  int get revision => _revision;

  BriskersConnectionMode get mode => receiptTestBuild
      ? BriskersConnectionMode.offline : _mode;

  bool get forceOffline => receiptTestBuild || _mode == BriskersConnectionMode.offline;
  bool get forceOnline => !receiptTestBuild && _mode == BriskersConnectionMode.online;

  String get label {
    if (receiptTestBuild) return 'Receipt TEST • Offline';
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

  /// Protect unsent local work if preferences cannot be read at startup.
  /// No settings are deleted or overwritten by this fallback.
  void useSafeOfflineFallback() {
    _revision++;
    _mode = BriskersConnectionMode.offline;
    notifyListeners();
  }

  Future<void> setMode(BriskersConnectionMode value) async {
    if (receiptTestBuild || _mode == value) return;
    _revision++;
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
