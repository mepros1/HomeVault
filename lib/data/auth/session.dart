import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/env.dart';
import '../providers.dart';
import 'credential_store.dart';
import 'device_auth_client.dart';

part 'session.g.dart';

enum SessionStatus {
  /// Credentials not loaded yet.
  loading,

  /// Registration in flight (first launch, or re-issue after a 401).
  registering,

  /// A token is available.
  ready,

  /// Registration failed; [SessionState.error] has the cause. Retry later.
  failed,
}

@immutable
class SessionState {
  const SessionState({required this.status, this.userId, this.error});

  final SessionStatus status;
  final String? userId;
  final Object? error;

  bool get isReady => status == SessionStatus.ready;
}

@Riverpod(keepAlive: true)
CredentialStore credentialStore(Ref ref) => SecureCredentialStore();

@Riverpod(keepAlive: true)
DeviceAuthClient deviceAuthClient(Ref ref) {
  final client = DeviceAuthClient(
    endpoint: Env.registerDeviceEndpoint,
    appCheck: ref.watch(appCheckProvider),
  );
  ref.onDispose(client.close);
  return client;
}

/// Owns the device identity and bearer token.
///
/// Flow: on first use, generate a device id, register with the server, store
/// the token. Later launches reuse the stored token. A 401 from any API call
/// goes through [reissueToken], which registers the same device id again and
/// gets a fresh token for the same user.
@Riverpod(keepAlive: true)
class Session extends _$Session {
  StoredCredentials? _credentials;
  Future<String>? _inFlight;
  Future<StoredCredentials>? _identityInFlight;

  @override
  SessionState build() => const SessionState(status: SessionStatus.loading);

  /// The current token, registering the device first if there is none.
  /// Concurrent callers share one registration request.
  Future<String> accessToken() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  /// Forces a new token for the same device. Used after a 401.
  Future<String> reissueToken() {
    return _inFlight ??= _register().whenComplete(() => _inFlight = null);
  }

  /// The device id, created and persisted on first call. Does not register
  /// with the server; a later [accessToken] registers this same id.
  Future<String> deviceId() async {
    return (await _ensureIdentity()).deviceId;
  }

  Future<StoredCredentials> _ensureIdentity() =>
      _identityInFlight ??= _loadIdentity().whenComplete(() => _identityInFlight = null);

  Future<StoredCredentials> _loadIdentity() async {
    final store = ref.read(credentialStoreProvider);
    _credentials ??= await store.read();
    if (_credentials == null) {
      _credentials = StoredCredentials(deviceId: const Uuid().v4(), deviceSecret: _newSecret());
      await store.write(_credentials!);
    } else if (_credentials!.deviceSecret == null) {
      // Local legacy installs require server-side migration/reset before renewal.
      // Never let this new secret silently take ownership of an old server id.
      _credentials = _credentials!.copyWith(deviceSecret: _newSecret());
      await store.write(_credentials!);
    }
    return _credentials!;
  }

  /// Forgets identity and token. Mostly for debugging and tests.
  Future<void> reset() async {
    await ref.read(credentialStoreProvider).clear();
    _credentials = null;
    state = const SessionState(status: SessionStatus.loading);
  }

  Future<String> _load() async {
    final c = await _ensureIdentity();
    if (c.hasToken) {
      state = SessionState(status: SessionStatus.ready, userId: c.userId);
      return c.accessToken!;
    }
    return _register();
  }

  Future<String> _register() async {
    final store = ref.read(credentialStoreProvider);
    final credentials = await _ensureIdentity();
    final deviceId = credentials.deviceId;
    state = SessionState(status: SessionStatus.registering, userId: _credentials?.userId);
    try {
      final result = await ref.read(deviceAuthClientProvider).register(
            deviceId: deviceId,
            deviceSecret: credentials.deviceSecret!,
            platform: defaultTargetPlatform.name,
          );
      final updated = _credentials!.copyWith(
        accessToken: result.accessToken,
        userId: result.userId,
      );
      await store.write(updated);
      _credentials = updated;
      state = SessionState(status: SessionStatus.ready, userId: result.userId);
      return result.accessToken;
    } catch (e) {
      // Keep the device id so a later retry registers the same identity.
      await store.write(_credentials!);
      state = SessionState(status: SessionStatus.failed, userId: _credentials?.userId, error: e);
      rethrow;
    }
  }

  static String _newSecret() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
  }
}
