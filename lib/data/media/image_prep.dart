import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/constants.dart';

/// An analysis-ready copy of a capture: ≤ 1024 px long side, JPEG, ≤ 400 KB.
class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// JPEG quality actually used (starts at 80, lowered only if needed).
  final int quality;
}

/// Metadata of an original capture (spec §3.2).
class OriginalImageInfo {
  const OriginalImageInfo({
    required this.sha256Hex,
    required this.width,
    required this.height,
  });

  final String sha256Hex;
  final int width;
  final int height;
}

/// Runs off the UI isolate. Original bytes are never modified.
Future<OriginalImageInfo> inspectOriginal(Uint8List originalBytes) =>
    compute(_inspect, originalBytes);

/// Produces the upload copy. Starts at q80 / 1024 px and steps quality down
/// until the file fits the 400 KB contract limit, so the client normally never
/// sees a 413.
Future<PreparedImage> prepareForAnalysis(Uint8List originalBytes) =>
    compute(_prepare, originalBytes);

OriginalImageInfo _inspect(Uint8List bytes) {
  final decoded = _decodeOrThrow(bytes);
  final oriented = img.bakeOrientation(decoded);
  return OriginalImageInfo(
    sha256Hex: sha256.convert(bytes).toString(),
    width: oriented.width,
    height: oriented.height,
  );
}

PreparedImage _prepare(Uint8List bytes) {
  final decoded = _decodeOrThrow(bytes);
  final oriented = img.bakeOrientation(decoded);

  final longSide = oriented.width > oriented.height ? oriented.width : oriented.height;
  final resized = longSide > Limits.analysisLongSidePx
      ? (oriented.width >= oriented.height
          ? img.copyResize(oriented, width: Limits.analysisLongSidePx)
          : img.copyResize(oriented, height: Limits.analysisLongSidePx))
      : oriented;

  var quality = Limits.analysisJpegQuality;
  Uint8List encoded = img.encodeJpg(resized, quality: quality);
  while (encoded.length > Limits.maxAnalysisImageBytes && quality > 40) {
    quality -= 10;
    encoded = img.encodeJpg(resized, quality: quality);
  }
  return PreparedImage(
    bytes: encoded,
    width: resized.width,
    height: resized.height,
    quality: quality,
  );
}

/// Long side of list/report thumbnails.
const int thumbnailLongSidePx = 320;

/// Small preview for lists and the report table (orientation baked in).
Future<Uint8List> makeThumbnail(Uint8List originalBytes) =>
    compute(_thumbnail, originalBytes);

Uint8List _thumbnail(Uint8List bytes) {
  final decoded = _decodeOrThrow(bytes);
  final oriented = img.bakeOrientation(decoded);
  final resized = oriented.width >= oriented.height
      ? img.copyResize(oriented, width: thumbnailLongSidePx)
      : img.copyResize(oriented, height: thumbnailLongSidePx);
  return img.encodeJpg(resized, quality: 75);
}

/// `image` throws assorted RangeErrors on garbage input; callers only want
/// one failure type.
img.Image _decodeOrThrow(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) throw const FormatException('Unsupported image');
  return decoded;
}
