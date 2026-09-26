import 'package:flutter/services.dart';

String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

String formatUsPhone(String? value) {
  if (value == null) return '';
  final digits = digitsOnly(value);
  if (digits.length < 4) return digits;
  if (digits.length < 7) {
    return '${digits.substring(0, 3)}-${digits.substring(3)}';
  }
  final clipped = digits.length > 10 ? digits.substring(0, 10) : digits;
  return '${clipped.substring(0, 3)}-${clipped.substring(3, 6)}-${clipped.substring(6)}';
}

class UsPhoneTextInputFormatter extends TextInputFormatter {
  const UsPhoneTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = digitsOnly(newValue.text);
    if (digits.length > 10) digits = digits.substring(0, 10);

    final formatted = formatUsPhone(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class VinTextInputFormatter extends TextInputFormatter {
  const VinTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var cleaned = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length > 17) cleaned = cleaned.substring(0, 17);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

String normalizeVin(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
