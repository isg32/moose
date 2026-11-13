import 'dart:convert';
import 'dart:io';

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

/// On the Linux desktop build (a second Moose on a laptop): a file only
/// you can read, in Moose's data folder. The desktop's keyring isn't
/// always reachable over the Secret Service.
class FileVault implements Vault {
  FileVault(this.path);

  final String path;
  Map<String, String>? _values;

  Future<Map<String, String>> _load() async {
    if (_values case final v?) return v;
    final f = File(path);
    if (!f.existsSync()) return _values = {};
    try {
      return _values = (jsonDecode(await f.readAsString()) as Map)
          .cast<String, String>();
    } on Object {
      return _values = {};
    }
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String? value) async {
    final v = await _load();
    value == null ? v.remove(key) : v[key] = value;
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(v), flush: true);
    await Process.run('chmod', ['600', path]);
  }
}
