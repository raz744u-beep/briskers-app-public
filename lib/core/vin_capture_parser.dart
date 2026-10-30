/// Extract real 17-character VIN candidates without silently truncating,
/// guessing ambiguous O/0 or I/1, or accepting unrelated product barcodes.
///
/// For older/nonstandard vehicles the Add Vehicle form still permits typing
/// manually; camera acceptance requires the modern 17-character VIN format.
class VinCaptureParser {
  static final RegExp _valid = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static final RegExp _tokens = RegExp(r'[A-Z0-9]+');
  static final RegExp _vinLabel = RegExp(r'\bVIN\b\s*[:#=-]?\s*');

  static String normalize(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool isValid(String candidate) => _valid.hasMatch(candidate);

  // 49 CFR 565 VIN transliteration and position weights. All calculations
  // happen on-device; no lookup, OCR cloud call, or network dependency.
  static const List<int> _checkWeights = [
    8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2,
  ];
  static const Map<String, int> _letterValues = {
    'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5,
    'F': 6, 'G': 7, 'H': 8, 'J': 1, 'K': 2,
    'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9,
    'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6,
    'X': 7, 'Y': 8, 'Z': 9,
  };

  /// Check digits apply to US-market 17-character VINs. A mismatch is
  /// suspicious, but some imported vehicles do not use the US convention.
  /// Caller must warn and require explicit review rather than silently
  /// changing characters or discarding manually entered VINs.
  static bool hasValidCheckDigit(String candidate) {
    if (!isValid(candidate)) return false;
    var sum = 0;
    for (var index = 0; index < candidate.length; index++) {
      final character = candidate[index];
      final value = int.tryParse(character) ?? _letterValues[character];
      if (value == null) return false;
      sum += value * _checkWeights[index];
    }
    final remainder = sum % 11;
    final expected = remainder == 10 ? 'X' : remainder.toString();
    return candidate[8] == expected;
  }

  /// Prefer mathematically consistent readings, while preserving an OCR
  /// mismatch so the operator can see and manually repair the captured VIN.
  static List<String> preferVerified(Iterable<String> values) {
    final ranked = values.toSet().toList();
    ranked.sort((a, b) =>
        (hasValidCheckDigit(b) ? 1 : 0)
            .compareTo(hasValidCheckDigit(a) ? 1 : 0));
    return ranked;
  }

  static List<String> fromBarcodeValues(Iterable<String?> values) {
    final found = <String>{};
    for (final raw in values) {
      if (raw == null || raw.trim().isEmpty) continue;
      final capital = raw.trim().toUpperCase();
      final tagged = capital.replaceFirst(
        RegExp(r'^\s*\*?\s*VIN\s*[:#=-]?\s*'),
        '',
      );
      // Code39 often surrounds its data in asterisks. A complete
      // well-defined VIN may be carried inside this wrapper, not a guess.
      final trimmed = tagged.replaceAll(RegExp(r'^\*|\*$'), '').trim();
      final asOne = normalize(trimmed);
      if (isValid(asOne)) found.add(asOne);
      // A carrier may contain other labels/codes; only complete isolated
      // VIN tokens are accepted. NEVER substring an arbitrary long code.
      found.addAll(fromTextLines([capital]));
    }
    return found.toList(growable: false);
  }

  static List<String> fromTextLines(Iterable<String> lines) {
    final found = <String>{};
    for (final raw in lines) {
      final line = raw.toUpperCase().trim();
      if (line.isEmpty) continue;
      final tokens = _tokens.allMatches(line)
          .map((match) => match.group(0)!)
          .toList();
      for (final token in tokens) {
        if (isValid(token)) found.add(token);
      }
      // OCR often puts spaces/dashes between VIN character groups.
      // Accept this only when the whole line, or the whole VIN-labeled
      // suffix, resolves to EXACTLY 17 valid characters.
      final compact = normalize(line);
      if (isValid(compact)) found.add(compact);
      final match = _vinLabel.firstMatch(line);
      if (match != null) {
        final afterLabel = normalize(line.substring(match.end));
        if (isValid(afterLabel)) found.add(afterLabel);
      }
    }
    return found.toList(growable: false);
  }
}
