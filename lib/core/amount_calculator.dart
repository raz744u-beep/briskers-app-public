/// Small arithmetic parser; never evaluates code or writes financial records.
class AmountCalculator {
  static int cents(String expression, {int? balanceCents}) {
    var source = expression.trim().replaceAll('×', '*').replaceAll('÷', '/')
        .replaceAll('−', '-').replaceAll(RegExp(r'\s+'), '');
    if (balanceCents != null && (source.startsWith('+') || source.startsWith('-'))) {
      source = '${balanceCents / 100}$source';
    }
    final parser = _Arithmetic(source);
    final value = parser.sum();
    if (parser.index != source.length || !value.isFinite || value < 0 || value > 1000000) {
      throw const FormatException('Enter a valid amount from 0 to 1,000,000.');
    }
    // Absorb floating representation noise only at the final cent boundary.
    return (value * 100 + 0.00000001).round();
  }
}

class _Arithmetic {
  _Arithmetic(this.source);
  final String source;
  int index = 0;
  bool take(String token) {
    if (!source.startsWith(token, index)) return false;
    index += token.length;
    return true;
  }
  double sum() {
    var value = product();
    while (index < source.length) {
      final add = take('+');
      if (!add && !take('-')) break;
      final start = index;
      final right = product();
      final expression = source.substring(start, index);
      // Familiar currency-calculator percentages: 100 + 9.75% = 109.75.
      final percentage = expression.endsWith('%') &&
          !expression.contains('*') && !expression.contains('/');
      final delta = percentage ? value * right : right;
      value += add ? delta : -delta;
    }
    return value;
  }
  double product() {
    var value = number();
    while (index < source.length) {
      if (take('*')) {
        value *= number();
      } else if (take('/')) {
        final divisor = number();
        if (divisor == 0) throw const FormatException('Cannot divide by zero.');
        value /= divisor;
      } else {
        break;
      }
    }
    return value;
  }
  double number() {
    final sign = take('-') ? -1.0 : (take('+') ? 1.0 : 1.0);
    final match = RegExp(r'(?:\d+(?:\.\d*)?|\.\d+)').matchAsPrefix(source, index);
    if (match == null) throw const FormatException('Complete the calculation.');
    index = match.end;
    var value = double.parse(match.group(0)!) * sign;
    if (take('%')) value /= 100;
    return value;
  }
}
