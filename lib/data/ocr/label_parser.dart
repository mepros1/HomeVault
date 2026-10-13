/// Pulls serial-number and model candidates out of OCR text from a product
/// label. Pure Dart, unit-tested; the OCR itself is in [OcrEngine].
class LabelInfo {
  const LabelInfo({required this.serials, required this.models});

  /// Best candidate first.
  final List<String> serials;
  final List<String> models;

  bool get isEmpty => serials.isEmpty && models.isEmpty;
}

abstract final class LabelParser {
  static final RegExp _serialLabel = RegExp(
    r'\b(?:S\s*/\s*N|SN|SER(?:IAL)?\.?(?:\s*(?:NO|NUM(?:BER)?))?\.?)\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-/]{4,})',
    caseSensitive: false,
  );
  static final RegExp _modelLabel = RegExp(
    r'\b(?:MODEL|MOD(?:EL)?\.?(?:\s*(?:NO|NUM(?:BER)?))?|M\s*/\s*N|TYPE)\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-/.]{2,})',
    caseSensitive: false,
  );

  /// Bare tokens that look like serials: 6–24 chars, letters and digits,
  /// at least two digits. Pure numbers of 8+ digits also qualify.
  static final RegExp _bareToken = RegExp(r'\b[A-Z0-9][A-Z0-9\-]{5,23}\b');

  /// Common label words that pass the token shape but are never serials.
  static const Set<String> _noise = {
    'MODEL', 'SERIAL', 'NUMBER', 'MADE-IN', 'WARNING', 'CAUTION', 'VOLTAGE',
    'CHINA', 'KOREA', 'JAPAN', 'MEXICO', 'GERMANY', 'ENERGY', 'RATING',
  };

  static LabelInfo parse(String text) {
    final upper = text.toUpperCase();
    final serials = <String>[];
    final models = <String>[];

    for (final m in _serialLabel.allMatches(upper)) {
      _add(serials, m.group(1)!);
    }
    for (final m in _modelLabel.allMatches(upper)) {
      _add(models, m.group(1)!);
    }

    // Fallback: bare tokens with digits, longest first, excluding what we
    // already classified.
    final bare = <String>[];
    for (final m in _bareToken.allMatches(upper)) {
      final token = m.group(0)!;
      final digits = token.replaceAll(RegExp(r'[^0-9]'), '').length;
      final letters = token.replaceAll(RegExp(r'[^A-Z]'), '').length;
      if (_noise.contains(token)) continue;
      if (digits < 2) continue;
      if (letters == 0 && digits < 8) continue; // dates, prices, phone fragments
      if (serials.contains(token) || models.contains(token)) continue;
      _add(bare, token);
    }
    // Mixed letters+digits look more like serials than bare numbers (which
    // are often barcodes or phone fragments); then longer first.
    bare.sort((a, b) {
      final la = RegExp(r'[A-Z]').hasMatch(a) ? 1 : 0;
      final lb = RegExp(r'[A-Z]').hasMatch(b) ? 1 : 0;
      if (la != lb) return lb - la;
      return b.length.compareTo(a.length);
    });
    serials.addAll(bare);

    return LabelInfo(serials: serials, models: models);
  }

  /// Serial and model values always carry at least one digit; words after
  /// "MODEL" such as a country name are not values.
  static void _add(List<String> list, String raw) {
    final value = raw.replaceAll(RegExp(r'[.:]+$'), '');
    if (value.length < 3 || list.contains(value)) return;
    if (!RegExp(r'[0-9]').hasMatch(value)) return;
    list.add(value);
  }
}
