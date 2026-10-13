import 'dart:convert';

import 'package:crypto/crypto.dart';

/// X-Idempotency-Key (spec §5.1): SHA-256 over the sorted capture hashes.
///
/// Sorting makes the key independent of capture order, so retrying the same
/// set of photos after a dropped connection hits the worker's 24-hour cache
/// instead of spending quota again.
String idempotencyKeyFor(Iterable<String> captureSha256Hexes) {
  final sorted = captureSha256Hexes.map((h) => h.toLowerCase()).toList()
    ..sort();
  return sha256.convert(utf8.encode(sorted.join('\n'))).toString();
}
