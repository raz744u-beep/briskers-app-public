import 'package:shared_preferences/shared_preferences.dart';

class ReceiptScanningNotice {
  static Future<bool> shown(String business) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('receipt_scan_notice:$business') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> setShown(String business, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool('receipt_scan_notice:$business', value);
    } catch (_) {
      return false;
    }
  }
}
