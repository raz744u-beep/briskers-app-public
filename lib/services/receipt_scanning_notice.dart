import 'package:shared_preferences/shared_preferences.dart';

class ReceiptScanningNotice {
  static Future<bool> shown(String business) async =>
      (await SharedPreferences.getInstance()).getBool('receipt_scan_notice:$business') ?? true;

  static Future<bool> setShown(String business, bool value) async =>
      (await SharedPreferences.getInstance()).setBool('receipt_scan_notice:$business', value);
}
