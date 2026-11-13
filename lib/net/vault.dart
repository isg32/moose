import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets that stay on this phone: the hidden account, the session
/// cookie and the identity key. Android Keystore-backed in the app.
abstract interface class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureVault implements Vault {
  const SecureVault();

  static const _store = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _store.read(key: key);

  @override
  Future<void> write(String key, String? value) => value == null
      ? _store.delete(key: key)
      : _store.write(key: key, value: value);
}

/// For tests, and for a second pretend phone in end-to-end runs.
class MemoryVault implements Vault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}
