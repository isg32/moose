import 'dart:async';

import 'package:flutter/services.dart';

/// What is installed, as Android sees it.
class Installed {
  const Installed({
    required this.versionCode,
    required this.versionName,
    required this.abi,
    required this.canInstall,
  });

  final int versionCode;
  final String versionName;

  /// The phone's preferred ABI (`arm64-v8a` on nearly every phone).
  final String? abi;

  /// Whether Moose may install APKs ("Install unknown apps").
  final bool canInstall;
}

/// A downloaded APK, as Android reads it.
class ApkCheck {
  const ApkCheck({
    required this.valid,
    this.package,
    this.versionCode = 0,
    this.sameSigner = false,
  });

  final bool valid;
  final String? package;
  final int versionCode;

  /// Signed with the key the installed Moose was signed with, so Android
  /// will let it replace it.
  final bool sameSigner;
}

/// How an install went: [pendingUser] while Android's "Update Moose?"
/// screen is up, then [success] (Moose is replaced and closes) or a
/// failure, [aborted] being "Cancel".
class InstallResult {
  const InstallResult(this.code, [this.message]);

  final int code;
  final String? message;

  static const pendingUser = -1;
  static const success = 0;
  static const aborted = 3;

  bool get failed => code > 0 && code != aborted;
}

/// What over-the-air updates need from the phone (Android's
/// PackageInstaller; see Updater.kt).
abstract interface class UpdatePlatform {
  Future<Installed> info();
  Future<ApkCheck> check(String path);
  Future<void> openInstallSettings();

  /// Starts installing [path]; how it goes arrives on [results].
  Future<void> install(String path);
  Stream<InstallResult> get results;
}

/// [UpdatePlatform] over the `moose/update` channel (Android only).
class ChannelUpdatePlatform implements UpdatePlatform {
  ChannelUpdatePlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'status') {
        final a = Map<String, Object?>.from(call.arguments as Map);
        _results.add(
          InstallResult((a['code'] as num).toInt(), a['message'] as String?),
        );
      }
    });
  }

  static const _channel = MethodChannel('moose/update');
  final _results = StreamController<InstallResult>.broadcast();

  @override
  Stream<InstallResult> get results => _results.stream;

  @override
  Future<Installed> info() async {
    final m = Map<String, Object?>.from(
      (await _channel.invokeMethod<Map<Object?, Object?>>('info'))!,
    );
    return Installed(
      versionCode: (m['versionCode'] as num).toInt(),
      versionName: (m['versionName'] as String?) ?? '',
      abi: m['abi'] as String?,
      canInstall: m['canInstall'] as bool? ?? false,
    );
  }

  @override
  Future<ApkCheck> check(String path) async {
    final m = Map<String, Object?>.from(
      (await _channel.invokeMethod<Map<Object?, Object?>>('check', {
        'path': path,
      }))!,
    );
    return ApkCheck(
      valid: m['valid'] as bool? ?? false,
      package: m['package'] as String?,
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      sameSigner: m['sameSigner'] as bool? ?? false,
    );
  }

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});
}
