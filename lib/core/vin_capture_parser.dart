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
