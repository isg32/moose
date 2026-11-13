import 'package:flutter/services.dart';

/// "Hide in recent apps" (C36): FLAG_SECURE on Android.
abstract final class SecureWindow {
  static const _channel = MethodChannel('moose/window');

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('secure', on);
    } on MissingPluginException {
      // Tests and other platforms: nothing to hide.
    } on PlatformException {
      // Not worth crashing over.
    }
  }
}
