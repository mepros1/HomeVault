/// Product-wide constants. Values come from the spec; change here, not inline.
abstract final class Limits {
  /// Spec §3.2: minimum / recommended / maximum captures per room.
  static const int minCapturesPerRoom = 3;
  static const int recommendedCapturesPerRoom = 4;
  static const int maxCapturesPerRoom = 8;

  /// Spec §3.2: analysis copy is 1024 px on the long side, JPEG q80.
  static const int analysisLongSidePx = 1024;
  static const int analysisJpegQuality = 80;

  /// Spec §5.1: each uploaded image must be ≤ 400 KB.
  static const int maxAnalysisImageBytes = 400 * 1024;

  /// Spec §3.4: items below this confidence need explicit confirmation.
  static const double lowConfidenceThreshold = 0.6;

  /// Spec §3.5: default high-value threshold, user-configurable.
  static const double defaultHighValueThreshold = 1500;

  /// Spec §5.1: retry 502/504 with exponential backoff, at most 3 attempts.
  static const int maxAnalyzeAttempts = 3;
  static const Duration analyzeBaseBackoff = Duration(seconds: 2);
  static const Duration analyzeTimeout = Duration(seconds: 45);

  /// Spec §7: free tier is limited to one room.
  static const int freeTierRooms = 1;
}

abstract final class Defaults {
  static const String currency = 'USD';
}

/// Spec §8: shown in the app and printed in every report.
abstract final class Disclaimer {
  static const String short =
      'Not an appraisal. Not insurance advice. '
      'Estimated replacement values are for reference only.';

  static const String aiDisclosure =
      'Items and estimates were generated automatically from your photos '
      'and must be reviewed before use.';
}
