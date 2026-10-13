import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What the app keeps between launches to identify itself to the server.
class StoredCredentials {
  const StoredCredentials({
    required this.deviceId,
    this.deviceSecret,
    this.accessToken,
    this.userId,
  });

  /// Generated once per install; never changes afterwards.
  final String deviceId;

  /// Independent random credential; unlike the public device id, never share it.
  final String? deviceSecret;

  /// Bearer token issued by the server, or null before first registration.
  final String? accessToken;
  final String? userId;

  bool get hasToken => accessToken != null && accessToken!.isNotEmpty;

  StoredCredentials copyWith({String? accessToken, String? userId, String? deviceSecret}) =>
      StoredCredentials(
        deviceId: deviceId,
        deviceSecret: deviceSecret ?? this.deviceSecret,
        accessToken: accessToken ?? this.accessToken,
        userId: userId ?? this.userId,
      );
}

abstract interface class CredentialStore {
  Future<StoredCredentials?> read();

  Future<void> write(StoredCredentials credentials);

  Future<void> clear();
}

/// Android Keystore-backed storage via flutter_secure_storage.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _kDeviceId = 'device_id';
  static const _kDeviceSecret = 'device_secret';
  static const _kAccessToken = 'access_token';
  static const _kUserId = 'user_id';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredCredentials?> read() async {
    final deviceId = await _storage.read(key: _kDeviceId);
    if (deviceId == null || deviceId.isEmpty) return null;
    return StoredCredentials(
      deviceId: deviceId,
      deviceSecret: await _storage.read(key: _kDeviceSecret),
      accessToken: await _storage.read(key: _kAccessToken),
      userId: await _storage.read(key: _kUserId),
    );
  }

  @override
  Future<void> write(StoredCredentials c) async {
    await _storage.write(key: _kDeviceId, value: c.deviceId);
    await _storage.write(key: _kDeviceSecret, value: c.deviceSecret);
    await _storage.write(key: _kAccessToken, value: c.accessToken);
    await _storage.write(key: _kUserId, value: c.userId);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// For tests and previews.
class InMemoryCredentialStore implements CredentialStore {
  StoredCredentials? _value;

  @override
  Future<StoredCredentials?> read() async => _value;

  @override
  Future<void> write(StoredCredentials credentials) async =>
      _value = credentials;

  @override
  Future<void> clear() async => _value = null;
}
