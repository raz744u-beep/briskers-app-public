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

String formatWarrantyPhone(String? value) {
  if (value == null) return '';
  var digits = digitsOnly(value);

  final hasCountryCode = digits.length >= 11 && digits.startsWith('1');
  if (hasCountryCode) {
    digits = digits.substring(0, 11);
    final national = digits.substring(1);
    return '1-${national.substring(0, 3)}-${national.substring(3, 6)}-${national.substring(6)}';
  }

  if (digits.length < 4) return digits;
  if (digits.length < 7) {
    return '${digits.substring(0, 3)}-${digits.substring(3)}';
  }

  if (digits.length > 10) digits = digits.substring(0, 10);
  return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
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

class WarrantyPhoneTextInputFormatter extends TextInputFormatter {
  const WarrantyPhoneTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = digitsOnly(newValue.text);
    final maxDigits = digits.startsWith('1') ? 11 : 10;
    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }

    final formatted = formatWarrantyPhone(digits);
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

class FirstLetterCapitalizationFormatter extends TextInputFormatter {
  const FirstLetterCapitalizationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    var start = 0;
    for (final rune in newValue.text.runes) {
      final letter = String.fromCharCode(rune);
      final uppercase = letter.toUpperCase();
      final end = start + letter.length;
      if (letter.toLowerCase() != uppercase) {
        if (uppercase == letter) return newValue;
        final change = uppercase.length - letter.length;
        int shift(int offset) => offset >= end ? offset + change : offset;
        final selection = newValue.selection;
        return newValue.copyWith(
          text: newValue.text.replaceRange(start, end, uppercase),
          selection: TextSelection(
            baseOffset: shift(selection.baseOffset),
            extentOffset: shift(selection.extentOffset),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          ),
          composing: TextRange.empty,
        );
      }
      start = end;
    }
    return newValue;
  }
}
