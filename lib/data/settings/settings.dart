import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../providers.dart';

part 'settings.g.dart';

/// Small key-value settings. Overridden in tests with an in-memory map.
abstract interface class SettingsStore {
  Future<double?> readDouble(String key);

  Future<void> writeDouble(String key, double value);

  Future<bool?> readBool(String key);

  Future<void> writeBool(String key, bool value);
}

class PrefsSettingsStore implements SettingsStore {
  @override
  Future<double?> readDouble(String key) async =>
      (await SharedPreferences.getInstance()).getDouble(key);

  @override
  Future<void> writeDouble(String key, double value) async =>
      (await SharedPreferences.getInstance()).setDouble(key, value);

  @override
  Future<bool?> readBool(String key) async => (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<void> writeBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);
}

class InMemorySettingsStore implements SettingsStore {
  final Map<String, Object> _values = {};

  @override
  Future<double?> readDouble(String key) async => _values[key] as double?;

  @override
  Future<void> writeDouble(String key, double value) async => _values[key] = value;

  @override
  Future<bool?> readBool(String key) async => _values[key] as bool?;

  @override
  Future<void> writeBool(String key, bool value) async => _values[key] = value;
}

@Riverpod(keepAlive: true)
SettingsStore settingsStore(Ref ref) => PrefsSettingsStore();

/// Spec §3.5: the high-value threshold is user-configurable. Changing it
/// re-flags every item so lists and reports stay consistent.
@Riverpod(keepAlive: true)
class HighValueThreshold extends _$HighValueThreshold {
  static const String key = 'high_value_threshold';

  @override
  double build() {
    ref.read(settingsStoreProvider).readDouble(key).then((v) {
      if (v != null && v > 0) state = v;
    });
    return Limits.defaultHighValueThreshold;
  }

  Future<void> set(double value) async {
    if (value <= 0) return;
    state = value;
    await ref.read(settingsStoreProvider).writeDouble(key, value);
    await ref.read(appDatabaseProvider).itemsDao.recomputeHighValue(value);
  }
}

/// Whether generated PDF reports are copied to the server (on by default;
/// the privacy policy describes it). Photos are never included.
@Riverpod(keepAlive: true)
class CloudBackupEnabled extends _$CloudBackupEnabled {
  static const String key = 'cloud_backup_enabled';

  @override
  bool build() {
    ref.read(settingsStoreProvider).readBool(key).then((v) {
      if (v != null) state = v;
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsStoreProvider).writeBool(key, value);
  }
}
