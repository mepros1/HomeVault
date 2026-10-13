import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Source of `X-App-Check` tokens (Play Integrity, spec §6).
///
/// A token is bound to a request hash: the device id for registration, the
/// idempotency key for analysis. Returning null means "send no header"; the
/// server decides (log or reject) according to its `APP_CHECK_MODE`.
abstract interface class AppCheck {
  /// Warm up; safe to call repeatedly and to ignore the result.
  Future<void> prepare();

  Future<String?> token(String requestHash);
}

/// No Play Integrity: builds without `PLAY_INTEGRITY_PROJECT_NUMBER`, tests.
class NoopAppCheck implements AppCheck {
  const NoopAppCheck();

  @override
  Future<void> prepare() async {}

  @override
  Future<String?> token(String requestHash) async => null;
}

/// Play Integrity standard API through `MainActivity.kt`.
class PlayIntegrityAppCheck implements AppCheck {
  PlayIntegrityAppCheck({required this.cloudProjectNumber, MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('homevault/app_check');

  static const Duration prepareTimeout = Duration(seconds: 20);
  static const Duration tokenTimeout = Duration(seconds: 10);

  final int cloudProjectNumber;
  final MethodChannel _channel;
  Future<bool>? _prepared;

  @override
  Future<void> prepare() => _ensurePrepared().then((_) {});

  Future<bool> _ensurePrepared() {
    return _prepared ??= _channel
        .invokeMethod<bool>('prepare', {'cloudProjectNumber': cloudProjectNumber})
        .timeout(prepareTimeout)
        .then((ok) => ok ?? false)
        .catchError((Object e) {
      debugPrint('Play Integrity prepare failed: $e');
      _prepared = null; // allow a later retry
      return false;
    });
  }

  @override
  Future<String?> token(String requestHash) async {
    if (!await _ensurePrepared()) return null;
    try {
      return await _channel
          .invokeMethod<String>('token', {'requestHash': requestHash})
          .timeout(tokenTimeout);
    } on Exception catch (e) {
      debugPrint('Play Integrity token failed: $e');
      return null;
    }
  }
}

/// Test double: returns [nextToken] and records the hashes it was asked for.
class FakeAppCheck implements AppCheck {
  FakeAppCheck({this.nextToken});

  String? nextToken;
  final List<String> requestedHashes = [];
  int prepares = 0;

  @override
  Future<void> prepare() async => prepares++;

  @override
  Future<String?> token(String requestHash) async {
    requestedHashes.add(requestHash);
    return nextToken;
  }
}
